extends SceneTree
var failures: Array[String] = []
var notices: Array[String] = []
func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/" + name + ".png")
func click(view: CanvasLayer, at: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	view.view_input(down)
func screen(view: CanvasLayer, node: Node3D) -> Vector2:
	var center: Vector3 = node.global_position
	if node is MeshInstance3D: center = node.global_transform * (node as MeshInstance3D).get_aabb().get_center()
	return view.camera.unproject_position(center)
func open_fan(bench: Node3D, fan: Node3D) -> void:
	bench.closeup.show_view("service", fan)
	# The close-up viewport is laid out over the next frames.
	await process_frame
	await process_frame
func switch_tool(bench: Node3D, id: String) -> void:
	bench.closeup.close()
	if bench.tools.equipped_tool != "": await bench.tools.return_tool()
	if id != "": await bench.tools.equip(id)
func run() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	bench.get_node("CameraRig").legacy_test_mode = true
	root.add_child(bench)
	await process_frame
	var bearing: Node = bench.bearing
	var rules: RefCounted = bench.service_rules
	var station: Node = bench.testing_station
	var view: CanvasLayer = bench.closeup
	var fan: Node3D = bench.asset_contract.objects["fan-assembly"]
	bearing.notice.connect(func(text: String): notices.append(text))
	expect(bearing.dry and not bearing.shaft_clean and bearing.oil_drops == 0 and bearing.total_gunk() > 5.0,
		"Fan did not start with a dry, gummed bearing")
	expect(bearing.rotor.is_ancestor_of(bearing.shaft) and fan.is_ancestor_of(bearing.boss) and not bearing.rotor.is_ancestor_of(bearing.boss),
		"Shaft must travel with the rotor and the bearing boss with the housing")
	# Rules own reach, order and tool choice.
	expect(not rules.check_opening("open", "hub-label", [], [], "").allowed, "Hub sticker was reachable on a mounted fan")
	expect(rules.check_opening("open", "hub-label", ["fan-assembly"], [], "").allowed, "Detached fan sticker could not be peeled by hand")
	expect(rules.check_opening("open", "hub-label", ["fan-assembly"], [], "ipa-wipe").allowed, "A light tool in hand blocked peeling")
	expect(not rules.check_opening("open", "hub-label", ["fan-assembly"], [], "screwdriver").allowed, "Screwdriver in hand could peel the sticker")
	expect(not rules.check_opening("open", "fan-rotor", ["fan-assembly"], [], "").allowed, "Rotor came out under the sticker")
	expect(not rules.check_opening("close", "hub-label", ["fan-assembly"], ["hub-label", "fan-rotor"], "").allowed, "Sticker closed over a pulled rotor")
	expect(not rules.check_surface("wipe", "shaft", ["fan-assembly"], "ipa-wipe", ["hub-label"]).allowed, "Shaft was wipeable inside the fitted rotor")
	expect(rules.check_surface("wipe", "shaft", ["fan-assembly"], "ipa-wipe", ["hub-label", "fan-rotor"]).allowed, "Exposed shaft refused the IPA wipe")
	expect(not rules.check_surface("scrape", "shaft", ["fan-assembly"], "spudger", ["hub-label", "fan-rotor"]).allowed, "Spudger could scrape the shaft")
	expect(rules.check_surface("oil", "die", ["cooler-assembly"], "fan-oiler").reason == "Only the fan bearing takes oil.", "The die accepted oil")
	var broken = preload("res://scripts/service_rules.gd").new(bench.asset_contract.service_parts, [], [], [{"id": "x", "insideOf": "missing"}])
	expect(not broken.check_opening("open", "x", ["missing"], [], "").allowed, "Malformed opening did not fail closed")
	# The dry bearing grinds while the fan spins on the test board.
	expect(station.attach(), "Assembled GPU could not attach for the grind check")
	await create_timer(0.6).timeout
	for step in range(90): station._process(1.0 / 60.0)
	expect(station.grind_audio.playing and station.grind_audio.volume_db > -20.0, "Dry bearing did not grind on the test board")
	station.set_muted(true)
	expect(station.grind_audio.volume_db == -80.0, "Mute did not silence the grind")
	station.set_muted(false)
	expect(station.detach(), "GPU could not leave the test board")
	await create_timer(0.6).timeout
	for step in range(120): station._process(1.0 / 60.0)
	expect(not station.grind_audio.playing, "Grind kept playing after the fan stopped")
	expect(bench.service.debug_disassemble(), "Setup disassembly failed")
	await create_timer(0.1).timeout
	# Empty hands in focus: peel the sticker, then pull the rotor.
	await open_fan(bench, fan)
	view.direction = (fan.global_basis.y.normalized() + fan.global_basis.z.normalized() * 0.5).normalized()
	view.update_camera()
	await capture("fan-bearing-sticker")
	var cap: MeshInstance3D = fan.find_child("fan-hub-cap", true, false)
	expect(bearing.click_target(view.pick.hit_at(screen(view, cap)).get("mesh")) == "hub-label", "Hub sticker was not the click target")
	click(view, screen(view, cap))
	expect(bearing.moving and bearing.peel_audio.playing, "Peeling did not start with its recording")
	await create_timer(bearing.peel_time() + 0.15).timeout
	expect("hub-label" in bearing.opened and not cap.visible, "Sticker did not peel off")
	expect(notices.any(func(text: String): return "peeled" in text), "Peeling gave no notice")
	var hub: MeshInstance3D = fan.find_child("fan-hub", true, false)
	click(view, screen(view, hub))
	await create_timer(0.6).timeout
	expect("fan-rotor" in bearing.opened and bearing.rotor.transform.is_equal_approx(bearing.ROTOR_ASIDE), "Rotor was not pulled and set aside")
	expect(bench.service.refit_block.call("fan-assembly") != "", "Fan could be mounted with its rotor out")
	await capture("fan-bearing-rotor-out")
	# IPA wipe on the exposed shaft: strokes along it lift the gunk.
	await switch_tool(bench, "ipa-wipe")
	await open_fan(bench, fan)
	expect(view.bearing_face() == "shaft", "IPA wipe did not frame the exposed shaft")
	await capture("fan-shaft-gunk")
	var gunk_before: float = bearing.total_gunk()
	var top: Vector2 = view.camera.unproject_position(bearing.shaft.to_global(Vector3(0, bearing.SHAFT_LENGTH * 0.5, 0)))
	var bottom: Vector2 = view.camera.unproject_position(bearing.shaft.to_global(Vector3(0, -bearing.SHAFT_LENGTH * 0.5, 0)))
	click(view, top.lerp(bottom, 0.5))
	var stroke := 0
	while not bearing.shaft_clean and stroke < 12:
		for step in range(21):
			view.cleaning_pointer = top.lerp(bottom, step / 20.0 if stroke % 2 == 0 else 1.0 - step / 20.0)
			view.bearing_under_pointer(0.05)
		stroke += 1
	bearing.end()
	expect(bearing.shaft_clean and bearing.total_gunk() == 0.0 and gunk_before > 0.0, "Wiping did not clean the shaft")
	expect(stroke <= 6, "Cleaning the shaft took too many strokes (%d)" % stroke)
	expect(notices.any(func(text: String): return "Shaft clean" in text), "Clean shaft gave no completion notice")
	await capture("fan-shaft-clean")
	# Oiler: holding on the bearing lets drops fall at a steady rate.
	await switch_tool(bench, "fan-oiler")
	await open_fan(bench, fan)
	expect(view.bearing_face() == "bearing", "Oiler did not frame the bearing")
	var sleeve_point: Vector2 = screen(view, bearing.sleeve)
	click(view, sleeve_point)
	# The first drop falls shortly after the press, then one every 0.4 s.
	for step in range(14):
		view.cleaning_pointer = sleeve_point
		view.bearing_under_pointer(0.05)
	bearing.end()
	expect(bearing.oil_drops == 2 and bearing.oil_bead.visible, "A short hold on the bearing did not give two drops (%d)" % bearing.oil_drops)
	await capture("fan-bearing-oiled")
	# Clicking the resting rotor refits it and presses the sticker back on.
	notices.clear()
	click(view, screen(view, bearing.rotor.find_child("fan-blade-1", true, false)))
	await create_timer(0.6).timeout
	expect(bearing.opened.is_empty() and cap.visible and bearing.rotor.transform.is_equal_approx(bearing.rotor_home),
		"Rotor refit did not restore the rotor and sticker")
	expect(not bearing.dry and notices.any(func(text: String): return "quietly" in text), "Serviced bearing still counts as dry")
	expect(bench.service.refit_block.call("fan-assembly") == "", "Serviced fan was still blocked from mounting")
	view.close()
	await bench.tools.return_tool()
	station.update_fan_audio(true)
	expect(not station.grind_audio.playing, "Oiled bearing still grinds")
	# A fan mounted with only its sticker peeled gets the sticker pressed back on.
	await open_fan(bench, fan)
	view.direction = (fan.global_basis.y.normalized() + fan.global_basis.z.normalized() * 0.5).normalized()
	view.update_camera()
	click(view, screen(view, cap))
	await create_timer(bearing.peel_time() + 0.15).timeout
	view.close()
	expect(bench.service.refit_block.call("fan-assembly") == "", "A peeled sticker alone blocked mounting")
	bench.service.assembly_seated.emit("fan-assembly")
	expect(bearing.opened.is_empty() and cap.visible and not bearing.dry, "Mounting did not press the peeled sticker back on")
	expect(bearing.debug_dry() and bearing.dry and bearing.total_gunk() > 5.0, "Debug dry did not restore the gummed bearing")
	expect(bearing.debug_oil() and not bearing.dry and bearing.shaft_clean, "Debug oil did not service the bearing")
	bench.queue_free()
	await process_frame
	print("PASS: fan bearing rules, dry grind, sticker peel, rotor pull, shaft wipe, oil drops, rotor refit and debug toggles" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
