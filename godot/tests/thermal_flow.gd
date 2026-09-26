extends SceneTree
var failures: Array[String] = []
func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func _initialize() -> void: call_deferred("run")
func aim(bench: Node3D, target: Vector3) -> void:
	bench.camera_rig.camera.look_at(target)
	bench.camera_rig.look_pitch = bench.camera_rig.camera.rotation.x
	bench.camera_rig.look_yaw = bench.camera_rig.camera.rotation.y
func capture(bench: Node3D, name: String) -> void:
	bench.thermal_viewer._process(0.2)
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		await process_frame
		bench.thermal_viewer._process(0.2)
		await RenderingServer.frame_post_draw
		bench.thermal_viewer.viewport.get_texture().get_image().save_png("res://build/thermal-" + name + ".png")
		root.get_texture().get_image().save_png("res://build/thermal-" + name + "-player.png")
func run() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	root.add_child(bench)
	await process_frame
	bench.set_process_unhandled_input(false)
	bench.thermal.set_process(false)
	var player = bench.camera_rig
	player.set_physics_process(false)
	player.body.position = Vector3(6, -4.35, 7)
	player.update_camera()
	aim(bench, bench.tools.thermal_camera.global_position)
	var center := root.get_visible_rect().size * 0.5
	expect(bench.interaction_hit(center).get("action") == "thermal-camera", "Thermal camera cannot be picked from the desk")
	var interact := InputEventKey.new()
	interact.physical_keycode = KEY_E
	interact.pressed = true
	bench.first_person_input(interact)
	await create_timer(0.4).timeout
	expect(bench.tools.equipped_tool == "thermal-camera", "Thermal camera pickup failed")
	# Placing/retrieving is physical; Q remains an explicit return to its stand.
	expect(bench.tools.place(Vector3(6, -0.2926, 3.5), []), "Thermal camera could not be placed")
	await create_timer(0.4).timeout
	expect(bench.tools.thermal_location == "desk", "Placed thermal camera did not stay on desk")
	bench.tools.grab("thermal-camera")
	await create_timer(0.4).timeout
	expect(bench.tools.equipped_tool == "thermal-camera", "Placed thermal camera could not be picked up")
	bench.tools.equip("screwdriver")
	expect(bench.tools.equipped_tool == "thermal-camera", "Two tools could be equipped together")
	expect(not bench.testing_station.attach(), "Thermal camera bypassed empty-hand test-board rule")
	bench.tools.return_tool()
	await create_timer(0.4).timeout
	expect(bench.tools.thermal_camera.get_parent() == bench.tools.thermal_stand, "Camera did not return to its stand")
	expect(bench.testing_station.attach(), "Thermal test card did not attach")
	await create_timer(0.6).timeout
	bench.thermal.advance(60)
	var dirty_memory: float = bench.thermal.memory_c
	expect(dirty_memory > 85 and dirty_memory <= 94, "Dusty powered VRAM did not heat up")
	# Pick up the camera again then inspect exposed rear memory on the mounted card.
	bench.tools.equip("thermal-camera")
	await create_timer(0.4).timeout
	var chip: MeshInstance3D = bench.gpu.find_child("rear-memory-3", true, false)
	var target: Vector3 = chip.global_transform * chip.get_aabb().get_center()
	player.body.position = Vector3(target.x, -4.35, target.z - 6)
	player.update_camera()
	aim(bench, target)
	bench.thermal_viewer.aiming = true
	bench.thermal_viewer._process(0.2)
	var reading: Dictionary = bench.thermal_viewer.sample_center()
	expect(reading.get("mesh") == chip and reading.get("temperature", 0.0) > 80, "Thermal spot did not read the visible VRAM package")
	expect(chip.get_node_or_null("MemoryMarking") != null, "VRAM package has no visible identity")
	await capture(bench, "dirty")
	# A hidden front package must not show through the PCB in the rear view.
	var hidden: MeshInstance3D = bench.gpu.find_child("memory-package-0", true, false)
	aim(bench, hidden.global_transform * hidden.get_aabb().get_center())
	expect(bench.thermal_viewer.sample_center().get("mesh") != hidden, "Thermal camera sees through the PCB")
	aim(bench, target)
	bench.tools.return_tool()
	await create_timer(0.4).timeout
	bench.testing_station.detach()
	await create_timer(0.6).timeout
	bench.thermal.advance(1)
	expect(bench.thermal.memory_c < dirty_memory and bench.thermal.memory_c > 70, "Power removal did not retain slowly cooling heat")
	bench.cleaning.clean_part("fan-assembly")
	bench.cleaning.clean_part("cooler-assembly")
	expect(bench.cleaning.part_progress("board") < 0.01, "Internal-part cleaning unexpectedly cleaned the PCB")
	bench.testing_station.attach()
	await create_timer(0.6).timeout
	bench.thermal.advance(60)
	expect(bench.thermal.memory_c < dirty_memory - 25 and bench.thermal.memory_c > 50,
		"Cleaning internal parts did not lower VRAM heat under the same load")
	bench.cleaning.debug_clean()
	bench.thermal.advance(60)
	expect(absf(bench.thermal.memory_c - 48.0) < 1.0, "Clean powered VRAM did not settle to the healthy baseline")
	# Move near the physical camera before re-equipping; no inventory teleport pickup.
	player.body.position = Vector3(6, -4.35, 7)
	player.update_camera()
	bench.tools.equip("thermal-camera")
	await create_timer(0.4).timeout
	player.body.position = Vector3(target.x, -4.35, target.z - 6)
	player.update_camera()
	aim(bench, target)
	bench.thermal_viewer.aiming = true
	await capture(bench, "clean")
	reading = bench.thermal_viewer.sample_center()
	expect(reading.get("temperature", 100) < 50, "Clean VRAM still reads hot on the camera")
	bench.tools.return_tool()
	await create_timer(0.4).timeout
	bench.thermal_viewer._process(0.2)
	expect(not bench.thermal_viewer.panel.visible, "Returned thermal camera left the viewfinder visible")
	bench.testing_station.detach()
	await create_timer(0.6).timeout
	bench.thermal.advance(300)
	expect(absf(bench.thermal.memory_c - 24.0) < 0.1, "Unpowered VRAM did not cool to room temperature")
	bench.queue_free()
	await process_frame
	print("PASS: thermal pickup, exclusivity, occlusion, dust-driven heating, internal cleaning and cooldown" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
