extends CanvasLayer
## Independent viewing camera; live mesh proxies preserve all gameplay transforms.
const Picker = preload("res://scripts/interaction_picker.gd")
const Contract = preload("res://scripts/asset_contract.gd")
var bench: Node3D
var mode := ""
var overlay: ColorRect
var viewport: SubViewport
var surface: SubViewportContainer
var camera: Camera3D
var stage: Node3D
var pick: RefCounted
var proxies: Array = []
var center := Vector3.ZERO
var direction := Vector3(0, 1, 0.1)
var distance := 5.0
var zoom := 1.0
var rotating := false
var status: Label
var progress: ProgressBar
var was_captured := false
var selected_screw := ""
var hud_was_visible := true
var return_area: Button
var cleaning_pointer := Vector2.ZERO
var subject: Node3D
var subject_targets: Array = []
var puff_view: MultiMeshInstance3D
## Loupe: a round lens over the view, much deeper zoom, and a click centres what to magnify.
const VIEW_ZOOM := 0.4
const LOUPE_ZOOM := 0.05
var lens: ColorRect
var lens_motion: Tween
## Paste tools seen at work on the face: the spudger blade riding it (with compound beading on
## its edge) or the IPA pad pressed flat (greying as it lifts residue). Built in cell units and
## scaled to the face; lifted while hovering, pressed while LMB is held.
var work_tools: Dictionary = {}
var blade_tilt: Node3D
var blade_bead: MeshInstance3D
var pad_material: StandardMaterial3D
var tool_dir := Vector3.ZERO
var tool_press := 0.0

func configure(owner_bench: Node3D) -> void:
	bench = owner_bench
	layer = 12
	overlay = ColorRect.new()
	var backdrop := ShaderMaterial.new()
	backdrop.shader = preload("res://shaders/closeup_backdrop.gdshader")
	overlay.material = backdrop
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	overlay.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 21)
	status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	status.add_theme_constant_override("shadow_offset_y", 2)
	column.add_child(status)
	surface = SubViewportContainer.new()
	# The transparent view renders premultiplied colour; composite it that way so thin dust
	# clouds over the empty background are not darkened.
	var composite := CanvasItemMaterial.new()
	composite.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	surface.material = composite
	surface.stretch = true
	surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(surface)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	surface.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	camera = Camera3D.new()
	camera.fov = 38
	camera.near = 0.01
	stage.add_child(camera)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.8
	camera.add_child(fill)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#d6e5ee")
	environment.environment.ambient_light_energy = 0.7
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -25, 0)
	light.light_energy = 1.4
	stage.add_child(light)
	lens = ColorRect.new()
	lens.name = "LoupeLens"
	lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lens_material := ShaderMaterial.new()
	lens_material.shader = preload("res://shaders/loupe_lens.gdshader")
	lens.material = lens_material
	surface.add_child(lens)
	lens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var power := Label.new()
	power.name = "Magnification"
	power.add_theme_font_size_override("font_size", 22)
	power.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	lens.add_child(power)
	power.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	power.offset_top = -40
	power.offset_left = -60
	power.offset_right = 60
	power.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lens.hide()
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 12
	column.add_child(progress)
	var bar := HFlowContainer.new()
	column.add_child(bar)
	# Lifted dust shows here too: the same MultiMesh, drawn in this view's world.
	puff_view = MultiMeshInstance3D.new()
	puff_view.multimesh = bench.cleaning.puffs.multimesh
	puff_view.custom_aabb = bench.cleaning.puffs.custom_aabb
	puff_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(puff_view)
	build_work_tools()
	for item in [["Flip part", "flip"], ["Return tool", "return"], ["Screwdriver", "screwdriver"], ["Air blower", "air-blower"], ["Dev blower", "dev-blower"],
			["Spudger", "spudger"], ["IPA wipe", "ipa-wipe"], ["Paste syringe", "paste-syringe"], ["Fan oiler", "fan-oiler"],
			["Loupe", "loupe"], ["Thermal camera (stand)", "thermal-camera"], ["Empty hands", ""], ["Close / Esc", "close"]]:
		var button := Button.new()
		button.text = item[0]
		button.custom_minimum_size.y = 42
		var id: String = item[1]
		button.set_meta("id", id)
		button.set_meta("label", item[0])
		bar.add_child(button)
		if id == "return":
			return_area = button
			button.custom_minimum_size = Vector2(230, 54)
			button.pressed.connect(return_equipped_tool)
		elif id == "close":
			button.pressed.connect(request_close)
			bench.hud.tool_close_button = button
		elif id == "flip":
			button.pressed.connect(func():
				if bench.service.busy: return
				direction = -direction
				update_camera())
		else:
			button.pressed.connect(func(): bench.select_tool(id))
			bench.hud.tool_buttons[id] = button
	bench.hud.tool_overlay = overlay
	surface.gui_input.connect(view_input)
	bench.service.notice.connect(func(message: String):
		if mode == "service": status.text = message)
	bench.paste.notice.connect(func(message: String):
		if mode == "service": status.text = message)
	bench.bearing.notice.connect(func(message: String):
		if mode == "service": status.text = message)
	bench.bearing.opened_changed.connect(func():
		if mode == "service": frame_view())
	overlay.hide()

func work_part(parent: Node3D, mesh: Mesh, at: Vector3, material: Material, turn := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.rotation = turn
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func build_work_tools() -> void:
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = Color(0.2, 0.32, 0.62)
	plastic.roughness = 0.45
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color(0.06, 0.07, 0.08)
	grip.roughness = 0.7
	var gum := StandardMaterial3D.new()
	gum.albedo_color = Color(0.4, 0.4, 0.38)
	gum.roughness = 0.3
	# Spudger: the leading edge sits at the origin; the blade rises back along -x into the grip.
	var spudger := Node3D.new()
	spudger.name = "SpudgerAtWork"
	stage.add_child(spudger)
	blade_tilt = Node3D.new()
	spudger.add_child(blade_tilt)
	var blade := BoxMesh.new()
	blade.size = Vector3(7.0, 0.4, 5.0)
	work_part(blade_tilt, blade, Vector3(-3.5, 0.2, 0), plastic)
	var handle := CylinderMesh.new()
	handle.top_radius = 0.9
	handle.bottom_radius = 1.0
	handle.height = 11.0
	work_part(blade_tilt, handle, Vector3(-12.5, 0.2, 0), grip, Vector3(0, 0, PI / 2.0))
	var bead := SphereMesh.new()
	bead.radius = 0.5
	bead.height = 1.0
	blade_bead = work_part(spudger, bead, Vector3(0.6, 0.45, 0), gum)
	spudger.hide()
	work_tools["spudger"] = spudger
	# IPA pad: a folded lint-free square pressed flat under the fingers.
	pad_material = StandardMaterial3D.new()
	pad_material.albedo_color = Color(0.95, 0.95, 0.93)
	pad_material.roughness = 0.95
	var pad := Node3D.new()
	pad.name = "IpaPadAtWork"
	stage.add_child(pad)
	var sheet := BoxMesh.new()
	sheet.size = Vector3(7.0, 0.7, 6.0)
	work_part(pad, sheet, Vector3(0, 0.35, 0), pad_material)
	var fold := BoxMesh.new()
	fold.size = Vector3(6.4, 0.6, 2.6)
	work_part(pad, fold, Vector3(0, 0.95, -1.4), pad_material, Vector3(0.15, 0, 0))
	pad.hide()
	work_tools["ipa-wipe"] = pad

## Rides the equipped paste tool on the face under the pointer, aimed along the stroke.
func place_work_tool(delta: float) -> void:
	var tool: String = bench.tools.equipped_tool
	for id in work_tools: work_tools[id].visible = false
	if mode != "service" or not work_tools.has(tool) or paste_face() == "": return
	if not Rect2(Vector2.ZERO, surface.size).has_point(cleaning_pointer): return
	var hit: Dictionary = pick.surface_hit_at(cleaning_pointer)
	var face: String = bench.paste.face_of(hit.get("mesh")) if not hit.is_empty() else ""
	if face == "": return
	var face_layer: MeshInstance3D = bench.paste.faces[face].mesh
	var cell: float = bench.paste.cell_size(face_layer)
	var normal := face_layer.global_basis.y.normalized()
	# The blade follows the stroke's locked heading (set on the stroke's first movement, never
	# reversed until release) and keeps its last heading while hovering between strokes.
	var heading: Vector2 = bench.paste.stroke_dir
	if bench.paste.working and heading != Vector2.ZERO:
		tool_dir = (face_layer.global_basis * Vector3(heading.x, 0.0, heading.y)).normalized()
	if tool_dir == Vector3.ZERO or absf(tool_dir.dot(normal)) > 0.9:
		tool_dir = face_layer.global_basis.x.normalized()
	tool_dir = (tool_dir - normal * tool_dir.dot(normal)).normalized()
	tool_press = move_toward(tool_press, 1.0 if bench.paste.working else 0.0, delta * 8.0)
	var node: Node3D = work_tools[tool]
	node.global_transform = Transform3D(Basis(tool_dir, normal, tool_dir.cross(normal)).scaled(Vector3.ONE * cell),
		hit.point + normal * cell * (0.15 + 1.8 * (1.0 - tool_press)))
	if tool == "spudger":
		blade_tilt.rotation.z = -deg_to_rad(lerpf(55.0, 28.0, tool_press))
		var carried: float = bench.paste.blade_load
		blade_bead.visible = carried > 0.03
		blade_bead.scale = Vector3(0.4 + 1.2 * carried, 0.3 + 1.0 * carried, 4.4)
	else:
		pad_material.albedo_color = Color(0.95, 0.95, 0.93).lerp(Color(0.42, 0.42, 0.4), bench.paste.pad_soil)
	node.visible = true

func contains_subject(node: Node) -> bool:
	return subject != null and (node == subject or subject.is_ancestor_of(node))

func show_view(kind: String, selected_part: Node3D = null) -> void:
	mode = kind
	subject = selected_part if selected_part != null else bench.gpu
	if mode == "bag": subject = bench.tools.toolbox
	was_captured = bench.camera_rig.captured
	hud_was_visible = bench.hud.visible
	bench.hud.hide()
	bench.cancel_press()
	bench.camera_rig.set_captured(false)
	rotating = false
	zoom = 1.0
	selected_screw = ""
	for proxy in proxies: proxy.node.queue_free()
	proxies.clear()
	pick = Picker.new()
	pick.configure(bench, bench.gpu, camera, bench.service)
	var subject_screws: Array = []
	if mode == "service":
		for id in bench.service.screw_seats:
			if contains_subject(bench.service.screw_seats[id]): subject_screws.append(id)
	var selected: Array = []
	for entry in pick.entries:
		var belongs: bool = contains_subject(entry.node)
		if mode == "service":
			for id in subject_screws:
				var screw: Node3D = bench.asset_contract.objects[id]
				belongs = belongs or screw == entry.node or screw.is_ancestor_of(entry.node)
		if belongs:
			selected.append(entry)
			var proxy := MeshInstance3D.new()
			proxy.mesh = entry.node.mesh
			proxy.material_override = entry.node.material_override
			proxy.material_overlay = entry.node.material_overlay
			stage.add_child(proxy)
			proxies.append({"source": entry.node, "node": proxy, "entry": entry})
	pick.entries = selected
	if mode == "bag": pick.targets = []
	else:
		pick.targets = pick.targets.filter(func(target): return contains_subject(target.node) or (target.action == "screw" and target.id in subject_screws))
	subject_targets = pick.targets.duplicate()
	frame_view()
	for button in bench.hud.tool_close_button.get_parent().get_children():
		var id: String = button.get_meta("id")
		button.visible = id == "close" or (id in ["flip", "return"] if mode == "service" else id not in ["flip", "return"])
		if (id == "dev-blower" and not OS.is_debug_build()) or id in bench.tools.locked: button.hide()
	progress.visible = mode == "service"
	overlay.show()
	update_camera()
	sync_proxies()
	bench.hud.tool_close_button.grab_focus()
	if mode == "bag":
		bench.hud.refresh_tool_menu(bench.tools, bench.service, false)
		bench.hud.tool_buttons["screwdriver"].grab_focus()

## Frames the subject, or the exposed work surface for the equipped hand tool.
func frame_view() -> void:
	zoom = 1.0
	var bounds: AABB = subject.global_transform * Contract.bounds_in(subject)
	if mode == "bag":
		center = subject.to_global(Vector3(0.45, 0.3, 0))
		distance = 8.3
		direction = Vector3(0, 1, 0.22).normalized()
	else:
		center = bounds.get_center()
		distance = maxf(bounds.size.length() * 0.40 / tan(deg_to_rad(camera.fov * 0.5)), 1)
		direction = (bench.camera_rig.camera.global_position - center).normalized()
	status.text = ("GPU" if subject == bench.gpu else bench.service.assembly_name(String(subject.name)).to_upper()) + " SERVICE  /  Hold LMB: use tool   •   T: tools   •   Q: return tool   •   RMB drag: rotate   •   Wheel: zoom" if mode == "service" else "ENGINEER'S TOOL ROLL  /  Select a tool or its label   •   T or Esc: close"
	var face := paste_face()
	if face != "":
		# Paste work frames the exposed contact face, looking straight at it.
		var face_layer: MeshInstance3D = bench.paste.faces[face].mesh
		var span: float = (face_layer.mesh as PlaneMesh).size.length() * face_layer.global_basis.get_scale().x
		center = face_layer.global_position
		distance = maxf(span * 0.5 / tan(deg_to_rad(camera.fov * 0.5)), 0.2)
		direction = (face_layer.global_basis.y.normalized() + face_layer.global_basis.z.normalized() * 0.35).normalized()
		status.text = ("GPU DIE" if face == "die" else "HEATSINK BASE") + "  /  " + {
			"spudger": "Hold and drag LMB to scrape the old crust",
			"ipa-wipe": "Hold and rub LMB to lift the film and stray paste",
			"paste-syringe": "Hold LMB to squeeze paste; drag to lay a line" if face == "die" else "Check the imprint. Fresh paste goes on the die"}[bench.tools.equipped_tool] + "   •   RMB drag: rotate   •   Wheel: zoom"
	var part := bearing_face()
	if part != "":
		# With the rotor out, frame the shaft from the side or look down into the bearing.
		var fan_basis: Basis = bench.bearing.fan.global_basis
		var fan_scale: float = fan_basis.get_scale().x
		if part == "shaft":
			center = bench.bearing.shaft.global_position
			distance = maxf(bench.bearing.SHAFT_LENGTH * 2.4 * fan_scale / tan(deg_to_rad(camera.fov * 0.5)), 0.05)
			direction = (fan_basis.z.normalized() + fan_basis.y.normalized() * 0.25).normalized()
			status.text = "FAN SHAFT  /  Hold and drag LMB along the shaft to wipe off the gunk"
		else:
			# Keep the rotor resting beside the housing in view so it can be clicked back in.
			var sleeve: Vector3 = bench.bearing.sleeve.global_position
			var hub: Vector3 = bench.bearing.rotor.global_position
			center = sleeve.lerp(hub, 0.4)
			distance = maxf(sleeve.distance_to(hub) * 0.9 / tan(deg_to_rad(camera.fov * 0.5)), 0.05)
			direction = (fan_basis.y.normalized() + fan_basis.z.normalized() * 0.45).normalized()
			status.text = "FAN BEARING  /  Hold LMB on the bearing for a drop of oil. Click the rotor to refit it"
		status.text += "   •   RMB drag: rotate   •   Wheel: zoom"
	elif mode == "service" and subject == bench.bearing.fan and "fan-assembly" in bench.service.removed:
		status.text = "FAN SERVICE  /  " + ("Click the rotor to refit it" if "fan-rotor" in bench.bearing.opened else
			"Click the hub to pull the rotor out" if "hub-label" in bench.bearing.opened else
			"Click the hub sticker to peel it off") + "   •   RMB drag: rotate   •   Wheel: zoom"
	if mode == "service" and loupe_view():
		status.text = "LOUPE  /  Click: centre and magnify   •   Wheel: zoom   •   RMB drag: rotate"
		if subject == bench.gpu:
			# The card opens on its gold fingers, looking at the fan-side face from past the edge.
			var card: Basis = bench.gpu.global_basis
			center = bench.connector.centre()
			distance = maxf(bench.connector.span() * 0.45 / tan(deg_to_rad(camera.fov * 0.5)), 0.1)
			direction = (card.y.normalized() + card.z.normalized() * 0.8).normalized()
			status.text = "EDGE CONNECTOR  /  " + status.text.trim_prefix("LOUPE  /  ")
	update_camera()

func loupe_view() -> bool:
	return bench.tools.equipped_tool in bench.tools.VIEW_TOOLS

func min_zoom() -> float:
	return LOUPE_ZOOM if mode == "service" and loupe_view() else VIEW_ZOOM

## Centres the view on the clicked spot and doubles the magnification.
func magnify_at(point: Vector2) -> void:
	var hit: Dictionary = pick.surface_hit_at(point)
	if hit.is_empty() or not contains_subject(hit.mesh): return
	if lens_motion != null: lens_motion.kill()
	lens_motion = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	lens_motion.tween_property(self, "center", hit.point, 0.25)
	lens_motion.tween_property(self, "zoom", maxf(zoom * 0.5, LOUPE_ZOOM), 0.25)

## The bearing part this service view should frame for the equipped tool, once the rotor is out.
func bearing_face() -> String:
	if mode != "service" or not bench.bearing.WORK.has(bench.tools.equipped_tool): return ""
	if not contains_subject(bench.bearing.fan) or "fan-rotor" not in bench.bearing.opened: return ""
	return "shaft" if bench.tools.equipped_tool == "ipa-wipe" else "bearing"

## The contact face this service view should frame for the equipped paste tool, if exposed.
func paste_face() -> String:
	if mode != "service" or bench.tools.equipped_tool not in bench.tools.PASTE_TOOLS: return ""
	for face in ["die", "heatsink"]:
		var face_layer: MeshInstance3D = bench.paste.faces[face].mesh
		if contains_subject(face_layer) and bench.service_rules.check_surface("scrape", face, bench.service.removed, "spudger").allowed:
			return face
	return ""

func update_camera() -> void:
	var aspect := maxf(0.25, surface.size.x / maxf(surface.size.y, 1))
	camera.global_position = center + direction * distance * zoom / minf(1, aspect)
	camera.look_at(center, Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP)

func sync_proxies() -> void:
	var visible_entries: Array = []
	for proxy in proxies:
		# Cable deformation replaces the mesh resource while this view stays open.
		proxy.node.mesh = proxy.source.mesh
		proxy.node.global_transform = proxy.source.global_transform
		proxy.node.visible = proxy.source.is_visible_in_tree()
		# Damage can change a part's look while the view is open (tarnished contacts).
		proxy.node.material_override = proxy.source.material_override
		# A removed screw leaves this view; a seated screw returns immediately.
		if mode == "service":
			proxy.node.visible = proxy.node.visible and contains_subject(proxy.source)
		if proxy.node.visible: visible_entries.append(proxy.entry)
	pick.entries = visible_entries
	pick.targets = subject_targets.filter(func(target): return contains_subject(target.node) and target.node.is_visible_in_tree())

func view_input(event: InputEvent) -> void:
	if mode == "": return
	if event is InputEventMouse: cleaning_pointer = event.position
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			rotating = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed: bench.cancel_press()
			elif bench.ready_for_action():
				var hit: Dictionary = pick.hit_at(event.position)
				var opening: String = bench.bearing.click_target(hit.get("mesh")) if mode == "service" else ""
				if opening != "" and bench.tools.equipped_tool in bench.bearing.HANDLING_TOOLS:
					bench.bearing.operate(opening)
				elif mode == "service" and loupe_view():
					magnify_at(event.position)
				elif mode == "service" and bench.tools.blower_equipped():
					bench.cleaning.begin()
				elif mode == "service" and bench.tools.equipped_tool in bench.tools.SURFACE_TOOLS:
					bench.paste.begin()
					bench.bearing.begin()
					if bench.paste.face_of(hit.get("mesh")) == "" and bench.bearing.surface_of(hit.get("mesh")) == "":
						status.text = ("Pull the rotor out, then work the shaft or the bearing." if contains_subject(bench.bearing.fan) and "fan-assembly" in bench.service.removed else
							"Aim at the bare die or the heatsink base. Remove the heatsink first if it is still mounted.")
				elif mode == "service" and hit.get("action") in ["screw", "screw_hole"]:
					selected_screw = hit.target.get_meta("part_id")
					bench.service.begin_screw(selected_screw)
				elif mode == "service" and bench.tools.equipped_tool == "":
					if hit.get("action") == "cable":
						bench.service.toggle_cable()
					elif hit.get("action") == "assembly" and bench.service.held_part == "":
						var part_id: String = hit.target.get_meta("part_id")
						var check: Dictionary = bench.service.decision("pickup" if part_id in bench.service.removed else "remove", part_id)
						if check.allowed:
							close()
							bench.lift_assembly(part_id)
						else: status.text = check.reason
				elif mode == "bag" and hit.get("action") in bench.tools.ROLL_NODES:
					bench.select_tool(hit.action)
		elif event.pressed and not bench.service.busy and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom = clampf(zoom * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), min_zoom(), 1.6)
			update_camera()
	elif event is InputEventMouseMotion and rotating and mode == "service" and not bench.service.busy:
		direction = (Basis(camera.global_basis.y, -event.relative.x * 0.008) * Basis(camera.global_basis.x, -event.relative.y * 0.008) * direction).normalized()
		update_camera()

func _input(event: InputEvent) -> void:
	if mode == "": return
	if event is InputEventKey and event.pressed and event.physical_keycode in [KEY_ESCAPE, KEY_TAB]:
		request_close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_T:
		# T swaps tools without leaving the job: the bag opens, then this close-up returns.
		if mode == "service": bench.open_tool_menu(true)
		else: request_close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Q and mode == "service":
		# Q puts the tool back in the kit; the part stays in hand and the close-up stays open.
		if bench.tools.equipped_tool != "": return_equipped_tool()
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			bench.service.end_screw()
			bench.paste.end()
			bench.bearing.end()
		if event.button_index == MOUSE_BUTTON_RIGHT: rotating = false

func request_close() -> void:
	if mode == "bag": bench.close_tool_menu()
	else: close()

func return_equipped_tool() -> void:
	if bench.tools.busy or bench.inspection.moving or bench.service.moving: return
	bench.cancel_press()
	await bench.tools.return_tool()
	status.text = "Tool returned. Click the cable or a loosened part to handle it; RMB rotates the view."

func clean_under_pointer(delta: float) -> void:
	if mode != "service" or not bench.tools.blower_equipped() or not bench.ready_for_action(): return
	if not Rect2(Vector2.ZERO, surface.size).has_point(cleaning_pointer): return
	var hit: Dictionary = pick.surface_hit_at(cleaning_pointer, true)
	if hit.is_empty() or not contains_subject(hit.mesh): return
	bench.tools.aim_blower(bench.camera_rig.camera.unproject_position(hit.point), hit)
	# The jet comes from this view, the way the player sees the nozzle pointed.
	if bench.cleaning.blowing: bench.cleaning.blow_at(cleaning_pointer, delta, hit, (hit.point - camera.global_position).normalized(), subject)

func paste_under_pointer(delta: float) -> void:
	if mode != "service" or not bench.paste.working or not bench.ready_for_action(): return
	if not Rect2(Vector2.ZERO, surface.size).has_point(cleaning_pointer): return
	var hit: Dictionary = pick.surface_hit_at(cleaning_pointer)
	if hit.is_empty() or not contains_subject(hit.mesh): return
	bench.paste.work_at(hit, delta)

func bearing_under_pointer(delta: float) -> void:
	if mode != "service" or not bench.bearing.working or not bench.ready_for_action(): return
	if not Rect2(Vector2.ZERO, surface.size).has_point(cleaning_pointer): return
	var hit: Dictionary = pick.surface_hit_at(cleaning_pointer)
	if hit.is_empty() or not contains_subject(hit.mesh): return
	bench.bearing.work_at(hit, delta)

func paste_progress() -> float:
	var part := bearing_face()
	if part != "": return bench.bearing.progress(part)
	var face := paste_face()
	if face == "": return 0.0
	if bench.tools.equipped_tool == "paste-syringe":
		return clampf(bench.paste.paste_volume() / (2.0 * bench.paste.IDEAL_VOLUME), 0.0, 1.0)
	return bench.paste.face_progress(face)

func subject_cleaning_progress() -> float:
	var total := 0.0
	var remaining := 0.0
	for entry in bench.cleaning.surfaces:
		if contains_subject(entry.mesh):
			total += entry.mass
			remaining += entry.remaining
	return 1.0 - remaining / total if total > 0 else 1.0

func close() -> void:
	bench.cancel_press()
	mode = ""
	rotating = false
	overlay.hide()
	bench.hud.visible = hud_was_visible
	bench.camera_rig.set_captured(was_captured)
	bench.refresh_ui()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		rotating = false

func _process(delta: float) -> void:
	if mode == "": return
	sync_proxies()
	update_camera()
	return_area.disabled = bench.tools.equipped_tool == "" or bench.tools.busy or bench.inspection.moving or bench.service.moving
	return_area.text = "Return " + bench.tools.NAMES[bench.tools.equipped_tool] if bench.tools.equipped_tool != "" else "Tool returned"
	cleaning_pointer = surface.get_local_mouse_position()
	clean_under_pointer(delta)
	paste_under_pointer(delta)
	place_work_tool(delta)
	bearing_under_pointer(delta)
	var id: String = bench.service.active_screw
	if id != "": selected_screw = id
	puff_view.visible = bench.cleaning.puffs.visible
	lens.visible = mode == "service" and loupe_view()
	progress.visible = mode == "service" and not lens.visible
	if lens.visible:
		(lens.material as ShaderMaterial).set_shader_parameter("view_size", lens.size)
		(lens.get_node("Magnification") as Label).text = "%d×" % maxi(1, roundi(2.0 / zoom))
	elif zoom < VIEW_ZOOM:
		zoom = VIEW_ZOOM
	progress.value = subject_cleaning_progress() * 100 if bench.tools.blower_equipped() else paste_progress() * 100 if bench.tools.equipped_tool in bench.tools.SURFACE_TOOLS else bench.service.turns[selected_screw].progress * 100 if bench.service.turns.has(selected_screw) else 0
