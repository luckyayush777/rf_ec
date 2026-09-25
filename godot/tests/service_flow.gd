extends RefCounted

func run(tree: SceneTree, bench: Node3D, expect: Callable) -> void:
	var tools = bench.tools
	var service = bench.service
	var inspection = bench.inspection
	var camera: Camera3D = bench.camera_rig.camera
	service.set_muted(true)
	# Explicit ticks verify the real 1.5-second accumulation without wall-clock flakiness.
	service.set_process(false)
	expect.call(not service.begin_screw("fan-screw-1"), "Empty hands turned a screw")
	tools.equip()
	expect.call(tools.busy, "Equip did not lock the tool transition")
	expect.call(not service.toggle_cable(), "Cable moved during tool equip")
	inspection.lift()
	expect.call(not inspection.held, "GPU lifted during tool equip")
	await tree.create_timer(1.0).timeout
	expect.call(tools.open and tools.equipped_tool == "screwdriver" and not tools.busy, "Equip failed to open toolbox and retrieve screwdriver")
	expect.call(tools.screwdriver.get_parent() == camera, "Equipped screwdriver is not camera-relative")
	expect.call(not service.toggle_cable() and service.cable_connected, "Equipped screwdriver bypassed empty-hand cable rule")
	expect.call(not service.begin_screw("cooler-screw-1"), "Cooler screw removed with connected cable")
	inspection.lift()
	await tree.create_timer(0.55).timeout
	var screw: Node3D = bench.asset_contract.objects["fan-screw-1"]
	var screen: Vector2 = camera.unproject_position(screw.global_position)
	var hit: Dictionary = bench.picker.hit_at(screen)
	expect.call(hit.get("action", "") == "screw" and hit.get("target") == screw, "Front screw surface picking failed")
	var rear: Node3D = bench.asset_contract.objects["cooler-screw-1"]
	var rear_hit: Dictionary = bench.picker.hit_at(camera.unproject_position(rear.global_position))
	expect.call(rear_hit.get("target") != rear, "Hidden rear screw was pickable through PCB")
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = screen
	bench._unhandled_input(down)
	expect.call(service.active_screw == "fan-screw-1", "Pointer hold did not start the selected screw")
	service.advance_turn(0.45)
	expect.call(is_equal_approx(service.turns["fan-screw-1"].progress, 0.3), "Screw hold does not accumulate over 1.5 seconds")
	var held_pose: Transform3D = bench.gpu.transform
	var move := InputEventMouseMotion.new()
	move.position = screen + Vector2(100, 100)
	move.relative = Vector2(100, 100)
	bench._unhandled_input(move)
	inspection.flip()
	inspection.put_down()
	tools.return_tool()
	expect.call(inspection.held and bench.gpu.transform.is_equal_approx(held_pose), "Active screw allowed GPU rotation or placement")
	expect.call(tools.equipped_tool == "screwdriver", "Active screw allowed returning the tool")
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = screen
	bench._input(up)
	bench._unhandled_input(up)
	expect.call(service.active_screw == "" and not service.audio.playing, "Global release did not pause screw/audio")
	service.advance_turn(1.0)
	expect.call(is_equal_approx(service.turns["fan-screw-1"].progress, 0.3), "Paused screw progressed without a hold")
	# Independent paused turns survive moving the inspected card.
	service.begin_screw("fan-screw-2")
	service.advance_turn(0.15)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	bench._unhandled_input(escape)
	expect.call(service.active_screw == "" and tools.equipped_tool == "screwdriver", "Escape did not pause before returning the tool")
	service.begin_screw("fan-screw-2")
	bench._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	expect.call(service.active_screw == "", "Window blur did not cancel the screw hold")
	expect.call(is_equal_approx(service.turns["fan-screw-2"].progress, 0.1), "Second screw did not preserve its own progress")
	inspection.rotate_item(Vector2(12, 4))
	expect.call(service.begin_screw("fan-screw-1"), "Paused screw could not resume")
	service.advance_turn(1.2)
	expect.call(service.moving and "fan-screw-1" in service.removed, "Completed screw did not enter tray transfer")
	expect.call(not service.begin_screw("fan-screw-2"), "Concurrent screw started during tray transfer")
	await service.motion.finished
	expect.call(screw.get_parent() == bench, "Removed screw did not detach from GPU")
	expect.call(screw.position.is_equal_approx(Vector3(3.1, 0.2, 3.38)), "Fan screw used wrong tray slot")
	bench.begin_refit()
	service.advance_turn(0.3)
	service.end_screw()
	inspection.rotate_item(Vector2(-8, 7))
	expect.call(service.begin_screw("fan-screw-1"), "Paused refit could not resume")
	service.advance_turn(1.3)
	expect.call(screw.get_parent() == bench.asset_contract.homes["fan-screw-1"].parent, "Refit restored wrong parent")
	expect.call(screw.transform.is_equal_approx(bench.asset_contract.homes["fan-screw-1"].transform), "Refit accumulated transform drift")
	await tools.return_tool()
	expect.call(tools.location == "toolbox" and tools.screwdriver.transform.is_equal_approx(tools.home), "Tool return did not restore home")
	expect.call(service.toggle_cable(), "Empty hands could not unplug cable")
	expect.call(not service.toggle_cable(), "Cable animation allowed a second toggle")
	await service.motion.finished
	expect.call(not service.cable_connected and is_equal_approx(service.cable_progress, 1.0), "Cable did not reach unplugged state")
	var plug: Node3D = bench.asset_contract.objects["fan-plug"]
	var plug_home: Transform3D = bench.asset_contract.homes["fan-plug"].transform
	expect.call(plug.position.is_equal_approx(plug_home.origin + Vector3(0, 0.22, 0.58)), "Plug displacement differs from browser")
	for wire in service.wires:
		var original: PackedVector3Array = wire.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var bent: PackedVector3Array = wire.node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var changed := false
		for i in range(mini(original.size(), bent.size())):
			if original[i].distance_to(bent[i]) > 0.1: changed = true
		expect.call(changed, "Unplugging did not bend a wire")
	# Close then equip/return while holding the GPU; the tool owns the full sequence.
	await tools.toggle_box()
	await tools.equip()
	expect.call(tools.open and tools.equipped_tool == "screwdriver", "Closed-toolbox retrieval failed")
	inspection.flip()
	await tree.process_frame
	for id in service.cooler_screws:
		var node: Node3D = bench.asset_contract.objects[id]
		var back_hit: Dictionary = bench.picker.hit_at(camera.unproject_position(node.global_position))
		expect.call(back_hit.get("target") == node, "Rear screw is not reachable after flipping: " + id)
	inspection.flip()
	for id in service.fan_screws + service.cooler_screws:
		expect.call(service.begin_screw(id), "Could not remove " + id)
		service.advance_turn(1.5)
		await service.motion.finished
	expect.call(service.removed.size() == 8, "Not all screws reached their tray rows")
	# Desktop tray picking, including rear screws after they are detached.
	inspection.put_down()
	await tree.create_timer(0.55).timeout
	bench.select_view("top")
	for id in service.removed:
		var node: Node3D = bench.asset_contract.objects[id]
		var tray_hit: Dictionary = bench.picker.hit_at(camera.unproject_position(node.global_position))
		expect.call(tray_hit.get("action", "") == "screw" and tray_hit.get("target") == node, "Tray screw is not reachable: " + id)
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://build")
		bench.select_view("repair")
		await RenderingServer.frame_post_draw
		tree.root.get_texture().get_image().save_png("res://build/service-tray.png")
	for id in service.cooler_screws + service.fan_screws:
		bench.begin_refit()
		expect.call(service.active_screw == id, "Refit button did not follow cooler/fan tray order")
		service.advance_turn(1.5)
		var node: Node3D = bench.asset_contract.objects[id]
		expect.call(node.transform.is_equal_approx(bench.asset_contract.homes[id].transform), "Screw failed exact refit: " + id)
	expect.call(service.removed.is_empty() and service.turns.is_empty(), "Refit left stale screw state")
	# Whole-tool footprint rejects edges/obstacles and can be retrieved from the desk.
	expect.call(not tools.place(Vector3(9.5, 0, 5.5), []), "Tool placement crossed the desk edge")
	expect.call(not tools.place(Vector3.ZERO, [AABB(Vector3(-2, -1, -2), Vector3(4, 3, 4))]), "Tool placement ignored an obstacle")
	expect.call(tools.place(Vector3(0, 0, 5), bench.placement_obstacles()), "Clear tool placement was rejected")
	await tree.create_timer(0.4).timeout
	expect.call(tools.location == "desk" and tools.equipped_tool == "", "Placed screwdriver stayed equipped")
	bench.select_view("top")
	var tool_hit: Dictionary = bench.picker.hit_at(camera.unproject_position(tools.screwdriver.global_position))
	expect.call(tool_hit.get("action", "") == "screwdriver", "Placed tool is not pickable")
	await tools.grab()
	await tree.create_timer(0.4).timeout
	expect.call(tools.equipped_tool == "screwdriver", "Desk tool could not be retrieved")
	await tools.toggle_box()
	await tools.return_tool()
	expect.call(tools.open and tools.location == "toolbox", "Return did not reopen closed toolbox")
	expect.call(service.toggle_cable(), "Could not reconnect cable after refit")
	await service.motion.finished
	expect.call(plug.transform.is_equal_approx(plug_home), "Cable round trip changed plug home transform")
	for wire in service.wires:
		expect.call(wire.node.mesh == wire.mesh, "Reconnect did not restore original wire mesh")
	service.set_process(true)
	bench.select_view("repair")
	print("Service flow checked: equip/return/place, cable guards/deformation, front/rear/tray picking, pause/resume/cancel, all eight screw round trips.")
