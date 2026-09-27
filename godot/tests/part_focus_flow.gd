extends SceneTree
const Contract = preload("res://scripts/asset_contract.gd")
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
	event.pressed = true
	event.physical_keycode = code
	bench.first_person_input(event)
func run() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	root.add_child(bench)
	await process_frame
	bench.camera_rig.set_physics_process(false)
	bench.camera_rig.body.position = Vector3(0, -4.35, 6.2)
	bench.camera_rig.update_camera()
	expect(bench.service.debug_disassemble(), "Setup disassembly failed")
	await bench.tools.equip("dev-blower")
	var view = bench.closeup
	for id in ["fan-assembly", "cooler-assembly"]:
		var part: Node3D = bench.asset_contract.objects[id]
		var other := "cooler-assembly" if id == "fan-assembly" else "fan-assembly"
		var other_progress: float = bench.cleaning.part_progress(other)
		var board_progress: float = bench.cleaning.part_progress("board")
		expect(bench.open_service_view({"action": "assembly", "target": part}), "Cannot focus a detached part directly: " + id)
		expect(view.subject == part, "Focus selected PCB instead of detached part")
		view.close()
		var aimed := false
		for mesh in part.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null: continue
			bench.camera_rig.camera.look_at(mesh.global_transform * mesh.get_aabb().get_center())
			var hit: Dictionary = bench.interaction_hit(root.get_visible_rect().size * 0.5)
			if hit.get("target") == part:
				aimed = true
				break
		expect(aimed, "Detached assembly cannot be targeted from the bench")
		key(bench, KEY_E)
		await create_timer(0.55).timeout
		expect(bench.service.held_part == id, "E did not pick up targeted detached part with blower: " + id)
		var pose: Basis = part.global_basis
		key(bench, KEY_F)
		expect(not part.global_basis.is_equal_approx(pose), "Tool blocked detached-part flip")
		key(bench, KEY_R)
		await process_frame
		await process_frame
		expect(view.subject == part and view.mode == "service", "E focus did not select held assembly")
		var before: float = view.subject_cleaning_progress()
		var physical_pose: Transform3D = part.global_transform
		for proxy in view.proxies:
			if proxy.node.visible:
				expect(part == proxy.source or part.is_ancestor_of(proxy.source), "Unrelated part leaked into focus")
		view.direction = part.global_basis.y.normalized()
		view.update_camera()
		await capture(id + "-focus-before")
		var down := InputEventMouseButton.new()
		down.button_index = MOUSE_BUTTON_LEFT
		down.pressed = true
		down.position = view.surface.size * 0.5
		for side in range(2):
			view.view_input(down)
			for y in range(20, int(view.surface.size.y) - 20, 24):
				for x in range(20, int(view.surface.size.x) - 20, 24):
					view.cleaning_pointer = Vector2(x, y)
					view.clean_under_pointer(0.05)
			bench.cleaning.end()
			view.direction = -view.direction
			view.update_camera()
		expect(view.subject_cleaning_progress() > before + 0.05, "Detached part could not be cleaned through focus: " + id)
		expect(is_equal_approx(bench.cleaning.part_progress(other), other_progress) and is_equal_approx(bench.cleaning.part_progress("board"), board_progress),
			"Cleaning selected part changed unrelated dust")
		expect(part.global_transform.is_equal_approx(physical_pose), "Focus rotation changed actual part pose/scale")
		await capture(id + "-focus-cleaned")
		view.return_area.pressed.emit()
		await create_timer(0.4).timeout
		expect(bench.tools.equipped_tool == "" and bench.service.held_part == id, "Returning tool lost the held assembly")
		view.close()
		# A tool can also be picked up after taking the detached part in the left hand.
		await bench.tools.equip("screwdriver")
		expect(bench.tools.equipped_tool == "screwdriver", "Held assembly prevented equipping another tool")
		await bench.tools.return_tool()
		bench.service.store_assembly()
		await bench.tools.equip("dev-blower")
	# Additional metadata-defined assemblies take the same route without a name allowlist.
	var extra := Node3D.new()
	extra.name = "aux-cover"
	extra.position = bench.gpu.global_position + Vector3(1, 0.5, 0)
	bench.add_child(extra)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	extra.add_child(mesh)
	var definition := {"id": "aux-cover", "kind": "assembly", "requires": [], "parent": "gpu"}
	bench.asset_contract.service_parts.append(definition)
	bench.asset_contract.objects["aux-cover"] = extra
	bench.service_rules.parts["aux-cover"] = definition
	bench.service_rules.removal["aux-cover"] = []
	bench.service.removed.append("aux-cover")
	expect(bench.service.lift_assembly("aux-cover"), "Inspection still hard-codes fan/cooler IDs")
	await create_timer(0.55).timeout
	key(bench, KEY_R)
	expect(view.subject == extra and view.proxies.size() == 1, "Metadata-defined assembly did not receive its own focus view")
	view.close()
	bench.queue_free()
	await process_frame
	print("PASS: detached fan/heatsink flip and clean, isolated dust, tool switching, and metadata-defined part focus" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
