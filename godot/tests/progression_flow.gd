extends SceneTree
const Contract = preload("res://scripts/asset_contract.gd")
const StarterShop = preload("res://scripts/starter_shop.gd")
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
## Moves the build view's plan pointer over a floor point, as the mouse would.
func aim(bench: Node3D, at: Vector3) -> void:
	var event := InputEventMouseMotion.new()
	event.position = bench.camera_rig.camera.unproject_position(at)
	bench._unhandled_input(event)
	await process_frame
func plan_click(bench: Node3D, at: Vector3, button := MOUSE_BUTTON_LEFT) -> void:
	await aim(bench, at)
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = bench.camera_rig.camera.unproject_position(at)
	bench._unhandled_input(event)
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
	expect(bench.day_cycle.environment.ambient_light_energy > 0.4, "Starter room was not evenly lit")
	expect(bench.find_child("BenchTaskLight", true, false) == null, "A lamp pooled light over the starter bench")
	# Frame rate top right; the debug Lighting slider drives the scene light level.
	expect(bench.hud.fps_label != null and bench.hud.fps_label.is_visible_in_tree(), "There was no FPS counter")
	bench.hud.light_settings_path = "user://test_bench_lighting.cfg"
	bench.hud.light_slider.value = 1.2
	expect(is_equal_approx(bench.day_cycle.light_scale, 1.2), "The Lighting slider did not change the scene light")
	bench.hud.light_slider.value = bench.day_cycle.DEFAULT_LIGHT
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_bench_lighting.cfg"))
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
	# Every store item has a product shot; the tools' cards show theirs.
	expect(bench.computer.previews != null and bench.computer.previews.views.size() == shop.CATALOG.size(), "Not every catalog item had a preview")
	for id in shop.catalog_ids("Tools"):
		var shot: TextureRect = bench.computer.viewport.find_child("Preview_" + id, true, false)
		expect(shot != null and shot.texture != null, "Tool card had no preview: " + id)
	expect(bench.computer.previews.views["test-station"].find_children("*", "SubViewport", true, false).is_empty(), "Station preview copied a live screen viewport")
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
	# Build view: B lifts the camera straight over the plan, frees the cursor and hides the ceiling.
	var build: Node = bench.build_view
	key(bench, KEY_B)
	expect(build.active and not bench.camera_rig.captured and not bench.ready_for_action(), "B did not open build view")
	await create_timer(0.65).timeout
	expect(camera.global_basis.z.dot(Vector3.UP) > 0.99, "Build view did not look straight down")
	var ceiling: Node3D = bench.get_node("ShopInterior/StarterShell/StarterCeiling")
	expect(not ceiling.visible, "The ceiling covered the floor plan")
	var stored: Button = build.list.find_child("Place_test-station", true, false)
	expect(stored != null, "The stored station was not listed in build view")
	if stored != null: stored.pressed.emit()
	expect(shop.placement_id == "test-station", "Build view storage did not pick up the station")
	await plan_click(bench, Vector3(18, -4.5, -5))
	expect(not shop.placement_valid and shop.placement_id == "test-station", "Equipment could overlap the repair desk")
	expect(not shop.place_audio.playing, "A rejected placement played the build thud")
	await aim(bench, Vector3(32, -4.5, -7))
	expect(not shop.placement_valid, "Equipment could block the delivery hatch")
	key(bench, KEY_R)
	await aim(bench, Vector3(26.7, -4.5, -11.5))
	expect(not shop.placement_valid, "Station could face into an inaccessible window aisle")
	key(bench, KEY_R)
	await aim(bench, Vector3(25, -4.5, 6))
	expect(shop.placement_valid, "The clear equipment spot was rejected: %s, yaw %s" % [shop.room_rect(shop.equipment["test-station"]), shop.equipment["test-station"].rotation.y])
	await capture("progression-build-view-placement")
	await plan_click(bench, Vector3(25, -4.5, 6))
	expect(shop.placement_id == "" and bench.testing_station.available, "Placed station remained unusable")
	expect(shop.place_audio.playing and shop.place_audio.bus == &"BuildPlace", "Placing equipment made no build thud")
	shop.place_audio.stop()
	var station: Node3D = shop.equipment["test-station"]
	var placed_pose := station.global_transform
	# Clicking placed equipment picks it up; Esc puts it back where it was.
	var middle: Vector2 = shop.room_rect(station).get_center()
	await plan_click(bench, Vector3(middle.x, -4.5, middle.y))
	expect(shop.placement_id == "test-station", "Owned equipment could not be moved")
	await aim(bench, Vector3(25, -4.5, 5))
	key(bench, KEY_ESCAPE)
	expect(station.global_transform.is_equal_approx(placed_pose) and bench.testing_station.available, "Cancelling move lost the old position")
	expect(build.active, "Cancelling a move left build view")
	# The starting repair desk and PC move like bought equipment; what sits on the desk rides along.
	var desk: Node3D = bench.get_node("RepairDesk")
	var desk_pose := desk.global_transform
	var desk_spot: Vector2 = shop.room_rect(desk).get_center()
	var card_offset: Vector3 = desk.global_transform.affine_inverse() * bench.gpu.global_position
	var stand_offset: Vector3 = desk.global_transform.affine_inverse() * bench.tools.thermal_stand.global_position
	expect(not shop.stash("repair-desk") and shop.placed["repair-desk"], "The repair desk could be stashed")
	await plan_click(bench, Vector3(desk_spot.x, -4.5, desk_spot.y))
	expect(shop.placement_id == "repair-desk", "Clicking the repair desk did not pick it up")
	await plan_click(bench, Vector3(desk_spot.x - 1.0, -4.5, desk_spot.y - 2.0))
	expect(shop.placement_id == "" and desk.global_position.is_equal_approx(desk_pose.origin + Vector3(-1, 0, -2)), "The repair desk did not move: %s" % desk.global_position)
	var card_home: Vector3 = (bench.gpu.get_parent() as Node3D).global_transform * bench.inspection.home.origin
	expect((desk.global_transform.affine_inverse() * bench.gpu.global_position).is_equal_approx(card_offset) and
		(desk.global_transform.affine_inverse() * card_home).is_equal_approx(card_offset) and
		(desk.global_transform.affine_inverse() * bench.tools.thermal_stand.global_position).is_equal_approx(stand_offset), "The card or thermal stand did not ride with the desk")
	# Turning the desk turns its riders; cancelling puts both back.
	await plan_click(bench, Vector3(desk_spot.x - 1.0, -4.5, desk_spot.y - 2.0))
	key(bench, KEY_R)
	await aim(bench, Vector3(desk_spot.x - 1.0, -4.5, desk_spot.y - 2.0))
	expect((desk.global_transform.affine_inverse() * bench.gpu.global_position).is_equal_approx(card_offset), "The card did not turn with the desk")
	key(bench, KEY_ESCAPE)
	await plan_click(bench, Vector3(desk_spot.x - 1.0, -4.5, desk_spot.y - 2.0))
	await plan_click(bench, Vector3(desk_spot.x, -4.5, desk_spot.y))
	expect(shop.placement_id == "" and desk.global_transform.is_equal_approx(desk_pose) and (desk.global_transform.affine_inverse() * bench.gpu.global_position).is_equal_approx(card_offset), "The repair desk did not return to its spot")
	var computer_pose: Transform3D = bench.computer.global_transform
	var computer_spot: Vector2 = shop.room_rect(bench.computer).get_center()
	await plan_click(bench, Vector3(computer_spot.x, -4.5, computer_spot.y))
	expect(shop.placement_id == "shop-computer", "Clicking the shop computer did not pick it up: hover %s, placing %s, rect %s" % [shop.placed_at(computer_spot), shop.placement_id, shop.room_rect(bench.computer)])
	await plan_click(bench, Vector3(computer_spot.x, -4.5, -13.0))
	expect(shop.placement_id == "" and is_equal_approx(bench.computer.global_position.z, computer_pose.origin.z - 13.0 - computer_spot.y), "The shop computer did not move: %s" % bench.computer.global_position)
	await plan_click(bench, Vector3(computer_spot.x, -4.5, -13.0))
	await plan_click(bench, Vector3(computer_spot.x, -4.5, computer_spot.y))
	expect(shop.placement_id == "" and bench.computer.global_transform.is_equal_approx(computer_pose), "The shop computer did not return to its spot")
	# The rest of the run works at the moved desk.
	await plan_click(bench, Vector3(desk_spot.x, -4.5, desk_spot.y))
	await plan_click(bench, Vector3(desk_spot.x - 1.0, -4.5, desk_spot.y - 2.0))
	expect(shop.placement_id == "" and desk.global_position.is_equal_approx(desk_pose.origin + Vector3(-1, 0, -2)), "The repair desk could not be moved again")
	key(bench, KEY_B)
	expect(not build.active and bench.camera_rig.captured, "B did not leave build view")
	await create_timer(0.65).timeout
	expect(ceiling.visible and bench.ready_for_action(), "Leaving build view did not restore the room")
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
	expect((desk.global_transform.affine_inverse() * bench.gpu.global_position).is_equal_approx(card_offset), "The tested card did not come back to the moved desk")
	expect(shop.purchase("queue-display") and shop.begin_placement("queue-display"), "Could not purchase/place the queue display")
	expect(not shop.preview_at(Vector3(25, -4.5, 2.3)), "Queue display could block the test station's working aisle")
	expect(shop.preview_at(Vector3(14.5, -4.5, -14)) and shop.finish_placement(), "Queue display did not fit its floor spot")
	# Shop expansion: in build view a square as wide as the starter room is long plops down flush
	# against the floor; the wall between is knocked through.
	expect(not shop.purchase("shop-expansion") and shop.expansions == 0, "An expansion was bought without being put down")
	var annex_spot := Vector3(-3, -4.5, -5)
	expect(shop.begin_placement("queue-display") and not shop.preview_at(annex_spot), "Equipment fit beyond the starter left wall")
	shop.cancel_placement()
	await stand(bench, Vector3(20, -4.35, 2), Vector3(14, 0, -5))
	expect(build.open("expansion") and build.mode == "expansion", "Build view did not offer an expansion")
	await create_timer(0.65).timeout
	var left_square := Rect2(-15.5, -16.5, 26, 26)
	await aim(bench, Vector3(-2, -4.5, -3))
	expect(build.square_valid and build.square.is_equal_approx(left_square), "The square did not snap flush to the left wall: %s" % build.square)
	await aim(bench, Vector3(25, -4.5, 22))
	expect(StarterShop.LOT.encloses(build.square), "A square was offered over the door or the window: %s" % build.square)
	await aim(bench, Vector3(-2, -4.5, -3))
	await capture("progression-build-view-expansion")
	await plan_click(bench, Vector3(-2, -4.5, -3))
	expect(shop.expansions == 1 and shop.expansion_squares[0].is_equal_approx(left_square), "Clicking did not build the square")
	expect(shop.place_audio.playing and shop.place_audio.pitch_scale < 0.9, "The expansion was built without a heavier build thud")
	expect(build.mode == "", "Build view kept offering squares after building one")
	await create_timer(0.6).timeout
	var plan: Node3D = bench.get_node("ShopInterior/StarterShell/Plan")
	expect(not plan.get_node("ExpansionCeiling").visible, "The new square's ceiling covered the plan")
	await physics_frame
	await physics_frame
	expect(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(18, 2, -5), Vector3(5, 2, -5), 1)).is_empty(), "The starter's left wall still blocked the expansion")
	for line in [[Vector3(-3, 2, -5), Vector3(-20, 2, -5)], [Vector3(-3, 2, -5), Vector3(-3, 2, -22)], [Vector3(-3, 2, 0), Vector3(-3, 2, 14)],
			[Vector3(-3, 0, -5), Vector3(-3, -6, -5)], [Vector3(18, 2, -12), Vector3(18, 2, -18)]]:
		expect(not space.intersect_ray(PhysicsRayQueryParameters3D.create(line[0], line[1], 1)).is_empty(), "The expansion lost a wall or floor collision: %s" % [line])
	expect(shop.begin_placement("queue-display") and shop.preview_at(annex_spot) and shop.finish_placement(), "Equipment did not fit in the expansion")
	expect(not shop.build_expansion(Rect2(0, -10, 26, 26)), "An expansion overlapping the floor was built")
	# Behind the starter room the square snaps to the window wall and opens onto both floors.
	build.set_mode("expansion")
	await aim(bench, Vector3(20, -4.5, -25))
	expect(build.square.is_equal_approx(Rect2(7, -42.5, 26, 26)) and build.square_valid, "The back square did not snap to the window wall: %s" % build.square)
	await plan_click(bench, Vector3(20, -4.5, -25))
	await create_timer(0.6).timeout
	build.set_mode("expansion")
	await plan_click(bench, Vector3(-28, -4.5, -3))
	await create_timer(0.6).timeout
	expect(shop.expansions == 3 and shop.owns("shop-expansion"), "Three squares could not be built: %s" % [shop.expansion_squares])
	build.set_mode("expansion")
	expect(build.mode == "" and not shop.build_expansion(Rect2(-41.5, -42.5, 26, 26)), "More than the available expansions were built")
	await physics_frame
	await physics_frame
	expect(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(18, 2, -12), Vector3(18, 2, -25), 1)).is_empty(), "The starter's back wall still blocked the back square")
	# Stashing returns placed equipment to storage, where build view can place it again.
	expect(shop.stash("queue-display") and not bench.queue_monitor.visible and "queue-display" in shop.stored_ids(), "Equipment could not be stashed")
	var again: Button = build.list.find_child("Place_queue-display", true, false)
	expect(again != null, "Stashed equipment was not listed in storage")
	if again != null: again.pressed.emit()
	await plan_click(bench, Vector3(20, -4.5, -30))
	expect(shop.placed.get("queue-display", false) and bench.queue_monitor.visible, "Stashed equipment could not be placed again")
	await capture("progression-build-view-plan")
	key(bench, KEY_B)
	await create_timer(0.65).timeout
	expect(ceiling.visible and bench.get_node("ShopInterior/StarterShell/Plan/ExpansionCeiling").visible, "Leaving build view left ceilings hidden")
	await stand(bench, Vector3(20, -4.35, -2), Vector3(0, 2.5, -12))
	await capture("progression-shop-expansion")
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
	print("PASS: starter ownership, real website purchase, finite/unlimited wallet, finishable blower job, locks, equipment placement/cancel, rotated test station, tray, build view placement/stash, catalog previews, square shop expansions and room upgrades" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
