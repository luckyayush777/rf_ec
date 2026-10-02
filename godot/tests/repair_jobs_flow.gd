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
## Stands the player at a floor spot and looks at a world point.
func stand(bench: Node3D, at: Vector3, look_at: Vector3) -> void:
	var player = bench.camera_rig
	player.body.global_position = at
	player.update_camera()
	player.camera.look_at(look_at)
	player.look_pitch = player.camera.rotation.x
	player.look_yaw = player.camera.rotation.y
	player.update_camera()
	await physics_frame
func key(bench: Node3D, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	bench._unhandled_input(event)
## A real click at a viewport position, routed the way play routes it.
func click_at(bench: Node3D, at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		bench._unhandled_input(event)
		await process_frame
## Clicks a portal control on the in-world screen through the camera.
func click_page(bench: Node3D, control: Control) -> void:
	var computer: Node3D = bench.computer
	var middle := control.get_global_rect().get_center()
	await click_at(bench, bench.camera_rig.camera.unproject_position(computer.world_point(middle)))
## Read fresh each time: a capture run resizes the window after startup.
func centre() -> Vector2:
	return root.get_visible_rect().size * 0.5
func page_control(bench: Node3D, control_name: String) -> Control:
	return bench.computer.viewport.find_child(control_name, true, false)
func settle(bench: Node3D) -> void:
	for step in range(80):
		await create_timer(0.05).timeout
		if not bench.jobs.busy and not bench.inspection.moving: return
func run() -> void:
	# Fault counts: geometric odds with 3 of 3 faults at exactly 10%.
	var Jobs = preload("res://scripts/repair_jobs.gd")
	var odds: Array[float] = Jobs.fault_odds(3)
	expect(absf(odds[2] - 0.1) < 0.0005 and absf(odds[0] + odds[1] + odds[2] - 1.0) < 0.0001, "Three-fault odds were %s" % [odds])
	expect(odds[0] > odds[1] and odds[1] > odds[2] and odds[0] + odds[1] > 0.8999,"One or two faults were not the common case: %s" % [odds])
	var four: Array[float] = Jobs.fault_odds(4)
	expect(four[3] < four[2] and four[2] < odds[2], "Adding a fault type did not make many-fault cards rarer: %s" % [four])
	var roller = Jobs.new()
	roller.rng.seed = 2610
	var counts := [0, 0, 0, 0]
	var kinds := {}
	for index in range(20000):
		var faults: Array[String] = roller.roll_faults()
		counts[faults.size()] += 1
		for fault in faults: kinds[fault] = kinds.get(fault, 0) + 1
	expect(counts[0] == 0 and absf(counts[3] / 20000.0 - 0.1) < 0.01, "Rolled fault counts were %s" % [counts])
	expect(counts[1] > counts[2] and counts[2] > counts[3], "Rolled fault counts did not fall with k: %s" % [counts])
	expect(kinds.size() == 3 and kinds.values().max() < kinds.values().min() * 1.06, "Fault kinds were not uniform: %s" % [kinds])
	roller.free()

	var bench = load("res://scenes/workbench.tscn").instantiate()
	bench.job_flow = true
	root.add_child(bench)
	await process_frame
	var jobs: Node = bench.jobs
	jobs.rng.seed = 77
	expect(not bench.gpu.visible and jobs.queue.is_empty() and jobs.offers.size() == jobs.OFFER_COUNT, "Product play did not open on an empty bench with offers")
	expect(jobs.balance == jobs.STARTING_BALANCE, "Starting balance was %d" % jobs.balance)
	expect(bench.get_node("ThermalCameraBox").visible and not bench.tools.thermal_camera.visible and "thermal-camera" in bench.tools.locked,
		"Thermal camera was not boxed")
	await bench.tools.equip("thermal-camera")
	expect(bench.tools.equipped_tool == "", "A boxed thermal camera could be equipped")
	expect(not bench.testing_station.attach(), "An empty bench put a card on the test board")
	bench.inspection.lift()
	expect(not bench.inspection.held, "An empty bench let the hidden card be picked up")
	expect(preload("res://scripts/repair_status.gd").rows(bench).size() == 1, "The debug status listed a card that is not on the bench")
	await capture("jobs-empty-bench")

	# Walk up to the computer and use it with a real click on its screen.
	var computer: Node3D = bench.computer
	await stand(bench, Vector3(computer.global_position.x - 1.2, -4.43, computer.global_position.z - 5.5), computer.global_position + Vector3(-0.4, 5.2, 0))
	await capture("jobs-retro-pc")
	await stand(bench, Vector3(computer.global_position.x, -4.43, computer.global_position.z - 3.6), computer.screen.global_position)
	expect(bench.interaction_hit(centre()).get("action") == "computer", "The computer screen was not the aimed target")
	bench.camera_rig.set_captured(true)
	await click_at(bench, centre())
	expect(computer.in_use and not bench.camera_rig.captured, "Clicking the screen did not sit down at the computer")
	await create_timer(0.45).timeout
	# Sitting down types a burst of recorded keys; the click that sat down was not a page click.
	expect(computer.keystrokes == computer.LOGIN_KEYS, "Sitting down did not type a burst of keys (%d)" % computer.keystrokes)
	for player in [computer.keys_audio, computer.mouse_down_audio, computer.mouse_up_audio]:
		expect(player.stream != null and player.bus == &"PcInput", "%s has no sound or is not on the PC channel" % player.name)
	var clicks_before: int = computer.mouse_clicks
	expect(is_equal_approx(bench.camera_rig.anchor_weight, 1.0), "The camera did not settle on the screen")
	expect(bench.camera_rig.camera.global_transform.origin.distance_to(computer.screen.global_position) < 4.0, "The camera was not in front of the screen")
	bench.camera_rig.movement_override = Vector2(0, -1)
	var parked: Vector3 = bench.camera_rig.body.global_position
	for step in range(10): await physics_frame
	bench.camera_rig.movement_override = Vector2.ZERO
	expect(bench.camera_rig.body.global_position.distance_to(parked) < 0.01, "The player walked away while using the computer")
	await capture("jobs-portal-board")

	# Accept the first offer through the page.
	var offer: Dictionary = jobs.offers[0]
	var accept := page_control(bench, "Accept%d" % offer.id)
	expect(accept != null and not accept.disabled, "The job board had no live Accept button")
	if accept != null: await click_page(bench, accept)
	await process_frame
	expect(jobs.queue.size() == 1 and jobs.active().id == offer.id and jobs.active().state == "boxed", "Clicking Accept did not take the job")
	expect(computer.mouse_clicks == clicks_before + 1, "Clicking on the page made no mouse click sound")
	expect(bench.delivery_box.visible and jobs.offers.size() == jobs.OFFER_COUNT, "The box did not arrive or the board was not refilled")
	expect(not jobs.accept(jobs.offers[0].id) and jobs.queue.size() == jobs.MAX_QUEUE, "A second job fit on a one-card bench")
	computer.tab = "board"
	computer.refresh()
	var full := page_control(bench, "Accept%d" % jobs.offers[0].id)
	expect(full != null and full.disabled and "FULL" in full.text.to_upper(), "The board did not show the bench as full")
	# The tube's glass bulge: the page-to-tube inverse round-trips, and F-keys switch pages.
	var Computer = preload("res://scripts/shop_computer.gd")
	for probe in [Vector2(0.5, 0.5), Vector2(0.1, 0.2), Vector2(0.93, 0.88), Vector2(0.02, 0.6)]:
		expect(Computer.tube_to_page(Computer.page_to_tube(probe)).distance_to(probe) < 0.0001, "Tube mapping did not round-trip at %s" % probe)
	var keys_before: int = computer.keystrokes
	key(bench, KEY_F3)
	await process_frame
	expect(computer.tab == "ledger" and computer.keystrokes == keys_before + 1, "F3 did not open the ledger page with a keystroke")
	computer.tab = "bench"
	computer.refresh()
	await process_frame
	await capture("jobs-portal-bench-boxed")
	expect(bench.queue_monitor.slots.get_child_count() == jobs.MAX_QUEUE, "The queue display did not show one slot")
	key(bench, KEY_ESCAPE)
	expect(not computer.in_use and bench.camera_rig.captured, "Esc did not step away from the computer")
	await create_timer(0.45).timeout
	expect(is_equal_approx(bench.camera_rig.anchor_weight, 0.0), "The camera did not return to the player")

	# One click opens the box; the card lands in the holder with its rolled faults.
	await stand(bench, Vector3(-0.3, -4.43, 9.0), bench.delivery_box.global_position + Vector3(0, 0.4, 0))
	await capture("jobs-delivery-box")
	expect(bench.interaction_hit(centre()).get("action") == "delivery_box", "The delivery box was not the aimed target")
	await click_at(bench, centre())
	expect(jobs.busy, "Clicking the box did not start unboxing")
	await create_timer(0.5).timeout
	await capture("jobs-box-open")
	await settle(bench)
	var job: Dictionary = jobs.active()
	expect(bench.gpu.visible and job.state == "bench", "The card was not unboxed")
	await create_timer(0.4).timeout
	expect(not bench.delivery_box.visible, "The empty box stayed on the desk")
	expect(bench.gpu.transform.is_equal_approx(bench.inspection.home), "The unboxed card did not land in its holder")
	expect(bench.cleaning.celebrated == ("dust" not in job.faults), "Dust did not match the rolled faults %s" % [job.faults])
	expect(bench.paste.dried == ("paste" in job.faults) and bench.paste.seated, "Paste did not match the rolled faults %s" % [job.faults])
	expect(bench.bearing.dry == ("bearing" in job.faults), "Bearing did not match the rolled faults %s" % [job.faults])
	expect(jobs.problems() == job.faults, "Problems %s did not match the rolled faults %s" % [jobs.problems(), job.faults])
	var status: Array[Dictionary] = preload("res://scripts/repair_status.gd").rows(bench)
	expect(status[0].label == "Job" and ", ".join(job.faults) in status[0].detail and status.size() == 7,"The debug status did not show the rolled faults")
	await capture("jobs-queue-monitor")

	# Returning needs the card assembled and set down; a held card is refused.
	await stand(bench, Vector3(-3.0, -4.43, 9.0), bench.gpu.global_position)
	bench.inspection.lift()
	await settle(bench)
	expect(jobs.return_card().is_empty() and jobs.last_refusal != "", "A card in hand was returned")
	bench.inspection.put_down()
	await settle(bench)

	# Fix everything (the debug fixes stand in for the service flows tested elsewhere), then return it from the page.
	bench.debug_clean_gpu()
	if bench.paste.dried: bench.paste.debug_repaste()
	if bench.bearing.dry: bench.bearing.debug_oil()
	expect(jobs.problems().is_empty(), "Debug fixes left problems: %s" % [jobs.problems()])
	await stand(bench, Vector3(computer.global_position.x, -4.43, computer.global_position.z - 3.6), computer.screen.global_position)
	await click_at(bench, centre())
	await create_timer(0.45).timeout
	computer.tab = "bench"
	computer.refresh()
	await process_frame
	await process_frame
	var send := page_control(bench, "ReturnCard")
	expect(send != null and not send.disabled, "The bench page had no live return button")
	var before: int = jobs.balance
	if send != null: await click_page(bench, send)
	await process_frame
	expect(jobs.queue.is_empty() and not bench.gpu.visible, "Returning did not send the card away")
	expect(jobs.last_result.get("paid", false) and jobs.balance == before + job.pay, "A fixed card did not pay %d (balance %d -> %d)" % [job.pay, before, jobs.balance])
	expect(jobs.ledger.size() == 1, "The ledger did not record the job")
	await capture("jobs-portal-paid")
	key(bench, KEY_ESCAPE)
	await create_timer(0.45).timeout

	# An unfixed card goes back without payment, and says what is still wrong.
	expect(jobs.accept(jobs.offers[1].id), "A second job could not be taken after returning the first")
	await jobs.unbox()
	await settle(bench)
	var second: Dictionary = jobs.active()
	before = jobs.balance
	var result: Dictionary = jobs.return_card()
	expect(not result.is_empty() and not result.paid and jobs.balance == before, "An unfixed card was paid")
	expect(result.left == second.faults and result.feedback != "", "The customer did not report the remaining faults")
	bench.queue_free()
	await process_frame

	# Fixtures keep the original three-fault card as a walk-in job, with the thermal camera out.
	var fixture = load("res://scenes/workbench.tscn").instantiate()
	root.add_child(fixture)
	await process_frame
	var walk_in: Dictionary = fixture.jobs.active()
	expect(fixture.gpu.visible and walk_in.get("state", "") == "bench" and walk_in.faults == ["dust", "paste", "bearing"],
		"The fixture bench lost its three-fault walk-in card")
	expect(fixture.jobs.problems() == walk_in.faults, "The walk-in card's problems were %s" % [fixture.jobs.problems()])
	expect(fixture.tools.locked.is_empty() and not fixture.get_node("ThermalCameraBox").visible, "Fixtures boxed the thermal camera")
	fixture.queue_free()
	await process_frame
	print("PASS: fault-count odds, portal job accept/return by clicks, one-card queue, delivery box unboxing with rolled faults, payment and fixtures" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
