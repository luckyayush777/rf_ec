extends SceneTree
const Contract = preload("res://scripts/asset_contract.gd")
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/" + name + ".png")
func run() -> void:
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/tool-proportions.json"))
	var bench = load("res://scenes/workbench.tscn").instantiate()
	root.add_child(bench)
	await process_frame
	bench.camera_rig.set_physics_process(false)
	bench.hud.audio_save_timer.stop()
	for id in bench.tools.TOOLS:
		if id == "screwdriver": continue
		var tool: Node3D = bench.tools.tool_node(id)
		var old: Dictionary = baseline[str(tool.name)]
		var bounds := Contract.bounds_in(tool)
		for axis in range(3):
			expect(absf(bounds.size[axis] - old.size[axis]) < maxf(0.005, old.size[axis] * 0.06),
				"Tool proportions changed: %s %s vs %s" % [id,bounds.size,old.size])
	var display: MeshInstance3D = bench.tools.thermal_camera.get_node("Display")
	expect(display.mesh is QuadMesh and display.mesh.size.is_equal_approx(Vector2(.90,.56)), "Thermal LCD lost its native UV quad")
	bench.open_tool_menu(true)
	await create_timer(.7).timeout
	await capture("rounded-tool-roll")
	# Pick every bag tool through the visible geometry, then exercise its ordinary lifecycle.
	for id in bench.tools.ROLL_NODES:
		var tool: Node3D = bench.tools.tool_node(id)
		var point := Vector2(-1,-1)
		for part in tool.find_children("*", "MeshInstance3D", true, false):
			var candidate: Vector2 = bench.closeup.camera.unproject_position(part.global_transform * part.get_aabb().get_center())
			if bench.closeup.pick.hit_at(candidate).get("action", "") == id:
				point = candidate
				break
		expect(point.x >= 0, "Rounded tool is not pickable in the bag: " + id)
		if point.x >= 0:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = point
			bench.closeup.view_input(click)
			await create_timer(1.05).timeout
			expect(bench.tools.equipped_tool == id, "Geometry click did not equip " + id)
			await bench.tools.return_tool()
			bench.open_tool_menu(true)
			await create_timer(.7).timeout
	await bench.select_tool("thermal-camera")
	await create_timer(.7).timeout
	expect(bench.tools.equipped_tool == "thermal-camera" and display.material_override == bench.thermal_viewer.screen_material,
		"Rounded thermal camera lost its live display or equip action")
	await capture("rounded-thermal-camera")
	await bench.tools.return_tool()
	bench.queue_free()
	await process_frame
	print("PASS: retained tool proportions, all eight bag tools selected through their meshes, equip/return and native thermal LCD" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
