extends SceneTree
var failures: Array[String] = []
func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	root.add_child(bench)
	await process_frame
	bench.set_process_unhandled_input(false)
	var player = bench.camera_rig
	expect(player.body != null and player.camera.fov == 65.0, "First-person player did not start")
	player.set_captured(true)
	player.movement_override = Vector2(0, -1)
	for i in range(100): await physics_frame
	player.movement_override = Vector2.ZERO
	expect(player.body.position.z > 5.7 and player.body.position.z < 7.0, "Player crossed the repair desk or failed to walk")
	expect(player.body.is_on_floor(), "Player fell through the room floor")
	var old_yaw: float = player.look_yaw
	var old_pitch: float = player.look_pitch
	player.look(Vector2(100, 30))
	expect(player.look_yaw != old_yaw and player.look_pitch < old_pitch, "Mouse look did not turn the first-person camera")
	var old_position: Vector3 = player.body.position
	player.set_captured(false)
	player.movement_override = Vector2(1, 0)
	for i in range(10): await physics_frame
	player.movement_override = Vector2.ZERO
	expect(player.body.position.distance_to(old_position) < 0.01, "Released mouse still allowed movement")
	# A nearby held GPU follows the player camera and returns to its original holder.
	player.set_captured(true)
	player.camera.look_at(bench.gpu.global_transform * bench.inspection.center)
	player.look_pitch = player.camera.rotation.x
	player.look_yaw = player.camera.rotation.y
	var interact := InputEventKey.new()
	interact.physical_keycode = KEY_E
	interact.pressed = true
	bench.first_person_input(interact)
	await create_timer(0.55).timeout
	expect(bench.inspection.held, "Nearby GPU could not be picked up")
	var before: Vector3 = bench.gpu.global_position
	player.look(Vector2(80, 0))
	await process_frame
	await process_frame
	expect(bench.gpu.global_position.distance_to(before) > 0.1, "Held GPU did not follow first-person look")
	bench.inspection.put_down()
	await create_timer(0.55).timeout
	expect(bench.gpu.transform.is_equal_approx(bench.inspection.home), "GPU did not return to its holder")
	bench.inspection.lift()
	await create_timer(0.55).timeout
	player.body.position = Vector3(15, -4.35, 7)
	player.update_camera()
	for i in range(15): await physics_frame
	var walking_pose: Transform3D = player.camera.global_transform
	bench.toggle_test_gpu()
	await create_timer(0.6).timeout
	expect(bench.testing_station.installed and not bench.inspection.held, "Carried GPU did not transfer to the test board")
	expect(player.camera.global_transform.is_equal_approx(walking_pose), "Testing switched away from the player's perspective")
	bench.toggle_test_gpu()
	await create_timer(0.6).timeout
	expect(not bench.testing_station.installed and bench.gpu.transform.is_equal_approx(bench.inspection.home), "Testing did not return the card to its holder")
	player.body.position = Vector3(28, -4.35, 12)
	player.update_camera()
	bench.inspection.lift()
	expect(not bench.inspection.held, "Player picked up GPU across the room")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		player.body.position = Vector3(-3, -4.35, 9)
		player.look_pitch = -0.22
		player.look_yaw = 0.0
		player.update_camera()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/first-person.png")
	bench.queue_free()
	await process_frame
	print("PASS: first-person movement, collision, mouse release and pickup/return" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
