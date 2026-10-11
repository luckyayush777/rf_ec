extends SceneTree
## The neighbourhood: households and zone unlocks, megacorp warranty glue (heat gun, then
## suction pen, in focus), the glue tools and map screen in the shop, the N map overlay and
## the board growing as zones open.
const Neighbourhood = preload("res://scripts/neighbourhood.gd")
var failures: Array[String] = []
var notices: Array[String] = []
func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func _initialize() -> void: call_deferred("run")
func capturing() -> bool:
	return "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
func capture(name: String) -> void:
	if not capturing(): return
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
func fetch_parcel(bench: Node3D) -> void:
	bench.delivery_window.arrival_delay = 0.1
	while bench.delivery_box.location != "sill": await process_frame
	bench.pick_up_parcel()
	await create_timer(0.35).timeout
	bench.set_down_parcel(bench.parcel_spot)
	await create_timer(0.45).timeout
func settle(bench: Node3D) -> void:
	for step in range(80):
		await create_timer(0.05).timeout
		if not bench.jobs.busy and not bench.inspection.moving: return
## Frames the close-up straight down onto one glued screw and returns its screen point.
func frame_seal(view: CanvasLayer, glue: Node, id: String) -> Vector2:
	var seal: Node3D = glue.seals[id].root
	view.center = glue.world_centre(id)
	view.direction = seal.global_basis.y.normalized()
	view.distance = glue.world_radius(id) * 9.0
	view.zoom = 1.0
	view.update_camera()
	return view.camera.unproject_position(glue.world_centre(id))
func work(view: CanvasLayer, at: Vector2, seconds: float) -> void:
	view.cleaning_pointer = at
	var step := 0.05
	var elapsed := 0.0
	while elapsed < seconds:
		view.glue_under_pointer(step)
		elapsed += step
func press(view: CanvasLayer, at: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	view.view_input(down)

func run() -> void:
	await households()
	await glue_service()
	await progression()
	print("PASS: households and zone unlocks, megacorp glue (heat gun then suction pen) blocking screws, glue tools and map screen in the shop, N map overlay, board growth" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)

func households() -> void:
	var area := Neighbourhood.new()
	var total := 0
	for zone in Neighbourhood.ZONES: total += zone.homes.size()
	expect(area.homes.size() == total and area.unlocked == 1, "The neighbourhood did not start with one zone open")
	# Territories tile the map: every household stands on its own zone's land, the shop on the
	# first zone's and the megacorp tower on its campus.
	for home in area.homes:
		expect(Neighbourhood.territory_at(home.at) == home.zone, "%s stands outside its zone's land" % home.id)
	expect(Neighbourhood.territory_at(Neighbourhood.SHOP_AT) == 0 and Neighbourhood.territory_at(Neighbourhood.MEGACORP_AT) == Neighbourhood.CAMPUS_TERRITORY,
		"The shop or the megacorp tower stood on the wrong land")
	var land := preload("res://scripts/neighbourhood_map.gd").geography_data()
	var turf: Array = land.turf_points
	expect(turf.size() == Neighbourhood.CAMPUS_TERRITORY + 1 and turf.all(func(points: PackedVector2Array): return points.size() >= 30),
		"A territory had no land on the map")
	expect(land.borders.has("0-1") and land.borders.has("0-2") and land.borders.has("1-3"), "Neighbouring territories shared no border: %s" % [land.borders.keys()])
	var start := area.reachable()
	expect(start.size() == Neighbourhood.ZONES[0].homes.size() and start.all(func(home: Dictionary): return home.state == "red" and home.zone == 0),
		"The first zone did not start all red")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var busy: Array = [start[0].id, start[1].id]
	for roll in range(50):
		var picked := area.pick(busy, rng)
		expect(not picked.is_empty() and picked.id not in busy and picked.zone == 0, "A customer came from a busy or unreachable home: %s" % [picked])
	expect(Neighbourhood.state_for(5) == "green" and Neighbourhood.state_for(4) == "green" and Neighbourhood.state_for(3) == "yellow" and
		Neighbourhood.state_for(2) == "red" and Neighbourhood.state_for(1) == "red", "Satisfaction did not map to green 4-5, yellow 3, red below")
	# Old Town opens at two green homes...
	expect(area.record(start[0].id, 4).is_empty() and area.tally().green == 1, "One green home opened a zone")
	var opened := area.record(start[1].id, 5)
	expect(opened.size() == 1 and opened[0] == "Old Town" and area.unlocked == 2 and area.reachable().size() == start.size() + Neighbourhood.ZONES[1].homes.size(),
		"Two green homes did not open Old Town: %s" % [opened])
	# ...or three happy (yellow or green) ones.
	var other := Neighbourhood.new()
	var homes := other.reachable()
	other.record(homes[0].id, 3)
	other.record(homes[1].id, 3)
	expect(other.unlocked == 1, "Two yellow homes opened a zone")
	var third := other.record(homes[2].id, 3)
	expect(third.size() == 1 and third[0] == "Old Town", "Three yellow homes did not open Old Town")
	var next := other.next_unlock()
	expect(next.name == "Hillside" and next.need_green == 5 and next.need_happy == 7 and next.happy == 3, "Next unlock read %s" % [next])
	# An unhappy repair leaves (or turns) a home red, and red homes can call again.
	other.record(homes[0].id, 2)
	expect(other.home(homes[0].id).state == "red" and not other.pick([], rng, false).is_empty(), "An unhappy home was not red or could not call again")
	# Megacorp glue: fan screws half the time at first, every screw on every card at three zones.
	var fan := ["fan-screw-1", "fan-screw-2"]
	var cooler := ["cooler-screw-1"]
	var glued := 0
	for roll in range(400):
		var screws := area.glue_roll(rng, fan, cooler)
		if not screws.is_empty():
			glued += 1
			expect(screws == fan, "An early megacorp card glued %s" % [screws])
	expect(absf(glued / 400.0 - 0.75) < 0.08, "With two zones open, %d of 400 megacorp cards were glued" % glued)
	area.unlocked = 3
	expect(area.glue_roll(rng, fan, cooler) == fan + cooler, "At three zones the megacorp did not glue every screw")

func glue_service() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	bench.get_node("CameraRig").legacy_test_mode = true
	root.add_child(bench)
	await process_frame
	bench.hud.audio_save_timer.stop()
	var glue: Node = bench.glue
	var service: Node = bench.service
	var view: CanvasLayer = bench.closeup
	glue.notice.connect(func(text: String): notices.append(text))
	expect(glue.seals.size() == 8 and glue.sealed.is_empty() and glue.seals.values().all(func(seal: Dictionary): return not seal.root.visible),
		"A fresh card showed glue")
	for id in glue.seals:
		expect(service.screw_seats[id].is_ancestor_of(glue.seals[id].root), "Glue on %s does not ride with its seat" % id)
	glue.set_sealed(service.fan_screws)
	expect(glue.sealed == service.fan_screws and glue.seals["fan-screw-1"].root.visible and not glue.seals["cooler-screw-1"].root.visible,
		"Sealing the fan screws did not show their glue")
	# The screwdriver cannot reach a glued screw.
	await bench.tools.equip("screwdriver")
	expect(not service.begin_screw("fan-screw-1") and service.active_screw == "" and service.screw_block.call("fan-screw-1").contains("warranty glue"),
		"A glued screw could be turned")
	await bench.tools.return_tool()
	# Heat gun from its stand, in focus on the card.
	expect(bench.tools.tool_location("heat-gun") == "stand" and bench.tools.stands["heat-gun"].is_ancestor_of(bench.tools.tool_node("heat-gun")),
		"The heat gun was not on its stand")
	expect(bench.tools.tool_location("suction-pen") == "toolbox" and bench.tools.toolbox.is_ancestor_of(bench.tools.tool_node("suction-pen")) and
		not bench.tools.stands.has("suction-pen"), "The suction pen was not in the tool roll")
	await bench.tools.equip("heat-gun")
	expect(bench.tools.equipped_tool == "heat-gun" and bench.tools.focus_tool(), "The heat gun could not be equipped as a focus tool")
	view.show_view("service", bench.gpu)
	await process_frame
	await process_frame
	var target: String = service.fan_screws[0]
	var neighbour: String = service.fan_screws[1]
	# The whole card as focus first frames it: the glue reads at a glance.
	await capture("glue-focus-card")
	var point := frame_seal(view, glue, target)
	await capture("glue-sealed")
	var hit: Dictionary = view.pick.surface_hit_at(point)
	expect(glue.seal_of(hit.get("mesh")) == target, "The focus pointer did not land on the glue over %s" % target)
	press(view, point)
	expect(glue.working and glue.work_kind == "heat", "Pressing with the heat gun did not start heating")
	for frame in range(20): glue._process(1.0 / 60.0)
	expect(glue.heat_audio.stream != null and glue.heat_audio.bus == &"HeatGun" and glue.motor > 0.2 and (glue.heat_audio.playing or glue.muted),
		"The heat gun motor did not wind up its recording")
	work(view, point, glue.HEAT_TIME * 0.4)
	expect(not glue.is_soft(target) and glue.seals[target].heat > 0.3, "Heat built up too fast or not at all")
	work(view, point, glue.HEAT_TIME * 0.8)
	expect(glue.is_soft(target), "Steady heat did not soften the glue")
	expect(service.fan_screws.all(func(id: String): return glue.is_soft(id)), "One heat gun pass did not soften every blob facing it")
	expect(notices.any(func(text: String): return "on 4 screws" in text), "Softening the facing side gave no single notice")
	expect((glue.seals[target].material as StandardMaterial3D).emission_energy_multiplier > 1.0, "Hot glue did not glow")
	await capture("glue-heated")
	glue.end()
	for frame in range(90): glue._process(1.0 / 60.0)
	expect(glue.motor < 0.01, "The heat gun motor did not coast down after the trigger")
	# Left alone, soft glue cools and hardens again after the soft time (60 s by default).
	expect(glue.soft_time == 60.0, "Glue did not default to staying soft for 60 s")
	glue._process(50.0)
	expect(glue.is_soft(target), "Glue hardened within 50 s")
	glue._process(15.0)
	expect(not glue.is_soft(target), "Glue never cooled back down")
	# The gun only reaches blobs facing it: from behind, nothing warms.
	var cold: float = glue.seals[target].heat
	glue.working = true
	glue.work_kind = "heat"
	glue.heat_from(glue.seals[target].root.global_basis.y, 1.0)
	glue.end()
	expect(is_equal_approx(glue.seals[target].heat, cold), "Heat from behind the card warmed the glue")
	press(view, point)
	work(view, point, glue.HEAT_TIME * 1.3)
	glue.end()
	expect(glue.is_soft(target), "Re-heating did not soften the glue")
	# Suction pen: hard glue refuses, soft glue goes.
	view.close()
	await bench.tools.return_tool()
	await bench.tools.equip("suction-pen")
	view.show_view("service", bench.gpu)
	await process_frame
	await process_frame
	var hard := frame_seal(view, glue, neighbour)
	if glue.is_soft(neighbour): glue.seals[neighbour].heat = 0.0
	press(view, hard)
	expect(glue.working and glue.work_kind == "suck", "Pressing with the suction pen did not start suction")
	work(view, hard, 1.0)
	expect(glue.seals[neighbour].amount == 1.0 and notices.any(func(text: String): return "rock hard" in text), "Hard glue was sucked off")
	glue.end()
	point = frame_seal(view, glue, target)
	press(view, point)
	work(view, point, glue.SUCK_TIME * 0.5)
	expect(glue.seals[target].amount > 0.2 and glue.seals[target].amount < 0.8, "Suction did not draw the soft glue down gradually")
	glue._process(1.0 / 60.0)
	expect(glue.suction_sound.stream != null and glue.suction_sound.bus == &"SuctionPen" and glue.suction_sound.target > 0.9,
		"Sucking glue did not drive the suction recording")
	await capture("glue-suction")
	work(view, point, glue.SUCK_TIME * 0.7)
	glue.end()
	expect(target not in glue.sealed and not glue.seals[target].root.visible and glue.sealed.size() == 3, "The sucked-off glue did not clear")
	await process_frame
	await process_frame
	expect(view.progress.value > 20.0, "The focus bar did not show the glue removed")
	# Clear the rest; then every screw turns again.
	for id in glue.sealed.duplicate():
		glue.seals[id].heat = 1.0
		point = frame_seal(view, glue, id)
		press(view, point)
		work(view, point, glue.SUCK_TIME * 1.2)
		glue.end()
	expect(glue.sealed.is_empty() and glue.progress() == 1.0 and notices.any(func(text: String): return "All the glue is off" in text),
		"Not all the glue came off")
	await capture("glue-cleared")
	view.close()
	await bench.tools.return_tool()
	expect(bench.tools.tool_location("suction-pen") == "toolbox" and bench.tools.toolbox.is_ancestor_of(bench.tools.tool_node("suction-pen")),
		"The suction pen did not go back to the tool roll")
	await bench.tools.equip("screwdriver")
	expect(service.begin_screw(target), "The screw stayed blocked after its glue came off")
	service.end_screw()
	await bench.tools.return_tool()
	# The debug shortcut glues every seated screw.
	expect(glue.debug_seal() == OS.is_debug_build() and (glue.sealed.size() == 8 or not OS.is_debug_build()), "Debug glue did not seal every screw")
	glue.set_sealed([])
	bench.queue_free()
	for frame in range(10): await process_frame

func progression() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	bench.progression_enabled = true
	root.add_child(bench)
	await process_frame
	bench.camera_rig.set_physics_process(false)
	bench.hud.audio_save_timer.stop()
	var jobs: Node = bench.jobs
	var shop: Node = bench.shop
	var area: Neighbourhood = jobs.neighbourhood
	expect(jobs.megacorp_glue and jobs.offers.size() == jobs.OFFER_COUNT, "Progression did not open with megacorp glue and three requests")
	for offer in jobs.offers:
		if offer.get("exterior_clean", false): expect(offer.glued.is_empty(), "An exterior cleaning job came glued")
		if not offer.glued.is_empty(): expect(offer.brand == Neighbourhood.MEGACORP, "A non-megacorp card came glued")
		if not jobs.is_tech(offer): expect(area.home(offer.home).zone == 0, "A customer called from outside the shop's zone")
	# The glue tools and the map screen are for sale; the heat gun's stand appears with it.
	expect("heat-gun" in bench.tools.locked and not bench.tools.stands["heat-gun"].is_visible_in_tree(), "The unbought heat gun stand was on the desk")
	expect("suction-pen" in bench.tools.locked and not bench.tools.tool_node("suction-pen").visible, "The unbought suction pen was in the tool roll")
	expect(bench.map_display != null and not bench.map_display.visible, "The unbought map screen was on the wall")
	var glued_job: Dictionary = jobs.make_job(["bearing"], "customer")
	glued_job.brand = Neighbourhood.MEGACORP
	glued_job.model = Neighbourhood.MEGACORP + " " + jobs.MODEL
	glued_job.glued = bench.service.fan_screws.duplicate()
	var missing: Array[String] = jobs.missing_equipment(glued_job)
	expect("Heat gun" in missing and "Suction pen" in missing, "A glued job did not need the glue tools: %s" % [missing])
	for id in ["heat-gun", "suction-pen", "map-display", "screwdriver", "ipa-wipe", "fan-oiler", "test-station", "thermal-camera"]:
		expect(shop.purchase(id), "Could not buy " + id)
	expect(bench.tools.stands["heat-gun"].is_visible_in_tree() and bench.tools.tool_node("heat-gun").is_visible_in_tree() and
		"suction-pen" not in bench.tools.locked, "Bought glue tools did not appear on the stand and in the roll")
	expect(bench.map_display.visible, "The bought map screen did not go up on the wall")
	var desk: MeshInstance3D = bench.get_node("RepairDesk/Tabletop")
	var stand_box: AABB = bench.tools.stands["heat-gun"].global_transform * preload("res://scripts/asset_contract.gd").bounds_in(bench.tools.stands["heat-gun"])
	expect(preload("res://scripts/asset_contract.gd").fits_table(stand_box, desk), "The heat gun stand overhung the starter desk")
	# The unrolled roll, suction pen in its last pocket, keeps clear of the heat gun's stand.
	await bench.tools.move_lid(true)
	var pen_box: AABB = bench.tools.tool_node("suction-pen").global_transform * preload("res://scripts/asset_contract.gd").bounds_in(bench.tools.tool_node("suction-pen"))
	expect(bench.tools.tool_node("suction-pen").is_visible_in_tree() and preload("res://scripts/asset_contract.gd").fits_table(pen_box, desk) and
		not pen_box.intersects(stand_box), "The suction pen's pocket was hidden, off the desk or under the heat gun stand")
	await stand(bench, Vector3(21.5, -4.35, -0.5), Vector3(22.6, -0.2, -5.4))
	bench.refresh_ui()
	await capture("neighbourhood-glue-stands")
	await bench.tools.move_lid(false)
	await bench.tools.equip("heat-gun")
	expect(bench.tools.equipped_tool == "heat-gun", "The bought heat gun could not be taken from its stand")
	await create_timer(0.1).timeout
	await capture("neighbourhood-heat-gun-held")
	await bench.tools.return_tool()
	expect(bench.tools.tool_location("heat-gun") == "stand", "The heat gun did not go back to its stand")
	await stand(bench, Vector3(26.5, -4.35, 5.9), Vector3(33, 3.25, 5.9))
	await process_frame
	await capture("neighbourhood-map-screen")
	# N shows the map over the view and hides it again.
	bench.camera_rig.set_captured(true)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_N
	key.pressed = true
	bench.first_person_input(key)
	expect(bench.hud.map_open(), "N did not open the neighbourhood map")
	await process_frame
	await capture("neighbourhood-map-overlay")
	bench.first_person_input(key)
	expect(not bench.hud.map_open(), "N did not close the neighbourhood map")
	# A glued megacorp card arrives sealed and needs the gun and pen; nothing else changes.
	jobs.offers[0] = glued_job
	shop.placed["test-station"] = true
	bench.testing_station.available = true
	expect(jobs.missing_equipment(glued_job).is_empty(), "The glued job stayed locked with every tool placed: %s" % [jobs.missing_equipment(glued_job)])
	expect(jobs.accept(glued_job.id), "The glued job could not be accepted")
	await fetch_parcel(bench)
	await jobs.unbox()
	await settle(bench)
	expect(bench.glue.sealed == bench.service.fan_screws, "The glued card did not arrive with glue over its fan screws")
	bench.computer.tab = "bench"
	bench.computer.refresh()
	await process_frame
	var page_text := ""
	for label in bench.computer.viewport.find_children("*", "Label", true, false): page_text += (label as Label).text + "\n"
	expect("WARRANTY GLUE" in page_text and "QUOTE $" in page_text, "The bench page did not warn of the glue or show the quote")
	# Returning it happy (same day, under the quote) turns its home green; a second green home
	# opens Old Town, whose households join the board.
	var first: Dictionary = area.reachable().filter(func(home: Dictionary): return home.id != glued_job.home)[0]
	area.record(first.id, 5)
	bench.debug_clean_gpu()
	bench.paste.debug_repaste()
	bench.bearing.debug_oil()
	bench.glue.set_sealed([])
	var result: Dictionary = jobs.return_card()
	expect(result.paid and result.stars >= 4 and area.home(glued_job.home).state == "green", "The happy household was %s with %s" % [area.home(glued_job.home).state, result])
	expect(area.unlocked == 2 and jobs.offers.size() == jobs.OFFER_COUNT + 1, "Old Town did not open or add a request: %d zones, %d offers" % [area.unlocked, jobs.offers.size()])
	expect(bench.hud.notice_label.text.contains("Old Town"), "Opening Old Town gave no notice: " + bench.hud.notice_label.text)
	var old_town := false
	for roll in range(30):
		var job: Dictionary = jobs.make_job([], "customer")
		old_town = old_town or area.home(job.home).zone == 1
	expect(old_town, "No customer called from Old Town after it opened")
	bench.hud.show_map(true)
	await process_frame
	await capture("neighbourhood-map-overlay-old-town")
	bench.hud.show_map(false)
	# Debug: a glued, half-opened card is fixed at once and paid for through the normal return.
	var quick: Dictionary = jobs.make_job(["dust", "bearing"], "customer")
	quick.glued = bench.service.fan_screws.duplicate()
	jobs.offers[0] = quick
	expect(jobs.accept(quick.id), "The quick debug job could not be accepted")
	await fetch_parcel(bench)
	await jobs.unbox()
	await settle(bench)
	bench.glue.set_sealed([])
	bench.service.debug_disassemble()
	bench.glue.set_sealed(quick.glued)
	var paid_before: int = jobs.balance
	await bench.debug_fix_and_return()
	expect(jobs.active().is_empty() and jobs.last_result.get("id") == quick.id and jobs.last_result.paid and jobs.balance > paid_before,
		"Debug fix-and-return did not pay for the card: %s" % [jobs.last_result])
	expect(bench.glue.sealed.is_empty() and bench.service.removed.is_empty() and bench.service.cable_connected, "Debug fix-and-return left the card open or glued")
	bench.queue_free()
	for frame in range(10): await process_frame
