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
func key(bench: Node3D, code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	bench.first_person_input(event)
func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/" + name + ".png")
func run() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	root.add_child(bench)
	await process_frame
	bench.camera_rig.set_physics_process(false)
	bench.camera_rig.body.position = Vector3(-3, -4.35, 6.2)
	bench.camera_rig.update_camera()
	var card_center: Vector3 = bench.gpu.global_transform * Contract.bounds_in(bench.gpu).get_center()
	var rail_center: Vector3 = (bench.get_node("RepairDesk/HolderRail0").global_position + bench.get_node("RepairDesk/HolderRail1").global_position) * 0.5
	expect(absf(rail_center.z - card_center.z) < 0.01 and absf(rail_center.x - card_center.x) < 0.01, "Clamp is behind the GPU instead of centred under it")
	aim(bench, card_center)
	await capture("clamp-front")
	bench.camera_rig.body.position = Vector3(3, -4.35, 6.2)
	bench.camera_rig.update_camera()
	await bench.tools.equip("dev-blower")
	bench.camera_rig.body.position = Vector3(-3, -4.35, 6.2)
	bench.camera_rig.update_camera()
	aim(bench, card_center)
	key(bench, KEY_E)
	await create_timer(0.55).timeout
	expect(bench.inspection.held and bench.tools.equipped_tool == "dev-blower", "E could not pick up GPU while blower equipped")
	var facing: Basis = bench.gpu.global_basis
	key(bench, KEY_F)
	expect(not bench.gpu.global_basis.is_equal_approx(facing), "Tool prevented flipping the held GPU")
	key(bench, KEY_R)
	await process_frame
	await process_frame
	var view = bench.closeup
	expect(view.mode == "service", "Held GPU with blower could not enter focus mode")
	view.direction = -bench.gpu.global_basis.y.normalized()
	view.update_camera()
	await process_frame
	await capture("blower-backplate-focus")
	var before: float = bench.cleaning.part_progress("board")
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = view.surface.size * 0.5
	view.view_input(down)
	expect(bench.cleaning.blowing, "Focus press did not start blower")
	# Sweep only the visible rear image; real mesh normals/masks and nozzle checks apply.
	for y in range(40, int(view.surface.size.y) - 40, 20):
		for x in range(40, int(view.surface.size.x) - 40, 20):
			view.cleaning_pointer = Vector2(x, y)
			view.clean_under_pointer(0.05)
	expect(bench.cleaning.part_progress("board") > before + 0.05, "Backplate dust did not clear through the focus view")
	down.pressed = false
	view.view_input(down)
	expect(not bench.cleaning.blowing, "Release did not stop focused cleaning")
	await capture("blower-backplate-cleaned")
	view.return_area.pressed.emit()
	await create_timer(1.0).timeout
	expect(bench.tools.equipped_tool == "" and view.mode == "service" and bench.inspection.held,
		"Return region did not put tool away while retaining GPU focus")
	view.close()
	bench.inspection.put_down()
	await create_timer(0.55).timeout
	await bench.tools.equip("screwdriver")
	aim(bench, card_center)
	key(bench, KEY_E)
	await create_timer(0.55).timeout
	expect(bench.inspection.held and bench.tools.equipped_tool == "screwdriver", "Screwdriver routed E into focus instead of picking up GPU")
	key(bench, KEY_F)
	key(bench, KEY_R)
	await process_frame
	expect(view.mode == "service", "Screwdriver focus failed after pickup/flip")
	view.return_area.pressed.emit()
	await create_timer(0.4).timeout
	expect(bench.tools.equipped_tool == "", "Focus return region did not return screwdriver")
	view.close()
	bench.queue_free()
	await process_frame
	print("PASS: tool-equipped pickup/flip, backplate focus cleaning, tool return region and forward clamp alignment" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
