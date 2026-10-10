extends Node
## Build view: the shop from straight above as a floor plan. B (or BUILD / PLACE / MOVE on the
## supply website) eases the camera up over the room, hides everything overhead and frees the
## cursor. On the plan the player plops square expansions down against the floor
## (`shop_inventory.build_expansion`), picks placed equipment up to move or rotate it, stashes it
## back into storage and places stored equipment. WASD or a middle drag pans and the wheel zooms;
## Esc, Q or right-click steps back, and B leaves. The side panel lists the same actions.
signal toggled(active: bool)

const Starter = preload("res://scripts/starter_shop.gd")
const UI = preload("res://scripts/screen_ui.gd")
const GRID_SHADER = preload("res://shaders/build_grid.gdshader")
const EASE_TIME := 0.5
## Ceilings, beams, lintels and lamps start above this height and are hidden from the plan.
const OVERHEAD_Y := 9.5
## Plan heights the camera may zoom between, above the floor.
const HEIGHT_RANGE := Vector2(20.0, 200.0)
## Panning speed in camera heights per second.
const PAN_SPEED := 0.9
const PANEL_WIDTH := 300.0
const GOOD := Color(0.25, 0.85, 0.5, 0.4)
const BAD := Color(0.9, 0.25, 0.15, 0.4)
const HOVER := Color(0.95, 0.82, 0.35, 0.35)
const PANEL_BG := Color(0.06, 0.08, 0.09, 0.92)
const TEXT := Color("#e6ece8")
const MUTED := Color("#8fa39b")
const ACCENT := Color("#2f8f83")
const WARM := Color("#b8743a")

var bench: Node3D
var shop: Node
var active := false
## "" arranges equipment; "expansion" offers a square to plop down.
var mode := ""
## Plan point under the screen centre, and the camera's height above the floor.
var focus := Vector2.ZERO
var height := 80.0
var pointer := Vector2.ZERO
## The mouse has been over the plan since opening.
var pointing := false
var motion: Tween
var hidden_overhead: Array[Node3D] = []
var square := Rect2()
var square_valid := false
var hover_id := ""
var ghost: MeshInstance3D
var ghost_material: StandardMaterial3D
var ghost_label: Label3D
var grid: MeshInstance3D
var ground: MeshInstance3D
var player_marker: MeshInstance3D
var layer: CanvasLayer
var list: VBoxContainer
var hint: Label

func configure(world: Node3D) -> void:
	bench = world
	shop = world.shop
	ghost = MeshInstance3D.new()
	ghost.name = "BuildGhost"
	var slab := BoxMesh.new()
	slab.size = Vector3(1, 0.06, 1)
	ghost.mesh = slab
	ghost_material = unshaded(GOOD, true)
	ghost.material_override = ghost_material
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bench.add_child(ghost)
	ghost_label = Label3D.new()
	ghost_label.name = "BuildGhostLabel"
	ghost_label.font_size = 48
	ghost_label.pixel_size = 0.04
	ghost_label.outline_size = 10
	ghost_label.no_depth_test = true
	ghost_label.rotation.x = -PI * 0.5
	bench.add_child(ghost_label)
	grid = MeshInstance3D.new()
	grid.name = "BuildGrid"
	var plane := PlaneMesh.new()
	plane.size = Starter.LOT.size
	grid.mesh = plane
	var grid_material := ShaderMaterial.new()
	grid_material.shader = GRID_SHADER
	grid.material_override = grid_material
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grid.position = Vector3(Starter.LOT.get_center().x, Starter.FLOOR_Y + 0.015, Starter.LOT.get_center().y)
	bench.add_child(grid)
	# Plain ground under the lot, below every floor, so the plan never shows the sky dome.
	ground = MeshInstance3D.new()
	ground.name = "BuildGround"
	var field := PlaneMesh.new()
	field.size = Vector2(900, 900)
	ground.mesh = field
	ground.material_override = unshaded(Color("#2a332d"), false)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.position = Vector3(Starter.LOT.get_center().x, Starter.FLOOR_Y - 0.4, Starter.LOT.get_center().y)
	bench.add_child(ground)
	# Where the player stands, with a pointer for the way they face.
	player_marker = MeshInstance3D.new()
	player_marker.name = "BuildPlayerMarker"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.9
	disc.bottom_radius = 0.9
	disc.height = 0.05
	player_marker.mesh = disc
	player_marker.material_override = unshaded(Color("#f2b44a"), false)
	player_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var facing := MeshInstance3D.new()
	var arrow := BoxMesh.new()
	arrow.size = Vector3(0.35, 0.05, 1.3)
	facing.mesh = arrow
	facing.position = Vector3(0, 0, -1.1)
	facing.material_override = player_marker.material_override
	player_marker.add_child(facing)
	bench.add_child(player_marker)
	build_panel()
	shop.changed.connect(refresh_panel)
	set_visuals(false)

static func unshaded(color: Color, transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	if transparent: material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func set_visuals(value: bool) -> void:
	grid.visible = value
	ground.visible = value
	player_marker.visible = value
	layer.visible = value
	if not value:
		ghost.hide()
		ghost_label.hide()

# --- Entering and leaving ------------------------------------------------------------------

## Opens the plan, optionally offering an expansion square (`"expansion"`) or holding the
## equipment `id` ready to place. Hands must be empty.
func open(new_mode := "", id := "") -> bool:
	if not active:
		if shop.hands_busy() or not bench.settled(): return false
		if bench.computer.in_use:
			bench.computer.leave()
			if bench.computer.motion != null: bench.computer.motion.kill()
		active = true
		pointing = false
		hide_overhead()
		fit()
		var rig: Node = bench.camera_rig
		var start: Transform3D = rig.camera.global_transform
		rig.anchor = start
		rig.anchor_weight = 1.0
		ease_camera(func(t: float):
			rig.anchor = start.interpolate_with(top_pose(), t)
			rig.update_camera())
		rig.set_captured(false)
		bench.hud.set_computer_mode(true)
		set_visuals(true)
		toggled.emit(true)
	set_mode(new_mode, id)
	return true

func close() -> void:
	if not active: return
	if shop.placement_id != "": shop.cancel_placement()
	mode = ""
	active = false
	shop.hide_preview()
	set_visuals(false)
	var rig: Node = bench.camera_rig
	rig.anchor = top_pose()
	if motion != null: motion.kill()
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	motion.tween_property(rig, "anchor_weight", 0.0, EASE_TIME)
	motion.tween_callback(func(): if not active: restore_overhead())
	rig.set_captured(true)
	bench.hud.set_computer_mode(false)
	bench.refresh_ui()
	toggled.emit(false)

func ease_camera(step: Callable) -> void:
	if motion != null: motion.kill()
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	motion.tween_method(step, 0.0, 1.0, EASE_TIME)

func set_mode(new_mode: String, id := "") -> void:
	if shop.placement_id != "" and shop.placement_id != id: shop.cancel_placement()
	mode = ""
	if new_mode == "expansion":
		var block: String = shop.expansion_block()
		if block != "": bench.hud.set_status(block)
		else:
			mode = "expansion"
			bench.hud.set_status("Plop the %s square down against the shop. Click to build, Esc or right-click to stop." % size_text())
	if id != "" and shop.placement_id != id: shop.begin_placement(id)
	refresh_panel()
	update_pointer()

func size_text() -> String:
	return "%.1f x %.1f m" % [Starter.EXPANSION_SIZE * 0.2, Starter.EXPANSION_SIZE * 0.2]

## Anything overhead in the room is hidden while the plan is open, then restored.
func hide_overhead() -> void:
	for mesh in bench.get_node("ShopInterior").find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		if bounds.position.y >= OVERHEAD_Y:
			mesh.hide()
			hidden_overhead.append(mesh)

func restore_overhead() -> void:
	for mesh in hidden_overhead:
		if is_instance_valid(mesh): mesh.show()
	hidden_overhead.clear()

# --- Camera ----------------------------------------------------------------------------------

func top_pose() -> Transform3D:
	return Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), Vector3(focus.x, Starter.FLOOR_Y + height, focus.y))

## Frames the built floor and, while squares remain, the lot beside it, left of the panel.
func fit() -> void:
	var bounds := Starter.ROOM
	for rect in Starter.rooms(shop.expansion_squares): bounds = bounds.merge(rect)
	if shop.expansions < Starter.MAX_EXPANSIONS:
		var reach := Starter.EXPANSION_SIZE * 0.6
		bounds = bounds.grow_individual(reach, reach, 0, 0).intersection(Starter.LOT)
	bounds = bounds.grow(6.0)
	var view: Vector2 = bench.get_viewport().get_visible_rect().size
	var share := 1.0 - PANEL_WIDTH / view.x
	var tangent := tan(deg_to_rad(bench.camera_rig.camera.fov) * 0.5)
	var aspect := view.x / view.y
	# Fitted at the wall tops, which sit nearer the camera than the floor.
	var walls := Starter.CEILING_Y - Starter.FLOOR_Y
	height = clampf(maxf(bounds.size.y * 0.5 / tangent, bounds.size.x * 0.5 / (tangent * aspect * share)) + walls, HEIGHT_RANGE.x, HEIGHT_RANGE.y)
	var world_width := 2.0 * height * tangent * aspect
	focus = bounds.get_center() + Vector2((1.0 - share) * 0.5 * world_width, 0)

## Eases to a fresh fit, after the plan has grown.
func reframe() -> void:
	var start := top_pose()
	fit()
	var target := top_pose()
	ease_camera(func(t: float):
		bench.camera_rig.anchor = start.interpolate_with(target, t)
		bench.camera_rig.update_camera())

func apply_camera() -> void:
	var limit := Starter.LOT.grow(20.0)
	focus = focus.clamp(limit.position, limit.end)
	if motion != null and motion.is_running(): return
	bench.camera_rig.anchor = top_pose()
	bench.camera_rig.update_camera()

func zoom(factor: float) -> void:
	height = clampf(height * factor, HEIGHT_RANGE.x, HEIGHT_RANGE.y)
	apply_camera()

func world_per_pixel() -> float:
	return 2.0 * height * tan(deg_to_rad(bench.camera_rig.camera.fov) * 0.5) / bench.get_viewport().get_visible_rect().size.y

## The floor point under a screen position, or null.
func floor_point(screen: Vector2) -> Variant:
	var camera: Camera3D = bench.camera_rig.camera
	return Plane(Vector3.UP, Starter.FLOOR_Y).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))

func _process(delta: float) -> void:
	if not active: return
	var pan := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if pan != Vector2.ZERO:
		focus += pan.normalized() * height * PAN_SPEED * delta
		apply_camera()
	var body: Node3D = bench.camera_rig.body
	player_marker.global_position = Vector3(body.global_position.x, Starter.FLOOR_Y + 0.08, body.global_position.z)
	player_marker.rotation.y = bench.camera_rig.look_yaw
	update_pointer()

# --- Pointer and actions ---------------------------------------------------------------------

## Follows the pointer: the equipment being placed, the offered square or the hovered piece.
func update_pointer() -> void:
	ghost.hide()
	ghost_label.hide()
	hover_id = ""
	square_valid = false
	var point = floor_point(pointer) if active and pointing else null
	if point == null:
		shop.hide_preview()
		update_hint()
		return
	var at := Vector2(point.x, point.z)
	if shop.placement_id != "":
		shop.preview_at(point)
	elif mode == "expansion":
		square = Starter.expansion_at(shop.expansion_squares, at)
		square_valid = Starter.expansion_fits(shop.expansion_squares, square)
		show_ghost(square, GOOD if square_valid else BAD)
		ghost_label.text = "%s\n$%d" % [size_text(), shop.CATALOG[shop.EXPANSION].price]
		ghost_label.global_position = Vector3(square.get_center().x, Starter.FLOOR_Y + 0.2, square.get_center().y)
		ghost_label.show()
	else:
		hover_id = shop.placed_at(at)
		if hover_id != "": show_ghost(shop.room_rect(shop.equipment[hover_id]).grow(0.3), HOVER)
	update_hint()

func show_ghost(rect: Rect2, color: Color) -> void:
	ghost.position = Vector3(rect.get_center().x, Starter.FLOOR_Y + 0.06, rect.get_center().y)
	ghost.scale = Vector3(rect.size.x, 1, rect.size.y)
	ghost_material.albedo_color = color
	ghost.show()

func update_hint() -> void:
	if hint == null: return
	if shop.placement_id != "":
		hint.text = "%s: click a clear floor spot   R: rotate   %sEsc / right-click: cancel" % [shop.item_name(shop.placement_id), "" if shop.FIXTURES.has(shop.placement_id) else "X: stash   "]
	elif mode == "expansion":
		hint.text = ("Click to build here" if square_valid else "Move along the outside of the shop: squares join behind or left of it") + "   Esc / right-click: stop"
	elif hover_id != "":
		hint.text = "%s: click to move%s" % [shop.item_name(hover_id), "" if shop.FIXTURES.has(hover_id) else "   X: stash in storage"]
	else:
		hint.text = "Click equipment to move it   WASD / middle drag: pan   Wheel: zoom   B: back to the shop"

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer = event.position
		pointing = true
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			focus -= event.relative * world_per_pixel()
			apply_camera()
		update_pointer()
	elif event is InputEventMouseButton and event.pressed:
		pointer = event.position
		pointing = true
		match event.button_index:
			MOUSE_BUTTON_LEFT: click()
			MOUSE_BUTTON_RIGHT: back()
			MOUSE_BUTTON_WHEEL_UP: zoom(0.9)
			MOUSE_BUTTON_WHEEL_DOWN: zoom(1.0 / 0.9)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_B, KEY_TAB: close()
			KEY_ESCAPE, KEY_Q: back()
			KEY_E: click()
			KEY_R:
				shop.rotate_placement()
				update_pointer()
			KEY_X, KEY_DELETE: stash_pointed()
			KEY_M: bench.hud.mute_requested.emit()

## Places the held equipment, builds the offered square or picks up the hovered piece.
func click() -> void:
	update_pointer()
	if shop.placement_id != "":
		if not shop.finish_placement():
			bench.hud.set_status("No room there: keep clear of walls, furniture, the door, the hatch counter and yourself.")
	elif mode == "expansion":
		if not square_valid:
			bench.hud.set_status("An expansion must join the shop flush along a wall, behind the front wall and left of the window.")
		elif shop.build_expansion(square):
			mode = ""
			hide_overhead()
			reframe()
	elif hover_id != "":
		shop.begin_placement(hover_id)
	refresh_panel()
	update_pointer()

## One step back: drop the held equipment, stop offering a square, then leave.
func back() -> void:
	if shop.placement_id != "": shop.cancel_placement()
	elif mode != "": mode = ""
	else:
		close()
		return
	refresh_panel()
	update_pointer()

func stash_pointed() -> void:
	var id: String = shop.placement_id if shop.placement_id != "" else hover_id
	if id != "" and shop.stash(id): update_pointer()

# --- Side panel ------------------------------------------------------------------------------

func build_panel() -> void:
	layer = CanvasLayer.new()
	layer.name = "BuildViewUI"
	layer.layer = 5
	bench.add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "BuildPanel"
	panel.add_theme_stylebox_override("panel", UI.flat(PANEL_BG, 0, Color.TRANSPARENT, 18))
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -PANEL_WIDTH
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	# The hint bar sits centred under the plan, left of the panel; none of it takes clicks.
	var area := MarginContainer.new()
	area.set_anchors_preset(Control.PRESET_FULL_RECT)
	area.add_theme_constant_override("margin_right", int(PANEL_WIDTH))
	area.add_theme_constant_override("margin_bottom", 18)
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(area)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UI.flat(PANEL_BG, 6, Color.TRANSPARENT, 10))
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.size_flags_vertical = Control.SIZE_SHRINK_END
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(bar)
	hint = UI.label("", 15, TEXT)
	bar.add_child(hint)

func refresh_panel() -> void:
	if list == null or not active: return
	UI.clear(list)
	list.add_child(UI.label("BUILD VIEW", 24, TEXT, true))
	list.add_child(UI.label("Funds: " + shop.money_text(), 14, MUTED))
	section("FLOOR")
	var block: String = shop.expansion_block()
	list.add_child(wrapped("Expansion square, %s, $%d. %d of %d built." % [size_text(), shop.CATALOG[shop.EXPANSION].price, shop.expansions, Starter.MAX_EXPANSIONS], MUTED))
	var expand := UI.button("STOP PLACING" if mode == "expansion" else "PLOP DOWN EXPANSION", 14, WARM)
	expand.name = "BuildExpansion"
	expand.disabled = block != "" and mode != "expansion"
	expand.pressed.connect(func(): set_mode("" if mode == "expansion" else "expansion"))
	list.add_child(expand)
	if block != "": list.add_child(wrapped(block, MUTED))
	section("STORAGE")
	var stored: Array[String] = shop.stored_ids()
	if shop.placement_id != "": list.add_child(wrapped("Placing: " + shop.item_name(shop.placement_id), TEXT))
	if stored.is_empty(): list.add_child(wrapped("Empty. Bought or stashed equipment waits here.", MUTED))
	for id in stored: list.add_child(row(id, [["PLACE", "Place_", func(): set_mode("", id)]]))
	section("IN THE SHOP")
	var any := false
	for id in shop.equipment:
		if not shop.placed.get(id, false) or id == shop.placement_id: continue
		any = true
		var actions := [["MOVE", "Move_", func(): set_mode("", id)]]
		if not shop.FIXTURES.has(id): actions.append(["STASH", "Stash_", func(): shop.stash(id)])
		list.add_child(row(id, actions))
	if not any: list.add_child(wrapped("No equipment placed yet.", MUTED))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	list.add_child(spacer)
	var leave := UI.button("BACK TO THE SHOP (B)", 14, ACCENT)
	leave.name = "ExitBuild"
	leave.pressed.connect(close)
	list.add_child(leave)
	update_hint()

func section(title: String) -> void:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.12)
	line.custom_minimum_size.y = 1
	list.add_child(line)
	list.add_child(UI.label(title, 13, MUTED, true))

func wrapped(value: String, color: Color) -> Label:
	var item := UI.label(value, 14, color)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.custom_minimum_size.x = PANEL_WIDTH - 40
	return item

## A piece of equipment with its action buttons: [label, name prefix, callback].
func row(id: String, actions: Array) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	var label := UI.label(shop.item_name(id), 14, TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	line.add_child(label)
	for action in actions:
		var button := UI.button(action[0], 12, ACCENT if action[0] != "STASH" else WARM)
		button.name = action[1] + id
		button.pressed.connect(action[2])
		line.add_child(button)
	return line
