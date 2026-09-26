extends SceneTree
var failures: Array[String] = []
func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/" + name + ".png")
func aim(bench: Node3D, point: Vector3) -> void:
	bench.camera_rig.camera.look_at(point)
	bench.camera_rig.look_pitch = bench.camera_rig.camera.rotation.x
	bench.camera_rig.look_yaw = bench.camera_rig.camera.rotation.y
func run() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	root.add_child(bench)
	await process_frame
	bench.set_process_unhandled_input(false)
	var player = bench.camera_rig
	player.set_physics_process(false)
	player.body.position = Vector3(3, -4.35, 6.2)
	player.update_camera()
	aim(bench, bench.tools.toolbox.global_position + Vector3(0, 0.6, 1.0))
	var center := root.get_visible_rect().size * 0.5
	expect(bench.interaction_hit(center).get("action") == "toolbox", "Toolbox not reachable from front of repair bench")
	bench.activate(center)
	expect(bench.tool_menu_open and not player.captured, "Toolbox did not open a separate cursor menu")
	expect(root.gui_get_focus_owner() is Button, "Tool menu did not focus a keyboard-accessible button")
	await capture("toolbox-menu")
	bench.hud.tool_buttons["screwdriver"].pressed.emit()
	await create_timer(1.0).timeout
	expect(bench.tools.equipped_tool == "screwdriver" and player.captured and not bench.tool_menu_open, "Menu selection failed to equip screwdriver and resume play")
	bench.open_tool_menu()
	bench.hud.tool_buttons["thermal-camera"].pressed.emit()
	await create_timer(0.8).timeout
	expect(bench.tools.equipped_tool == "thermal-camera" and bench.tools.location == "toolbox", "Menu did not return previous tool before switching")
	bench.open_tool_menu()
	bench.hud.tool_buttons[""].pressed.emit()
	await create_timer(0.4).timeout
	expect(bench.tools.equipped_tool == "", "Empty hands did not return current tool")
	bench.open_tool_menu()
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	bench.first_person_input(escape)
	expect(not bench.tool_menu_open and player.captured, "Escape did not close tool menu and resume play")
	player.body.position = Vector3(-3, -4.35, 6.2)
	player.update_camera()
	aim(bench, bench.gpu.global_position)
	var size: Vector3 = bench.gpu.global_basis.get_scale()
	expect(size.is_equal_approx(Vector3.ONE * 0.25), "GPU is not at compact physical scale")
	await capture("gpu-scale-holder")
	bench.inspection.lift()
	await create_timer(0.55).timeout
	bench.inspection.rotate_item(Vector2(120, 30))
	expect(bench.gpu.global_basis.get_scale().is_equal_approx(size), "Inspecting/rotating changed GPU scale")
	await capture("gpu-scale-held")
	bench.inspection.put_down()
	await create_timer(0.55).timeout
	bench.testing_station.attach()
	await create_timer(0.6).timeout
	expect(bench.gpu.global_basis.get_scale().is_equal_approx(size), "Test board enlarged GPU")
	expect(bench.test_monitor.scale.is_equal_approx(Vector3.ONE), "Monitor scale changed")
	player.body.position = Vector3(19, -4.35, 7)
	player.update_camera()
	aim(bench, Vector3(19, 1.0, 0))
	await capture("testing-scale")
	bench.testing_station.detach()
	await create_timer(0.6).timeout
	player.body.position = Vector3(-3, -4.35, 6.2)
	player.update_camera()
	bench.service.debug_disassemble()
	for id in bench.service.fan_screws + bench.service.cooler_screws:
		expect(bench.asset_contract.objects[id].global_basis.get_scale().is_equal_approx(size), "Tray screw changed physical size")
	bench.service.lift_assembly("fan-assembly")
	await create_timer(0.55).timeout
	bench.service.rotate_held(Vector2(90, 20))
	expect(bench.asset_contract.objects["fan-assembly"].global_basis.get_scale().is_equal_approx(size), "Detached fan changed physical size")
	bench.queue_free()
	await process_frame
	print("PASS: physical scale, front toolbox access, keyboard focus, tool switching and menu close" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
