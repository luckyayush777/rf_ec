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
func key(bench: Node3D, code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	bench.first_person_input(event)
func place_held(bench: Node3D) -> void:
	for x in [-6.0, -4.0, -2.0, 0.0]:
		for z in [2.0, 0.0, -2.0, 3.5]:
			bench.camera_rig.camera.look_at(Vector3(x, -0.27, z))
			await process_frame
			await process_frame
			bench.update_placement_marker()
			if not bench.placement_marker.visible or bench.placement_material.albedo_color != Color("#71e6b0"): continue
			key(bench, KEY_E)
			await create_timer(0.55).timeout
			expect(not bench.inspection.held and bench.service.held_part == "", "E on mat did not release the part")
			expect(bench.tools.equipped_tool == "screwdriver", "Placing the part put down the screwdriver instead")
			return
	expect(false, "No valid placement found with screwdriver equipped")
func run() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	root.add_child(bench)
	await process_frame
	bench.camera_rig.set_physics_process(false)
	bench.camera_rig.body.position = Vector3(0, -4.35, 6.2)
	bench.camera_rig.update_camera()
	var service = bench.service
	await bench.tools.equip()
	# Full card can be placed while keeping the screwdriver.
	bench.inspection.lift()
	await create_timer(0.55).timeout
	await place_held(bench)
	bench.open_service_view({"action": "gpu", "target": bench.gpu})
	var view = bench.closeup
	view.return_area.pressed.emit()
	await create_timer(0.4).timeout
	# Cable manipulation works inside focus after returning the tool.
	var plug: Node3D = bench.asset_contract.objects["fan-plug"]
	view.direction = bench.gpu.global_basis.y.normalized()
	view.update_camera()
	await process_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = view.camera.unproject_position(plug.global_position)
	view.view_input(click)
	await create_timer(0.3).timeout
	expect(not service.cable_connected, "Focus view did not unplug the fan cable")
	view.close()
	await bench.tools.equip()
	for id in service.fan_screws:
		expect(service.begin_screw(id), "Cannot undo fan screw")
		service.advance_turn(1.5)
		await create_timer(0.72).timeout
	await bench.tools.return_tool()
	expect(service.lift_assembly("fan-assembly"), "First part could not be removed")
	await create_timer(0.55).timeout
	await bench.tools.equip()
	# Holding the removed fan does not block turning a heatsink screw on the board.
	expect(bench.open_service_view({"action": "gpu", "target": bench.gpu}), "Board cannot be serviced with the fan removed")
	view.direction = -bench.gpu.global_basis.y.normalized()
	view.update_camera()
	await process_frame
	var first_id: String = service.cooler_screws[0]
	click.position = view.camera.unproject_position(bench.asset_contract.objects[first_id].global_position)
	view.view_input(click)
	expect(service.active_screw == first_id, "Holding fan and screwdriver still blocks heatsink screw")
	service.advance_turn(1.5)
	await create_timer(0.72).timeout
	expect(first_id in service.removed and service.held_part == "fan-assembly", "Heatsink screw removal lost held fan")
	await capture("heatsink-service-after-fan")
	view.close()
	await place_held(bench)
	# Partial board stays serviceable after another pickup and mat placement.
	bench.inspection.lift()
	await create_timer(0.55).timeout
	await place_held(bench)
	bench.open_service_view({"action": "gpu", "target": bench.gpu})
	view.direction = -bench.gpu.global_basis.y.normalized()
	view.update_camera()
	for id in service.cooler_screws:
		if id in service.removed: continue
		click.position = view.camera.unproject_position(bench.asset_contract.objects[id].global_position)
		view.view_input(click)
		expect(service.active_screw == id, "Partially dismantled board on mat cannot continue screw service")
		service.advance_turn(1.5)
		await create_timer(0.72).timeout
	view.return_area.pressed.emit()
	await create_timer(0.4).timeout
	view.direction = bench.gpu.global_basis.y.normalized()
	view.update_camera()
	await process_frame
	var cooler: Node3D = bench.asset_contract.objects["cooler-assembly"]
	var found := false
	for mesh in cooler.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		click.position = view.camera.unproject_position(mesh.global_transform * mesh.get_aabb().get_center())
		if view.pick.hit_at(click.position).get("target") == cooler:
			found = true
			view.view_input(click)
			break
	expect(found, "Loosened heatsink cannot be picked in focus")
	await create_timer(0.55).timeout
	expect(service.held_part == "cooler-assembly" and view.mode == "", "Focus click did not lift loosened heatsink")
	await bench.tools.equip()
	await place_held(bench)
	bench.inspection.lift()
	await create_timer(0.55).timeout
	await place_held(bench)
	expect(bench.open_service_view({"action": "gpu", "target": bench.gpu}), "Bare board on mat cannot open focus")
	view.close()
	bench.queue_free()
	# The audio server drops a sound still playing at free only a few frames later; quitting
	# sooner reports its stream as leaked at exit.
	for frame in range(10): await process_frame
	print("PASS: staged fan/heatsink removal, screw service with occupied left hand, tool-retaining placement and full/partial/bare board focus" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
