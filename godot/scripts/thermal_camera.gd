extends Node
## Separate depth-tested world renders visible surfaces only, at 9 Hz.
var bench: Node3D
var viewport: SubViewport
var camera: Camera3D
var proxies: Array[Dictionary] = []
var panel: PanelContainer
var readout: Label
var screen_material: StandardMaterial3D
var aiming := false
var elapsed := 0.0
var latest_reading: Dictionary = {}
var last_update_frame := -1

func configure(world: Node3D) -> void:
	bench = world
	viewport = SubViewport.new()
	viewport.name = "ThermalImage"
	viewport.size = Vector2i(320, 200)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.025, 0.015, 0.14)
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	viewport.add_child(environment)
	camera = Camera3D.new()
	camera.fov = 35.0
	camera.far = 150.0
	viewport.add_child(camera)
	var ambient := ShaderMaterial.new()
	ambient.shader = preload("res://shaders/thermal_surface.gdshader")
	for source in bench.find_children("*", "MeshInstance3D", true, false):
		if source.mesh == null or source is Label3D or is_ancestor_of(source): continue
		var proxy := MeshInstance3D.new()
		proxy.mesh = source.mesh
		var material := ambient.duplicate() as ShaderMaterial if bench.gpu.is_ancestor_of(source) else ambient
		proxy.material_override = material
		viewport.add_child(proxy)
		proxies.append({"source": source, "proxy": proxy, "material": material, "heated": bench.gpu.is_ancestor_of(source)})
	screen_material = StandardMaterial3D.new()
	screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_material.albedo_texture = viewport.get_texture()
	bench.tools.thermal_camera.get_node("Display").material_override = screen_material
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -340
	panel.offset_right = 340
	panel.offset_top = -245
	panel.offset_bottom = 245
	bench.hud.add_child(panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	var title := Label.new()
	title.text = "BENCH IR-1   |   SURFACE °C   |   SIMULATED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var display := TextureRect.new()
	display.texture = viewport.get_texture()
	display.custom_minimum_size = Vector2(640, 400)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(display)
	var cross := Label.new()
	cross.text = "+"
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.add_child(cross)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	gradient.colors = PackedColorArray([Color(0.025, 0.015, 0.14), Color(0.28, 0.04, 0.55), Color(0.92, 0.12, 0.1), Color(1, 0.72, 0.08), Color(1, 0.98, 0.82)])
	var ramp := GradientTexture2D.new()
	ramp.gradient = gradient
	ramp.width = 256
	ramp.height = 12
	var legend := TextureRect.new()
	legend.texture = ramp
	legend.custom_minimum_size.y = 12
	legend.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(legend)
	readout = Label.new()
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(readout)
	panel.hide()

func sample_center() -> Dictionary:
	# Match the thermal image's first visible surface, including occluding furniture.
	var point := bench.get_viewport().get_visible_rect().size * 0.5
	var hit: Dictionary = bench.picker.surface_hit_at(point)
	if hit.is_empty() or bench.camera_rig.camera.global_position.distance_to(hit.point) > 40.0: return {}
	var mesh: MeshInstance3D = hit.mesh
	var label := String(mesh.name).replace("-", " ")
	if String(mesh.name).begins_with("memory-package") or String(mesh.name).begins_with("rear-memory"):
		label = bench.thermal.memory_name(String(mesh.name)) + " VRAM package surface"
	return {"mesh": mesh, "temperature": bench.thermal.apparent_temperature(mesh), "label": label,
		"reflective": bench.thermal.emissivity(mesh) < 0.9}

func _process(delta: float) -> void:
	if bench == null: return
	var equipped: bool = bench.tools.equipped_tool == "thermal-camera" and not bench.tools.busy
	panel.visible = equipped and aiming and (bench.camera_rig.legacy_test_mode or bench.camera_rig.captured)
	if bench.hud.reticle != null: bench.hud.reticle.visible = bench.camera_rig.captured and not panel.visible
	if not equipped:
		aiming = false
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	camera.global_transform = bench.camera_rig.camera.global_transform
	elapsed += delta
	if elapsed < 1.0 / 9.0: return
	elapsed = 0.0
	for entry in proxies:
		var source: MeshInstance3D = entry.source
		entry.proxy.visible = source.is_visible_in_tree() and not bench.camera_rig.camera.is_ancestor_of(source)
		entry.proxy.global_transform = source.global_transform
		if entry.heated: entry.material.set_shader_parameter("temperature", bench.thermal.apparent_temperature(source))
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	latest_reading = sample_center()
	last_update_frame = Engine.get_process_frames()
	readout.text = "No surface in range\n20°C   —   FIXED SCALE   —   100°C" if latest_reading.is_empty() else \
		"%.1f°C  |  %s\n%s   |   20–100°C fixed scale" % [latest_reading.temperature, latest_reading.label,
		"Reflective metal: approximate" if latest_reading.reflective else "Emissivity 0.95"]
