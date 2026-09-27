extends SceneTree
const Contract = preload("res://scripts/asset_contract.gd")
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
func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/" + name + ".png")
func verify_left(bench: Node3D, part: Node3D) -> void:
	var bounds: AABB = Contract.bounds_in(part)
	var camera: Camera3D = bench.camera_rig.camera
	var width := root.get_visible_rect().size.x
	for i in range(8):
		var pixel := camera.unproject_position(part.global_transform * bounds.get_endpoint(i))
		expect(pixel.x < width * 0.49, "Held part obstructs the centre aiming ray")
	expect(part.global_basis.get_scale().is_equal_approx(Vector3.ONE * 0.25), "Holding altered physical scale")
func clear_point(bench: Node3D) -> Vector3:
	for x in [-6.0, -4.0, -2.0, 0.0]:
		for z in [2.0, 3.5, 0.0]:
			aim(bench, Vector3(x, 0, z))
			await process_frame
			await process_frame
			bench.update_placement_marker()
			if bench.placement_marker.visible and bench.placement_material.albedo_color == Color("#71e6b0"):
				return bench.interaction_hit(root.get_visible_rect().size * 0.5).point
	return Vector3.INF
func run() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	root.add_child(bench)
	await process_frame
	bench.camera_rig.set_physics_process(false)
	bench.camera_rig.body.position = Vector3(-3, -4.35, 6.2)
	bench.camera_rig.update_camera()
	bench.inspection.lift()
	await create_timer(0.55).timeout
	verify_left(bench, bench.gpu)
	var point: Vector3 = await clear_point(bench)
	expect(point.is_finite(), "No reachable highlighted placement spot for held GPU")
	if not point.is_finite():
		quit(1)
		return
	await capture("gpu-left-placement")
	var expected: Dictionary = bench.inspection.placement_for(point, bench.placement_obstacles("gpu"))
	bench.activate(root.get_visible_rect().size * 0.5)
	await create_timer(0.55).timeout
	expect(not bench.inspection.held and bench.gpu.global_transform.is_equal_approx(expected.destination), "GPU did not land at its indicated spot")
	expect(not bench.placement_marker.visible, "Placement marker remained after placing GPU")
	bench.inspection.lift()
	await create_timer(0.55).timeout
	bench.inspection.put_down()
	await create_timer(0.55).timeout
	expect(bench.gpu.transform.is_equal_approx(bench.inspection.home), "Q/return no longer restores the GPU holder pose")
	bench.service.debug_disassemble()
	bench.service.lift_assembly("fan-assembly")
	await create_timer(0.55).timeout
	verify_left(bench, bench.asset_contract.objects["fan-assembly"])
	bench.service.rotate_held(Vector2(80, 30))
	await process_frame
	await process_frame
	verify_left(bench, bench.asset_contract.objects["fan-assembly"])
	point = await clear_point(bench)
	expect(point.is_finite(), "No reachable highlighted placement spot for fan")
	if not point.is_finite():
		quit(1)
		return
	await capture("fan-left-placement")
	expected = bench.service.placement_for(point, bench.placement_obstacles("fan-assembly"))
	bench.activate(root.get_visible_rect().size * 0.5)
	await create_timer(0.55).timeout
	expect(bench.service.held_part == "" and bench.asset_contract.objects["fan-assembly"].global_transform.is_equal_approx(expected.destination),
		"Assembly did not land at the highlighted spot")
	bench.service.lift_assembly("cooler-assembly")
	await create_timer(0.55).timeout
	verify_left(bench, bench.asset_contract.objects["cooler-assembly"])
	# Aiming at the front desk edge must report the same rejected footprint as placement.
	var table: MeshInstance3D = bench.get_node("RepairDesk/Tabletop")
	var table_bounds: AABB = table.global_transform * table.get_aabb()
	aim(bench, Vector3(table_bounds.position.x + 0.1, table_bounds.end.y, 2))
	await process_frame
	await process_frame
	bench.update_placement_marker()
	expect(bench.placement_marker.visible and bench.placement_material.albedo_color == Color("#e57c63"), "Off-edge placement is not marked invalid")
	var edge_hit: Dictionary = bench.interaction_hit(root.get_visible_rect().size * 0.5)
	expect(not bench.service.place_assembly(edge_hit.point, bench.placement_obstacles("cooler-assembly")), "Invalid highlighted placement was accepted")
	bench.camera_rig.set_captured(false)
	bench.update_placement_marker()
	expect(not bench.placement_marker.visible, "Released mouse left placement marker visible")
	bench.queue_free()
	await process_frame
	print("PASS: left-hand framing, clear aim, placement marker, exact landing and invalid edge rejection" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
