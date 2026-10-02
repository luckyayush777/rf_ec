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
func run() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	root.add_child(bench)
	await process_frame
	bench.camera_rig.set_physics_process(false)
	bench.camera_rig.body.position = Vector3(3, -4.35, 6)
	bench.camera_rig.update_camera()
	await bench.tools.equip()
	bench.camera_rig.body.position = Vector3(-3, -4.35, 6)
	bench.camera_rig.update_camera()
	bench.camera_rig.camera.look_at(bench.gpu.global_position)
	var original: Transform3D = bench.gpu.global_transform
	expect(bench.open_service_view({"action": "gpu", "target": bench.gpu}), "GPU click with screwdriver did not open service view")
	if bench.closeup.mode == "":
		quit(1)
		return
	await process_frame
	await process_frame
	expect(not bench.camera_rig.captured, "Service window did not release pointer")
	expect(bench.gpu.global_transform.is_equal_approx(original), "Close-up changed physical GPU transform")
	var view = bench.closeup
	var screw: Node3D = bench.asset_contract.objects["fan-screw-1"]
	# Face the mounted fan directly, then use actual GUI input and viewport coordinates.
	view.direction = bench.gpu.global_basis.y.normalized()
	view.update_camera()
	await process_frame
	var screen: Vector2 = view.camera.unproject_position(screw.global_position)
	expect(view.pick.hit_at(screen).get("target") == screw, "Enlarged screw is not pickable")
	await capture("service-closeup-front")
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = screen + view.surface.global_position
	if DisplayServer.get_name() == "headless":
		down.position = screen
		view.view_input(down)
	else: root.push_input(down)
	await process_frame
	expect(bench.service.active_screw == "fan-screw-1", "Real GUI press did not start screw hold")
	bench.service.end_screw()
	bench.service.begin_screw("fan-screw-1")
	bench.service.advance_turn(1.5)
	await create_timer(0.75).timeout
	expect("fan-screw-1" in bench.service.removed, "Close-up removal failed")
	var seat: Node3D = bench.service.screw_seats["fan-screw-1"]
	screen = view.camera.unproject_position(seat.global_position)
	var hit: Dictionary = view.pick.hit_at(screen)
	expect(hit.get("action") == "screw_hole", "Removed screw hole is not pickable in close-up")
	down.position = screen
	view.view_input(down)
	bench.service.end_screw()
	expect(screw.get_parent() == bench.asset_contract.homes["fan-screw-1"].parent, "Hole click did not instantly seat screw")
	expect(screw.position.distance_to(seat.position) < 0.35, "Seated screw remains in tray")
	var seated: Transform3D = screw.transform
	await create_timer(0.1).timeout
	expect(screw.transform.is_equal_approx(seated), "Released screw continued tightening")
	bench.service.begin_screw("fan-screw-1")
	bench.service.advance_turn(0.4)
	bench._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	expect(bench.service.active_screw == "", "Focus loss did not pause close-up hold")
	bench.service.begin_screw("fan-screw-1")
	bench.service.advance_turn(1.5)
	expect(screw.transform.is_equal_approx(bench.asset_contract.homes["fan-screw-1"].transform), "Close-up refit did not restore exact screw transform")
	view.direction = -bench.gpu.global_basis.y.normalized()
	view.update_camera()
	await process_frame
	await capture("service-closeup-rear")
	view.request_close()
	expect(view.mode == "" and bench.camera_rig.captured, "Close did not resume captured play")
	expect(bench.gpu.global_transform.is_equal_approx(original), "Service changed physical scale/pose")
	# Reopening a hole from play seats it immediately, without starting a hidden hold.
	bench.service.begin_screw("fan-screw-1")
	bench.service.advance_turn(1.5)
	await create_timer(0.75).timeout
	expect(bench.open_service_view({"action": "screw_hole", "target": seat}), "Hole did not open close-up")
	expect(screw.get_parent() == seat.get_parent() and bench.service.active_screw == "", "Opening hole did not seat and pause screw")
	await process_frame
	var found := false
	for proxy in view.proxies:
		if proxy.source == screw or screw.is_ancestor_of(proxy.source):
			found = found or proxy.node.visible
	expect(found, "Screw returned from tray is missing from reopened close-up")
	bench.service.begin_screw("fan-screw-1")
	bench.service.advance_turn(1.5)
	await view.return_equipped_tool()
	# Unplug/reconnect without reopening focus: both wires must follow the live geometry.
	for connected in [false, true]:
		expect(bench.service.toggle_cable(), "Close-up cable toggle failed")
		await bench.service.motion.finished
		view.sync_proxies()
		var wires := 0
		for proxy in view.proxies:
			if String(proxy.source.name) in ["fan-positive-wire", "fan-ground-wire"]:
				wires += 1
				expect(proxy.node.mesh == proxy.source.mesh, "Close-up cable geometry is stale")
		expect(wires == 2 and bench.service.cable_connected == connected, "Close-up cable state or wire proxies missing")
		await capture("service-cable-connected" if connected else "service-cable-unplugged")
	view.close()
	bench.queue_free()
	await process_frame
	print("PASS: live close-up GUI picking, instant seating, pause/resume, focus loss, exact refit and physical scale" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
