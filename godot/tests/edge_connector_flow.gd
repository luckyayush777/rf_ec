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
func look(bench: Node3D, at: Vector3, target: Vector3) -> void:
	var player = bench.camera_rig
	player.body.global_position = at
	player.update_camera()
	player.camera.look_at(target)
	player.look_pitch = player.camera.rotation.x
	player.look_yaw = player.camera.rotation.y
	player.update_camera()
	player.set_captured(true)
	await physics_frame
func mouse_button(bench: Node3D, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	bench.first_person_input(event)
func wiggle(bench: Node3D, strokes: int) -> void:
	for stroke in range(strokes):
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(60.0 if stroke % 2 == 0 else -60.0, 0)
		bench.first_person_input(motion)
		for frame in range(3): await process_frame
## Runs the connector and thermal model for simulated seconds without waiting.
func run_for(bench: Node3D, seconds: float, step: float = 0.05) -> void:
	for tick in range(roundi(seconds / step)):
		bench.thermal.advance(step)
		bench.connector.step(step)
func settle(_bench: Node3D, seconds: float) -> void:
	for tick in range(roundi(seconds / 0.05)): await create_timer(0.05).timeout
func run() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	root.add_child(bench)
	await process_frame
	var edge: Node = bench.connector
	var monitor: Node3D = bench.test_monitor
	var station: Node = bench.testing_station
	expect(edge.state == "ok" and edge.contacts.size() == 66, "Connector did not start clean with 66 contacts (%d)" % edge.contacts.size())
	# Jobs never roll connector damage yet, but a damaged card is still a problem on return.
	expect(not bench.jobs.FAULTS.has("connector"), "Jobs can roll connector damage before a repair exists")
	expect(edge.debug_cycle() == OS.is_debug_build() and edge.state == ("oxidised" if OS.is_debug_build() else "ok"), "Debug cycle did not step the connector")
	expect("connector" in bench.jobs.problems() or not OS.is_debug_build(), "Connector damage was not a problem on return")
	bench.jobs.apply_faults(["dust"])
	expect(edge.state == "ok", "A new job card did not arrive with clean contacts")

	# A clean, cool card: any frame-rate cap comes from the link alone.
	bench.debug_clean_gpu()
	bench.paste.debug_repaste()
	if bench.bearing.dry: bench.bearing.debug_oil()
	expect(station.attach(), "Card would not seat on the test board")
	await settle(bench, 0.7)
	monitor.toggle_power()
	run_for(bench, 8.0)
	expect(monitor.link_width == 16 and monitor.simulated_fps == 60 and "x16" in monitor.readout.text, "Healthy card did not show a full x16 link at 60 FPS")

	edge.set_state("torn")
	run_for(bench, 1.0)
	expect(monitor.link_width == 4 and monitor.simulated_fps == bench.test_monitor.LINK_FPS[4] and "x4" in monitor.readout.text, "Torn finger did not narrow the link to x4")
	expect(bench.thermal.core_c < bench.thermal.THROTTLE_START and bench.thermal.core_clock() == bench.thermal.BOOST_CLOCK, "Narrow-link card was not cool at full clock")
	expect(not edge.contacts[edge.TORN].visible and edge.scar.all(func(node): return node.visible), "Torn finger was not drawn as missing")
	await look(bench, Vector3(15.5, -4.43, 6.5), monitor.global_position + Vector3(0, 2.3, 0))
	await capture("connector-monitor-x4")

	edge.set_state("oxidised")
	edge.rng.seed = 11
	expect(edge.contacts[edge.TARNISHED[0]].material_override == edge.tarnish, "Oxidised fingers were not tarnished")
	var lost := false
	for tick in range(1200):
		run_for(bench, 0.05)
		if monitor.link_width == 0:
			lost = true
			break
	expect(lost and not monitor.has_picture() and "LINK LOST" in monitor.readout.text, "Oxidised fingers never dropped the link")
	run_for(bench, 1.2)
	expect(monitor.link_width == 8 and monitor.has_picture(), "Oxidised link did not retrain at x8")

	# A lifted finger holds steady until the seated card is rocked: hold LMB on it and move the mouse.
	edge.set_state("lifted")
	var drops: int = edge.drops
	run_for(bench, 30.0)
	expect(edge.drops == drops and monitor.link_width == 16, "Lifted finger dropped out without being touched")
	var home: Transform3D = edge.homes[edge.LIFTED]
	expect((edge.contacts[edge.LIFTED].transform * Vector3(0, 0, edge.HALF_LENGTH)).y > (home * Vector3(0, 0, edge.HALF_LENGTH)).y + 0.01, "Lifted finger's tip was not raised")
	await look(bench, Vector3(17.6, -4.43, 5.0), bench.gpu.global_transform * Vector3(0, 0, 0.6))
	var centre: Vector2 = root.get_visible_rect().size * 0.5
	expect(bench.seated_card(bench.interaction_hit(centre)), "The seated card was not the aimed target")
	mouse_button(bench, true)
	expect(station.wiggling, "Holding LMB on the seated card did not grab it")
	var look_yaw: float = bench.camera_rig.look_yaw
	var down := false
	for attempt in range(6):
		await wiggle(bench, 2)
		if monitor.link_width == 0: down = true
	expect(down, "Rocking the card did not open the lifted finger")
	expect(is_equal_approx(bench.camera_rig.look_yaw, look_yaw), "Rocking the card also turned the view")
	await capture("connector-rocking")
	mouse_button(bench, false)
	expect(not station.wiggling and station.installed, "Releasing LMB removed the card or kept rocking")
	await settle(bench, 1.6)
	expect(monitor.link_width == 16 and station.rock_angle == 0.0 and bench.gpu.global_transform.is_equal_approx(station.seated_pose), "Card did not settle and retrain after rocking")
	edge.set_state("ok")
	drops = edge.drops
	mouse_button(bench, true)
	await wiggle(bench, 8)
	mouse_button(bench, false)
	expect(edge.drops == drops, "Rocking a healthy card dropped the link")
	await settle(bench, 1.0)
	# A rendered run's window can lose focus and release the mouse; play needs it captured.
	bench.camera_rig.set_captured(true)
	var interact := InputEventKey.new()
	interact.physical_keycode = KEY_E
	interact.pressed = true
	bench.first_person_input(interact)
	await settle(bench, 0.7)
	expect(not station.installed, "E did not remove the seated card")

	# The loupe: a pocket in the roll, a lens over the focus view, framed on the gold fingers.
	edge.set_state("lifted")
	await look(bench, Vector3(-3.0, -4.43, 9.0), bench.gpu.global_transform * bench.inspection.center)
	bench.open_tool_menu(true)
	await settle(bench, 0.8)
	await bench.select_tool("loupe")
	await settle(bench, 1.0)
	expect(bench.tools.equipped_tool == "loupe", "Loupe could not be taken from the tool roll")
	bench.camera_rig.set_captured(true)
	var hit: Dictionary = bench.interaction_hit(root.get_visible_rect().size * 0.5)
	expect(bench.open_service_view(hit) or bench.closeup.mode == "service", "Clicking the GPU with the loupe did not open focus")
	if bench.closeup.mode != "service": bench.closeup.show_view("service", bench.gpu)
	await process_frame
	await process_frame
	var view: CanvasLayer = bench.closeup
	expect(view.lens.visible and not view.progress.visible, "Loupe focus had no lens")
	expect(view.center.distance_to(edge.centre()) < 0.01, "Loupe focus was not framed on the edge connector")
	await capture("connector-loupe")
	var lifted: MeshInstance3D = edge.contacts[edge.LIFTED]
	var target: Vector2 = view.camera.unproject_position(lifted.global_position)
	var before: float = view.zoom
	view.magnify_at(target)
	await settle(bench, 0.35)
	view.magnify_at(view.camera.unproject_position(lifted.global_position))
	await settle(bench, 0.35)
	expect(view.zoom < before * 0.3 and view.center.distance_to(lifted.global_position) < 0.05, "Clicking with the loupe did not centre and magnify")
	for wheel in range(30):
		var scroll := InputEventMouseButton.new()
		scroll.button_index = MOUSE_BUTTON_WHEEL_UP
		scroll.pressed = true
		view.view_input(scroll)
	expect(is_equal_approx(view.zoom, view.LOUPE_ZOOM), "The loupe did not allow its deep zoom")
	view.zoom = 0.12
	view.center = lifted.global_position
	await capture("connector-loupe-lifted")
	edge.set_state("torn")
	view.center = edge.contacts[edge.TORN].global_position
	await process_frame
	await capture("connector-loupe-torn")
	edge.set_state("oxidised")
	view.zoom = 0.25
	view.center = edge.contacts[edge.TARNISHED[2]].global_position
	# process_frame resumes before nodes process; the view syncs its proxies a frame later.
	await process_frame
	await process_frame
	expect(view.proxies.any(func(proxy): return proxy.source == edge.contacts[edge.TARNISHED[2]] and proxy.node.material_override == edge.tarnish),
		"The focus view did not show the tarnish")
	await capture("connector-loupe-oxidised")
	view.close()
	bench.queue_free()
	await process_frame
	print("PASS: edge connector link width and FPS cap, oxidised dropouts, lifted-finger wiggle test, torn-finger x4, loupe focus and magnify, jobs never roll it" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
