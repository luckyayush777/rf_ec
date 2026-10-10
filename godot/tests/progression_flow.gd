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
func stand(bench: Node3D, at: Vector3, target: Vector3) -> void:
	bench.camera_rig.body.global_position = at
	bench.camera_rig.update_camera()
	bench.camera_rig.camera.look_at(target)
	bench.camera_rig.look_pitch = bench.camera_rig.camera.rotation.x
	bench.camera_rig.look_yaw = bench.camera_rig.camera.rotation.y
	bench.camera_rig.update_camera()
	await process_frame
func key(bench: Node3D, code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	bench._unhandled_input(event)
func click_page(bench: Node3D, name: String) -> void:
	var control: Control = bench.computer.viewport.find_child(name, true, false)
	expect(control != null, "Missing website control " + name)
	if control == null: return
	bench.computer.page_scroll.ensure_control_visible(control)
	await process_frame
	var screen: Vector2 = bench.camera_rig.camera.unproject_position(bench.computer.world_point(control.get_global_rect().get_center()))
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = screen
		event.global_position = screen
		bench._unhandled_input(event)
		await process_frame
	await process_frame
func run() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	bench.progression_enabled = true
	root.add_child(bench)
	await process_frame
	bench.camera_rig.set_physics_process(false)
	var shop: Node = bench.shop
	expect(not bench.tools.thermal_stand.is_visible_in_tree(), "Unpurchased thermal stand remained in the starter shop")
	var jobs: Node = bench.jobs
	expect(shop != null and shop.unlimited_funds, "Progression did not start with unlimited funds")
	expect(not bench.gpu.visible and jobs.queue.is_empty(), "Starter shop was not empty")
	expect(shop.owned.keys() == ["air-blower"], "Starter shop owned more than the dusting tool")
	expect(not bench.testing_station.available and not shop.equipment["test-station"].visible and not bench.queue_monitor.visible, "Unbought testing equipment was on the floor")
	expect(not bench.testing_station.attach(), "The unowned test station could be used")
	expect(bench.day_cycle.environment.ambient_light_energy > 0.6, "Starter room was not evenly lit")
	expect(bench.find_child("BenchTaskLight", true, false) == null, "A lamp pooled light over the starter bench")
	var table: MeshInstance3D = bench.get_node("RepairDesk/Tabletop")
	var bounds := table.global_transform * table.get_aabb()
	expect(bounds.size.x <= 12.01 and bounds.size.z <= 8.01, "Starter bench kept the oversized dimensions")
	expect(bench.gpu.scale.is_equal_approx(Vector3.ONE * 0.25), "Shrinking the bench changed GPU scale")
	await stand(bench, Vector3(21, -4.35, 6), Vector3(18, 0, -5))
	bench.refresh_ui()
	await capture("progression-starter-room")
	# Native starter walls and floor must contain the first-person player.
	var space: PhysicsDirectSpaceState3D = bench.get_world_3d().direct_space_state
	for line in [[Vector3(18, 2, 0), Vector3(9, 2, 0)], [Vector3(18, 2, -12), Vector3(18, 2, -18)],
			[Vector3(24, 0, 6), Vector3(24, -6, 6)]]:
		expect(not space.intersect_ray(PhysicsRayQueryParameters3D.create(line[0], line[1], 1)).is_empty(), "The smaller shop lost a wall or floor collision")
	bench.tools.toolbox.set_opening(1.0)
	for id in bench.tools.TOOLS:
		if id == "air-blower": continue
		expect(not bench.tools.tool_node(id).is_visible_in_tree(), "Unrolling exposed an unowned tool: " + id)
	await bench.tools.equip("screwdriver")
	expect(bench.tools.equipped_tool == "", "Unowned screwdriver could be equipped")
	bench.tools.toolbox.set_opening(0.0)
	var starter: Dictionary = jobs.offers[0]
	var paste_job: Dictionary = jobs.offers[1]
	expect(starter.get("exterior_clean", false) and jobs.missing_equipment(starter).is_empty(), "There was no finishable starter job")
	expect(not jobs.accept(paste_job.id) and jobs.queue.is_empty(), "A job without repair equipment was accepted")
	# Real screen input: F4 and a purchase button through the curved CRT surface.
	await stand(bench, Vector3(17, -4.35, 4), bench.computer.screen.global_position)
	bench.computer.use()
	await create_timer(0.45).timeout
	await capture("progression-locked-jobs")
	key(bench, KEY_F4)
	await process_frame
	await process_frame
	expect(bench.computer.tab == "shop", "F4 did not open the supply website")
	await capture("progression-supply-tools")
	var funds: int = jobs.balance
	shop.set_unlimited(false)
	jobs.balance = 0
	expect(not shop.purchase("screwdriver") and not shop.owns("screwdriver"), "Insufficient funds still bought a tool")
	jobs.balance = funds
	expect(shop.purchase("loupe") and jobs.balance == funds - shop.CATALOG.loupe.price, "Finite purchases did not debit the wallet")
	shop.set_unlimited(true)
	await process_frame
	await process_frame
	var before: int = jobs.balance
	await click_page(bench, "Buy_screwdriver")
	expect(shop.owns("screwdriver") and "screwdriver" not in bench.tools.locked, "Website purchase did not unlock the tool")
	expect(jobs.balance == before and not shop.purchase("screwdriver"), "Unlimited/duplicate purchase changed the wallet")
	bench.computer.leave()
	await create_timer(0.4).timeout
	# The starter job can be fetched, opened and completed with the regular air jet alone.
	bench.delivery_window.arrival_delay = 0.01
	expect(jobs.accept(starter.id), "Starter cleaning job was refused")
	while bench.delivery_window.busy(): await process_frame
	await stand(bench, Vector3(27, -4.35, -7), bench.delivery_box.global_position)
	expect(bench.pick_up_parcel(), "Could not pick up starter parcel")
	await create_timer(0.4).timeout
	await stand(bench, Vector3(15, -4.35, 1), bench.parcel_spot)
	expect(bench.set_down_parcel(bench.parcel_spot), "The parcel did not fit on the compact bench")
	await create_timer(0.45).timeout
	jobs.unbox()
	while jobs.busy: await process_frame
	expect(bench.cleaning.part_progress("board") == 1.0 and bench.cleaning.part_progress("cooler-assembly") == 1.0, "Starter job dirtied inaccessible internals")
	await bench.tools.equip("air-blower")
	var fan: Node3D = bench.asset_contract.objects["fan-assembly"]
	var fan_bounds := fan.global_transform * Contract.bounds_in(fan)
	var camera: Camera3D = bench.camera_rig.camera
	# Sweep real visible surfaces using the regular blower radius and penetration.
	camera.global_position = fan_bounds.get_center() + Vector3(0, 6, 0.01)
	camera.look_at(fan_bounds.get_center(), Vector3.FORWARD)
	for pass_index in range(3):
		for x in range(25):
			for z in range(25):
				var point := Vector3(lerpf(fan_bounds.position.x, fan_bounds.end.x, x / 24.0), fan_bounds.end.y,
					lerpf(fan_bounds.position.z, fan_bounds.end.z, z / 24.0))
				var hit: Dictionary = bench.picker.surface_hit_at(camera.unproject_position(point), true)
				if hit.has("mesh"): bench.cleaning.blast(hit, Vector3.DOWN, 0.6)
		bench.cleaning.finish_if_ready(false)
		if bench.cleaning.celebrated: break
	expect(bench.cleaning.celebrated and bench.service.removed.is_empty(), "Starter blower could not finish the mounted fan: %.3f" % bench.cleaning.part_progress("fan-assembly"))
	await bench.tools.return_tool()
	var result: Dictionary = jobs.return_card()
	expect(result.get("paid", false) and result.get("amount", 0) == 25, "Finished starter clean did not pay")
	expect(jobs.offers.any(func(job): return job.get("exterior_clean", false)), "The board ran out of starter work")
	# Buying a complete repair kit still requires placing the testing station.
	for id in shop.catalog_ids("Tools"):
		if not shop.owns(id): expect(shop.purchase(id), "Could not buy " + id)
	expect(bench.tools.thermal_camera.is_visible_in_tree(), "Purchased thermal camera did not appear on its stand")
	expect(shop.purchase("test-station"), "Could not buy testing station")
	expect(not jobs.missing_equipment(paste_job).is_empty(), "A stored station unlocked jobs before placement")
	await stand(bench, Vector3(20, -4.35, 2), Vector3(26, 0, -10))
	expect(shop.begin_placement("test-station"), "Could not begin equipment placement")
	expect(not shop.preview_at(Vector3(18, -4.5, -5)) and not shop.finish_placement(), "Equipment could overlap the repair desk")
	expect(not shop.place_audio.playing, "A rejected placement played the build thud")
	expect(not shop.preview_at(Vector3(32, -4.5, -7)), "Equipment could block the delivery hatch")
	key(bench, KEY_R)
	expect(not shop.preview_at(Vector3(26.7, -4.5, -11.5)), "Station could face into an inaccessible window aisle")
	key(bench, KEY_R)
	expect(shop.preview_at(Vector3(25, -4.5, 6)), "The clear equipment spot was rejected: %s, yaw %s" % [shop.room_rect(shop.equipment["test-station"]), shop.equipment["test-station"].rotation.y])
	# Capture a paused preview so the camera can show the intended position clearly.
	shop.set_process(false)
	await stand(bench, Vector3(23, -4.35, -1), Vector3(25, 0, 6))
	bench.camera_rig.set_captured(false)
	var resume := InputEventMouseButton.new()
	resume.button_index = MOUSE_BUTTON_LEFT
	resume.pressed = true
	bench._unhandled_input(resume)
	expect(bench.camera_rig.captured and shop.placement_id == "test-station", "Focus recovery accidentally placed equipment")
	await capture("progression-equipment-placement")
	expect(shop.finish_placement() and bench.testing_station.available, "Placed station remained unusable")
	expect(shop.place_audio.playing and shop.place_audio.bus == &"BuildPlace", "Placing equipment made no build thud")
	shop.place_audio.stop()
	shop.set_process(true)
	var station: Node3D = shop.equipment["test-station"]
	var placed_pose := station.global_transform
	expect(shop.begin_placement("test-station"), "Owned equipment could not be moved")
	shop.preview_at(Vector3(25, -4.5, 5))
	key(bench, KEY_Q)
	expect(station.global_transform.is_equal_approx(placed_pose) and bench.testing_station.available, "Cancelling move lost the old position")
	expect(jobs.missing_equipment(paste_job).is_empty() and jobs.accept(paste_job.id), "Equipped shop did not unlock repair jobs")
	while bench.delivery_window.busy(): await process_frame
	# The shifted tray must still catch every removed screw.
	jobs.apply_faults([])
	bench.gpu.visible = true
	jobs.active().state = "bench"
	bench.service.debug_disassemble()
	var tray: MeshInstance3D = bench.get_node("RepairDesk/Tray")
	for id in bench.service.fan_screws + bench.service.cooler_screws:
		var screw: Node3D = bench.asset_contract.objects[id]
		expect(Contract.fits_table(screw.global_transform * Contract.bounds_in(screw), tray), "Moved tray lost screw " + id)
	bench.service.debug_reassemble()
	await create_timer(0.1).timeout
	expect(bench.testing_station.attach(), "Purchased rotated station did not accept a GPU")
	while bench.testing_station.moving: await process_frame
	expect(bench.testing_station.installed and bench.gpu.scale.is_equal_approx(Vector3.ONE * 0.25), "Testing changed card scale or failed to install")
	bench.test_monitor.toggle_power()
	await stand(bench, Vector3(25, -4.35, 0), bench.testing_station.board.global_position)
	await capture("progression-purchased-test-station")
	expect(not shop.begin_placement("test-station"), "Station could be moved with a card installed")
	bench.testing_station.detach()
	while bench.testing_station.moving: await process_frame
	expect(shop.purchase("queue-display") and shop.begin_placement("queue-display"), "Could not purchase/place the queue display")
	expect(not shop.preview_at(Vector3(25, -4.5, 2.3)), "Queue display could block the test station's working aisle")
	expect(shop.preview_at(Vector3(14.5, -4.5, -14)) and shop.finish_placement(), "Queue display did not fit its floor spot")
	# Shop expansion: the back wall, left of the delivery window, moves out one strip per slot.
	var annex_spot := Vector3(20, -4.5, -22)
	expect(shop.begin_placement("queue-display") and not shop.preview_at(annex_spot), "Equipment fit beyond the starter back wall")
	shop.cancel_placement()
	var back_wall: Node3D = bench.get_node("ShopInterior/StarterShell/StarterBackWall")
	var wall_z := back_wall.global_position.z
	expect(shop.purchase("shop-expansion") and shop.expansions == 1 and not shop.owns("shop-expansion"), "First expansion slot could not be bought")
	expect(shop.place_audio.playing and shop.place_audio.pitch_scale < 0.9, "The expansion was built without a heavier build thud")
	expect(is_equal_approx(back_wall.global_position.z, wall_z - 10.0), "Expansion did not move the back wall")
	await physics_frame
	await physics_frame
	expect(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(18, 2, -12), Vector3(18, 2, -25), 1)).is_empty(), "The old back wall still blocked the expansion")
	for line in [[Vector3(18, 2, -20), Vector3(18, 2, -30)], [Vector3(24, 0, -22), Vector3(24, -6, -22)],
			[Vector3(20, 2, -22), Vector3(8, 2, -22)], [Vector3(20, 2, -22), Vector3(36, 2, -22)]]:
		expect(not space.intersect_ray(PhysicsRayQueryParameters3D.create(line[0], line[1], 1)).is_empty(), "The expansion lost a wall or floor collision")
	expect(shop.begin_placement("queue-display") and shop.preview_at(annex_spot) and shop.finish_placement(), "Equipment did not fit in the expansion")
	await stand(bench, Vector3(16, -4.35, -6), Vector3(24, 2.5, -26))
	await capture("progression-shop-expansion")
	expect(shop.purchase("shop-expansion") and shop.owns("shop-expansion"), "Second expansion slot could not be bought")
	expect(not shop.purchase("shop-expansion") and shop.expansions == 2, "More than the available expansion slots were built")
	expect(shop.begin_placement("queue-display") and shop.preview_at(Vector3(20, -4.5, -32)) and not shop.preview_at(Vector3(20, -4.5, -38)), "The second slot did not extend the floor by one strip")
	shop.cancel_placement()
	await stand(bench, Vector3(19, -4.35, 6.5), Vector3(21, 0, -5))
	await capture("progression-equipped-standard-light")
	var standard: float = bench.day_cycle.environment.ambient_light_energy
	expect(shop.purchase("lighting") and shop.purchase("refurbishment"), "Room upgrades could not be bought")
	expect(bench.day_cycle.environment.ambient_light_energy > standard * 1.1, "Lighting purchase did not brighten the shop")
	await capture("progression-upgraded-room")
	await stand(bench, Vector3(17, -4.35, 4), bench.computer.screen.global_position)
	bench.computer.use()
	await create_timer(0.45).timeout
	bench.computer.shop_section = "Equipment"
	bench.computer.show_tab("shop")
	await process_frame
	await process_frame
	await capture("progression-supply-equipment")
	bench.computer.shop_section = "Workshop"
	bench.computer.show_tab("shop")
	await process_frame
	await process_frame
	expect(bench.computer.viewport.find_child("Place_shop-expansion", true, false) == null and bench.computer.viewport.find_child("Owned_shop-expansion", true, false) != null, "Fully built expansion still offered a purchase")
	await capture("progression-supply-workshop")
	bench.computer.leave()
	bench.queue_free()
	for frame in range(10): await process_frame
	print("PASS: starter ownership, real website purchase, finite/unlimited wallet, finishable blower job, locks, equipment placement/cancel, rotated test station, tray, shop expansion and room upgrades" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
