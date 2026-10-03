extends SceneTree
## The right-wall window and mountain view, the day/night cycle from the shop clock, parcels
## arriving through the delivery hatch and carried to the repair desk, and ending the day
## through the front door. `-- --capture` writes the views to build/.
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
func stand(bench: Node3D, at: Vector3, look_at: Vector3) -> void:
	var player = bench.camera_rig
	player.body.global_position = at
	player.update_camera()
	player.camera.look_at(look_at)
	player.look_pitch = player.camera.rotation.x
	player.look_yaw = player.camera.rotation.y
	player.update_camera()
	await physics_frame
	await process_frame
func key(bench: Node3D, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	bench._unhandled_input(event)
func click_at(bench: Node3D, at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		bench._unhandled_input(event)
		await process_frame
func centre() -> Vector2:
	return root.get_visible_rect().size * 0.5
## Sets the shop clock and lets the day cycle and renderer catch up.
func at_time(bench: Node3D, hours: float) -> void:
	bench.jobs.shop_minutes = floorf(bench.jobs.shop_minutes / 1440.0) * 1440.0 + hours * 60.0
	bench.day_cycle.update()
	for frame in range(3): await process_frame

## A folded radial strip renders dark seams at intersections, even with valid mesh arrays.
## Check real generated triangles and the full dome bounds, including the hidden back slopes.
func check_mountain_geometry(scenery: Node3D) -> void:
	for name in ["FrontMountains", "BackMountains"]:
		var mountain: MeshInstance3D = scenery.get_node(name)
		var arrays := mountain.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var outside := 0
		var folded := 0
		for vertex in vertices:
			if vertex.distance_to(scenery.DOME_CENTRE) >= scenery.DOME_RADIUS: outside += 1
		for index in range(0, indices.size(), 3):
			var a := vertices[indices[index]]
			var b := vertices[indices[index + 1]]
			var c := vertices[indices[index + 2]]
			if (b - a).cross(c - a).y <= 0.0: folded += 1
		expect(outside == 0, "%s had %d vertices outside the sky dome" % [name, outside])
		expect(folded == 0, "%s had %d folded or degenerate terrain triangles" % [name, folded])

## Plants must sit on the yard or actual terrain, and their crowns must fit inside the sky.
func check_vegetation_geometry(scenery: Node3D) -> void:
	var plants: Node3D = scenery.vegetation
	expect(plants.tree_roots.size() > 0 and plants.shrub_roots.size() > 0 and plants.ledge_roots.size() > 0,
		"The outside has no yard trees, shrubs or mountain plants")
	for root_position in plants.tree_roots + plants.shrub_roots:
		expect(is_equal_approx(root_position.y, scenery.YARD_TOP), "A yard plant was not grounded")
		expect(root_position.z < -13.0 or root_position.z > -1.0, "A yard plant blocks the central path")
	var terrain_points := {}
	for name in ["FrontMountains", "BackMountains"]:
		var arrays: Array = scenery.get_node(name).mesh.surface_get_arrays(0)
		for point in arrays[Mesh.ARRAY_VERTEX]: terrain_points[point] = true
	for root_position in plants.ledge_roots:
		expect(terrain_points.has(root_position), "A mountain plant root missed the terrain surface")
	for name in ["YardPlants", "CliffPlants"]:
		var mesh: MeshInstance3D = plants.get_node(name)
		var arrays := mesh.mesh.surface_get_arrays(0)
		var outside := 0
		for point in arrays[Mesh.ARRAY_VERTEX]:
			# Includes space for the maximum shader wind displacement.
			if point.distance_to(scenery.DOME_CENTRE) + 0.2 >= scenery.DOME_RADIUS: outside += 1
		expect(outside == 0, "%s had %d vertices outside the sky dome" % [name, outside])

func run() -> void:
	var Jobs = preload("res://scripts/repair_jobs.gd")
	var DayCycle = preload("res://scripts/day_cycle.gd")
	var Room = preload("res://scripts/shop_interior.gd")
	# The sun rises in the east (-X), crosses the south and sets in the west, out of the window.
	expect(DayCycle.sun_direction(6.0).x < -0.9 and absf(DayCycle.sun_direction(6.0).y) < 0.05, "Sunrise was not on the eastern horizon")
	expect(DayCycle.sun_direction(12.75).y > 0.8, "The sun was not high at midday")
	expect(DayCycle.sun_direction(19.5).x > 0.9 and absf(DayCycle.sun_direction(19.5).y) < 0.05, "Sunset was not on the western horizon")
	expect(DayCycle.sun_direction(1.0).y < -0.5, "The sun was up at night")

	var bench = load("res://scenes/workbench.tscn").instantiate()
	bench.job_flow = true
	root.add_child(bench)
	await process_frame
	var jobs: Node = bench.jobs
	var day: Node = bench.day_cycle
	var box: Node3D = bench.delivery_box
	var hatch: Node3D = bench.delivery_window
	day.fade_time = 0.25
	day.dark_time = 0.3
	expect(day != null and hatch != null and bench.scenery != null, "First-person play had no day cycle, delivery hatch or scenery")
	check_mountain_geometry(bench.scenery)
	check_vegetation_geometry(bench.scenery)
	expect(is_equal_approx(Jobs.SHOP_MINUTES_PER_SECOND * 60.0 * 24.0, Jobs.CLOSING_MINUTE - Jobs.OPENING_MINUTE),
		"The 09:00-21:00 day did not last 24 real minutes")

	# The window: the solid wall is replaced around an opening, and the room still holds you in.
	var shell: Node3D = bench.get_node("ShopInterior")
	expect(not shell.find_child("right-plaster-wall", true, false).visible, "The solid right wall still covers the window")
	for piece in ["WallBelowWindow", "WallAboveWindow", "WallBackOfWindow", "WallFrontOfWindow", "WindowGlass", "HatchCounter", "Transom"]:
		expect(shell.find_child(piece, true, false) != null, "The window is missing " + piece)
	await stand(bench, Vector3(29.0, -4.43, -7.0), Vector3(40.0, 3.0, -7.0))
	bench.camera_rig.movement_override = Vector2(0, -1)
	for step in range(40): await physics_frame
	bench.camera_rig.movement_override = Vector2.ZERO
	expect(bench.camera_rig.body.global_position.x < Room.WALL_X.x - 0.5, "Walked out through the window (x %.2f)" % bench.camera_rig.body.global_position.x)

	# 09:00: the morning sun is behind the shop; the room keeps its authored light.
	await at_time(bench, 9.0)
	var environment: Environment = bench.get_node("Environment").environment
	expect(day.state.daylight > 0.99 and is_equal_approx(environment.ambient_light_energy, 0.65) and is_equal_approx(bench.get_node("FillLight").light_energy, 0.5),
		"The morning room light changed from the authored values")
	expect(day.state.sun_beam == 0.0, "Morning sun shone in through the west window")
	expect(is_equal_approx(bench.get_node("KeyLight").light_energy, 1.8), "The workshop key light changed")
	await stand(bench, Vector3(10.0, -4.43, -7.0), Vector3(Room.WALL_X.x, 4.6, -7.0))
	await capture("outside-morning")
	await stand(bench, Vector3(27.0, -4.43, -7.0), Vector3(Room.WALL_X.x + 20.0, 1.0, -7.0))
	await capture("outside-close")
	# Afternoon: the low western sun reaches in through the window.
	await at_time(bench, 17.5)
	expect(day.state.sun_beam > 1.0 and day.state.sun_dir.x > 0.5, "No afternoon sunbeam through the window")
	await stand(bench, Vector3(26.0, -4.43, 10.0), Vector3(9.0, -4.5, -12.0))
	await capture("outside-sunbeam")
	await at_time(bench, 18.8)
	await stand(bench, Vector3(10.0, -4.43, -7.0), Vector3(Room.WALL_X.x, 4.6, -7.0))
	await capture("outside-sunset")
	# Night: the sky darkens, stars come out and the room dims; the workshop lamps stay on.
	await at_time(bench, 22.5)
	expect(day.state.night > 0.9 and day.state.daylight < 0.01 and day.state.sun_beam == 0.0, "It was not night at 22:30")
	expect(environment.ambient_light_energy < 0.45 and bench.get_node("FillLight").light_energy < 0.2, "The room did not dim at night")
	expect(bench.get_node("KeyLight").light_energy > 1.3 and bench.get_node("KeyLight").light_energy < 1.8, "The workshop lamps went out or did not dim at night")
	await capture("outside-night")
	await at_time(bench, 9.0)
	var fresh = load("res://scenes/workbench.tscn").instantiate()
	expect(is_equal_approx(fresh.get_node("Environment").environment.ambient_light_energy, 0.65), "A later workbench inherited this one's room light")
	fresh.free()

	# Closing time is announced once, as the clock passes 21:00.
	bench.jobs.shop_minutes = Jobs.CLOSING_MINUTE - 0.02
	day.update()
	for frame in range(10): await process_frame
	expect("closing time" in bench.hud.status_label.text, "Closing time was not announced")
	# Opening tomorrow: from the evening, and from after midnight.
	jobs.shop_minutes = 22 * 60.0
	jobs.start_next_day()
	expect(is_equal_approx(jobs.shop_minutes, 1440.0 + Jobs.OPENING_MINUTE) and jobs.day() == 2, "The evening did not roll to 09:00 on day 2")
	jobs.shop_minutes = 1440.0 + 30.0
	jobs.start_next_day()
	expect(is_equal_approx(jobs.shop_minutes, 1440.0 + Jobs.OPENING_MINUTE), "After midnight the shop did not open that morning")
	jobs.shop_minutes = Jobs.OPENING_MINUTE + 60.0

	# Accepting a job sends the parcel to the hatch: nothing on the desk, nothing to open yet.
	var offer: Dictionary = jobs.offers[0]
	var accepted_at := Time.get_ticks_msec()
	expect(jobs.accept(offer.id), "The job could not be accepted")
	expect(box.location == "outside" and not box.visible and hatch.state == "waiting", "The parcel did not wait outside the hatch")
	jobs.unbox()
	expect(not jobs.busy and jobs.active().state == "boxed", "A parcel still outside could be unboxed")
	expect("on its way" in bench.hud.status_label.text or "delivery hatch" in bench.hud.status_label.text, "The status did not point at the hatch")
	await stand(bench, Vector3(26.0, -4.43, -7.0), Vector3(Room.WALL_X.x, 1.0, -7.0))
	while hatch.state == "waiting": await process_frame
	var waited := (Time.get_ticks_msec() - accepted_at) / 1000.0
	expect(waited > 2.0 and waited < 3.2, "The shutter opened after %.2f s, not 2-3 s" % waited)
	expect(hatch.audio.playing and hatch.audio.bus == &"Shutter", "The shutter made no sound on its channel")
	while hatch.state == "opening": await process_frame
	await create_timer(0.2).timeout
	await capture("outside-hatch-open")
	while hatch.busy(): await process_frame
	expect(box.location == "sill" and box.visible and box.get_meta("action") == "parcel", "The parcel did not land on the hatch counter")
	expect(box.global_transform.origin.distance_to(hatch.sill_transform().origin) < 0.01, "The parcel was not on the counter")
	expect(is_zero_approx(hatch.opening) and hatch.slats.all(func(slat): return slat.visible), "The shutter did not close again")
	await capture("outside-parcel-on-sill")

	# Pick it up from the counter, put it back with Q, pick it up again.
	await stand(bench, Vector3(28.0, -4.43, -7.0), box.global_position + Vector3(0, 0.3, 0))
	expect(bench.interaction_hit(centre()).get("action") == "parcel", "The parcel on the counter was not the aimed target")
	await create_timer(0.15).timeout
	expect("pick up the parcel" in bench.hud.interaction_hint.text, "No pick-up prompt on the parcel")
	await click_at(bench, centre())
	expect(box.location == "held" and box.get_parent() == bench.camera_rig.camera, "Clicking the parcel did not pick it up")
	await create_timer(0.4).timeout
	await capture("outside-parcel-carried")
	key(bench, KEY_E)
	expect(box.location == "held", "E away from the desk dropped the parcel")
	key(bench, KEY_Q)
	await create_timer(0.45).timeout
	expect(box.location == "sill" and box.get_parent() == bench, "Q did not put the parcel back on the hatch")
	expect(box.global_transform.origin.distance_to(hatch.sill_transform().origin) < 0.01, "Q left the parcel off the counter")
	expect(box.scale.is_equal_approx(Vector3.ONE), "The parcel kept its carried size on the counter")
	# Re-aim: a rendered run's real mouse may have turned the view.
	await stand(bench, Vector3(28.0, -4.43, -7.0), box.global_position + Vector3(0, 0.3, 0))
	await click_at(bench, centre())
	await create_timer(0.4).timeout
	expect(bench.carrying_parcel(), "The parcel could not be picked up again")
	# Hands full: no tool bag, no computer.
	key(bench, KEY_T)
	expect(not bench.tool_menu_open, "The tool bag opened while carrying the parcel")

	# Carry it to the repair desk and set it down on a clear spot by its authored place.
	expect(not bench.parcel_placement(bench.gpu.global_position).allowed, "The parcel could be set down in the card holder")
	await stand(bench, Vector3(-0.3, -4.43, 9.0), bench.parcel_spot)
	await create_timer(0.15).timeout
	expect(bench.interaction_hit(centre()).get("action") == "desk", "The desk was not the aimed target")
	expect(bench.placement_marker.visible and bench.placement_material.albedo_color == Color("#71e6b0"), "No green placement marker for the parcel")
	await capture("outside-parcel-placing")
	await stand(bench, Vector3(-0.3, -4.43, 9.0), bench.parcel_spot)
	await click_at(bench, centre())
	await create_timer(0.5).timeout
	expect(box.location == "desk" and box.get_meta("action") == "delivery_box" and box.get_parent() == bench, "The parcel was not set down on the desk")
	expect(Vector2(box.global_position.x, box.global_position.z).distance_to(Vector2(bench.parcel_spot.x, bench.parcel_spot.z)) < 0.6
		and is_equal_approx(box.global_position.y, bench.parcel_spot.y), "The parcel did not land where it was aimed")
	expect(box.transform.is_equal_approx(box.rest), "The box's rest did not follow it to the desk")
	await stand(bench, Vector3(-0.3, -4.43, 9.0), box.global_position + Vector3(0, 0.4, 0))
	expect(bench.interaction_hit(centre()).get("action") == "delivery_box", "The parcel on the desk was not openable")
	await click_at(bench, centre())
	for step in range(80):
		await create_timer(0.05).timeout
		if not jobs.busy: break
	expect(bench.gpu.visible and jobs.active().state == "bench" and box.parked, "The carried parcel could not be unboxed")

	# The front door ends the day: refused with a part in hand, then fade to 09:00 tomorrow.
	var door: Node3D = shell.find_child("EntranceDoor", true, false)
	await stand(bench, Vector3(door.global_position.x, -4.43, door.global_position.z - 8.0), door.global_position)
	expect(bench.interaction_hit(centre()).get("action") == "exit_door", "The front door was not the aimed target")
	await create_timer(0.15).timeout
	expect("end the day" in bench.hud.interaction_hint.text, "No prompt on the exit door")
	bench.inspection.held = true
	bench.end_day()
	expect(not day.busy and "Set the part down" in bench.hud.status_label.text, "Left for the night with a card in hand")
	bench.inspection.held = false
	jobs.shop_minutes = 20 * 60.0 + 15.0
	var before_day: int = jobs.day()
	await stand(bench, Vector3(door.global_position.x, -4.43, door.global_position.z - 8.0), door.global_position)
	await click_at(bench, centre())
	expect(day.busy and not bench.ready_for_action(), "Clicking the door did not start the end of the day")
	await create_timer(0.35).timeout
	await capture("outside-day-end")
	while day.busy: await process_frame
	# The clock keeps running through the fade-in.
	var opened_at: float = fmod(jobs.shop_minutes, 1440.0) - Jobs.OPENING_MINUTE
	expect(jobs.day() == before_day + 1 and opened_at >= 0.0 and opened_at < 2.0, "The next day did not open at 09:00")
	expect(bench.camera_rig.body.global_position.distance_to(bench.camera_rig.SPAWN) < 0.5, "The player did not start the day by the bench")
	expect("Day %d" % jobs.day() in bench.hud.status_label.text, "The new day was not announced")
	expect(bench.gpu.visible and jobs.active().state == "bench", "The card on the bench did not stay overnight")
	expect(not day.overlay.visible and bench.ready_for_action(), "The day transition did not finish")
	bench.queue_free()
	for frame in range(12): await process_frame
	print("PASS: window and wall collision, time-of-day sky and room light, closing notice, next-day rollover, hatch delivery in 2-3 s, carrying and placing the parcel, unboxing and leaving through the door" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
