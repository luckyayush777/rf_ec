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
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 12
	column.add_child(progress)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	for item in [["Flip part", "flip"], ["Return tool", "return"], ["Screwdriver", "screwdriver"], ["Dev blower", "dev-blower"], ["Thermal camera (stand)", "thermal-camera"], ["Empty hands", ""], ["Close / Esc", "close"]]:
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
	overlay.hide()

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
	var branch: Node3D = subject
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
	var bounds: AABB = branch.global_transform * Contract.bounds_in(branch)
	if mode == "bag":
		center = branch.to_global(Vector3(0, 0.3, 0))
		distance = 8.3
		direction = Vector3(0, 1, 0.22).normalized()
	else:
		center = bounds.get_center()
		distance = maxf(bounds.size.length() * 0.40 / tan(deg_to_rad(camera.fov * 0.5)), 1)
		direction = (bench.camera_rig.camera.global_position - center).normalized()
	status.text = ("GPU" if subject == bench.gpu else bench.service.assembly_name(String(subject.name)).to_upper()) + " SERVICE  /  Hold LMB: use tool   •   RMB drag: rotate   •   Wheel: zoom" if mode == "service" else "ENGINEER'S TOOL ROLL  /  Select a tool or its label. Other pockets are empty."
	for button in bench.hud.tool_close_button.get_parent().get_children():
		var id: String = button.get_meta("id")
		button.visible = id == "close" or (id in ["flip", "return"] if mode == "service" else id not in ["flip", "return"])
		if id == "dev-blower" and not OS.is_debug_build(): button.hide()
	progress.visible = mode == "service"
	overlay.show()
	update_camera()
	sync_proxies()
	bench.hud.tool_close_button.grab_focus()
	if mode == "bag":
		bench.hud.refresh_tool_menu(bench.tools, bench.service, false)
		bench.hud.tool_buttons["screwdriver"].grab_focus()

func update_camera() -> void:
	var aspect := maxf(0.25, surface.size.x / maxf(surface.size.y, 1))
	camera.global_position = center + direction * distance * zoom / minf(1, aspect)
	camera.look_at(center, Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP)

func sync_proxies() -> void:
	var visible_entries: Array = []
	for proxy in proxies:
		proxy.node.global_transform = proxy.source.global_transform
		proxy.node.visible = proxy.source.is_visible_in_tree()
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
				if mode == "service" and bench.tools.equipped_tool == "dev-blower":
					bench.cleaning.begin()
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
				elif mode == "bag" and hit.get("action") in ["screwdriver", "dev-blower"]:
					bench.select_tool(hit.action)
		elif event.pressed and not bench.service.busy and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom = clampf(zoom * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 0.4, 1.6)
			update_camera()
	elif event is InputEventMouseMotion and rotating and mode == "service" and not bench.service.busy:
		direction = (Basis(camera.global_basis.y, -event.relative.x * 0.008) * Basis(camera.global_basis.x, -event.relative.y * 0.008) * direction).normalized()
		update_camera()

func _input(event: InputEvent) -> void:
	if mode == "": return
	if event is InputEventKey and event.pressed and event.physical_keycode in [KEY_ESCAPE, KEY_TAB]:
		request_close()
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT: bench.service.end_screw()
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
	if mode != "service" or bench.tools.equipped_tool != "dev-blower" or not bench.ready_for_action(): return
	if not Rect2(Vector2.ZERO, surface.size).has_point(cleaning_pointer): return
	var hit: Dictionary = pick.surface_hit_at(cleaning_pointer, true)
	if hit.is_empty() or not contains_subject(hit.mesh): return
	bench.tools.aim_blower(bench.camera_rig.camera.unproject_position(hit.point), hit)
	if bench.cleaning.blowing: bench.cleaning.blow_at(cleaning_pointer, delta, hit)

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
	return_area.text = "Return " + bench.tools.equipped_tool.replace("-", " ") if bench.tools.equipped_tool != "" else "Tool returned"
	cleaning_pointer = surface.get_local_mouse_position()
	clean_under_pointer(delta)
	var id: String = bench.service.active_screw
	if id != "": selected_screw = id
	progress.value = subject_cleaning_progress() * 100 if bench.tools.equipped_tool == "dev-blower" else bench.service.turns[selected_screw].progress * 100 if bench.service.turns.has(selected_screw) else 0
