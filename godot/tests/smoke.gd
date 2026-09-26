extends SceneTree

const Rules = preload("res://scripts/service_rules.gd")
const ServiceFlow = preload("res://tests/service_flow.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var fixture_path := "res://.godot/rule-fixtures.json"
	if not FileAccess.file_exists(fixture_path):
		push_error("Run node godot/tools/build-rule-fixtures.mjs before this test.")
		quit(1)
		return
	var fixture_sets: Array = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	var checked := 0
	for fixture in fixture_sets:
		var rules = Rules.new(fixture.definitions, fixture.exceptions)
		expect(rules.errors.is_empty(), "Valid service definitions rejected")
		for case in fixture.cases:
			var result: Dictionary = rules.check(case.kind, case.id, case.removed, case.connected, case.tool)
			expect(result.allowed == case.allowed and result.missing == case.missing,
				"Rule mismatch: " + str(case))
			checked += 1
	for definitions in [
		[{"id": "a", "kind": "assembly", "requires": ["missing"]}],
		[{"id": "a", "kind": "assembly", "requires": ["b"]}, {"id": "b", "kind": "assembly", "requires": ["a"]}],
		[{"id": "a", "kind": "assembly", "requires": []}, {"id": "a", "kind": "assembly", "requires": []}]
	]:
		var invalid = Rules.new(definitions)
		expect(not invalid.errors.is_empty(), "Invalid service graph accepted")
		expect(not invalid.check("remove", "a").allowed, "Invalid graph did not fail closed")
	var auxiliary = Rules.new([{"id": "aux-plug", "kind": "connector", "requires": []},
		{"id": "aux-assembly", "kind": "assembly", "requires": ["aux-plug"]}])
	expect(not auxiliary.check("remove", "aux-assembly", [], {"aux-plug": true}).allowed, "Auxiliary connector ignored")
	expect(auxiliary.check("remove", "aux-assembly", [], {"aux-plug": false}).allowed, "Disconnected auxiliary connector blocked removal")
	expect(not auxiliary.check("pickup", "aux-plug").allowed, "Invalid connector action accepted")

	var packed: PackedScene = load("res://scenes/workbench.tscn")
	var bench = packed.instantiate()
	root.add_child(bench)
	await process_frame
	await physics_frame
	expect(bench.asset_contract.errors.is_empty(), "Imported GPU metadata contract failed")
	var room: Node3D = bench.get_node("ShopInterior")
	expect(room.find_child("oscilloscope-body", true, false) != null and
		room.find_child("SCREWS-text", true, false) != null, "Workshop props missing")
	var ceiling: Node3D = room.find_child("ceiling", true, false)
	expect(ceiling != null and not ceiling.is_visible_in_tree(), "Workshop cutaway ceiling blocks the camera")
	expect(not bench.get_node("RepairDesk/Floor").visible, "Old floor overlaps workshop floor")
	expect(bench.asset_contract.objects.has("fan-positive-wire"), "Cable wire missing")
	expect(bench.asset_contract.homes.size() == 20, "Expected 20 part home transforms")
	expect(bench.asset_contract.service_parts.size() == 11, "Expected two assemblies, eight screws, one connector")
	expect(bench.gpu.find_children("memory-residue-*", "MeshInstance3D", true, false).size() == 12, "Residue mesh identities lost")
	var dust = bench.cleaning
	bench.select_view("top")
	var sample_fan: MeshInstance3D = bench.gpu.find_child("fan-blade-1", true, false)
	var fan_arrays: Array = sample_fan.mesh.surface_get_arrays(0)
	var fa: PackedInt32Array = fan_arrays[Mesh.ARRAY_INDEX]
	var fv: PackedVector3Array = fan_arrays[Mesh.ARRAY_VERTEX]
	var fn: PackedVector3Array = fan_arrays[Mesh.ARRAY_NORMAL]
	var fi0: int = fa[0]
	var fi1: int = fa[1]
	var fi2: int = fa[2]
	var rendered_normal := (fn[fi0] + fn[fi1] + fn[fi2]).normalized()
	var mask_normal: Vector3 = dust.surface_normal(fv[fi0], fv[fi1], fv[fi2])
	expect(mask_normal.dot(rendered_normal) > 0.9, "Fan dust mask uses a face opposite its rendered surface")
	var hub: MeshInstance3D = bench.gpu.find_child("fan-hub-cap", true, false)
	var hub_screen: Vector2 = bench.camera_rig.camera.unproject_position(hub.global_transform * hub.get_aabb().get_center())
	var ordinary_hub_hit: Dictionary = bench.picker.surface_hit_at(hub_screen)
	var cleaning_hub_hit: Dictionary = bench.picker.surface_hit_at(hub_screen, true)
	expect(ordinary_hub_hit.get("mesh") != hub and cleaning_hub_hit.get("mesh") == hub,
		"Fan hub decoration still blocks cleaning the cap")
	expect(dust.surfaces.size() >= 10, "Cleanable GPU surfaces were not mapped")
	expect(dust.part_progress("board") < 0.01 and dust.part_progress("fan-assembly") < 0.01 and
		dust.part_progress("cooler-assembly") < 0.01, "Part-specific dust did not start dirty")
	var board_surface: Dictionary = {}
	for surface in dust.surfaces:
		if surface.name == "board-top": board_surface = surface
		expect(surface.mesh.material_overlay != null, "Dust overlay missing from " + surface.name)
		var covered := 0
		var dusty := 0
		for index in range(surface.coverage.size()):
			if surface.coverage[index] != 0: covered += 1
			if surface.data[index] != 0: dusty += 1
		expect(covered > 0 and absf(float(dusty) / maxf(covered, 1) - 0.4) < 0.04,
			"Initial dust coverage is not near 40% on " + surface.name)
	expect(not board_surface.is_empty(), "PCB front dust surface missing")
	if not board_surface.is_empty():
		var first_rng := RandomNumberGenerator.new()
		first_rng.seed = 101
		var second_rng := RandomNumberGenerator.new()
		second_rng.seed = 202
		expect(dust.make_dust_mask(board_surface.coverage, first_rng) != dust.make_dust_mask(board_surface.coverage, second_rng),
			"Dust pattern did not vary with the random seed")
		var board_mesh: MeshInstance3D = board_surface.mesh
		var center: Vector3 = board_mesh.global_transform * board_surface.bounds.get_center()
		expect(dust.clean_at(board_mesh, center, Vector3.UP, 0.6, 10.0) > 0.0, "Blower did not clean PCB front")
		expect(dust.part_progress("board") > 0.0 and dust.part_progress("fan-assembly") < 0.01 and
			dust.part_progress("cooler-assembly") < 0.01, "Cleaning PCB changed another part's dust")
	expect(bench.testing_desk.find_child("floor", true, false) == null, "Second floor was not removed")
	var tabletop: MeshInstance3D = bench.testing_desk.find_child("desk-top", true, false)
	var table_bounds: AABB = tabletop.global_transform * tabletop.get_aabb()
	expect(absf(table_bounds.end.y) < 0.001 and absf(table_bounds.position.x - 12.5) < 0.001,
		"Testing desk alignment differs from browser")
	var station = bench.testing_station
	var monitor = bench.test_monitor
	expect(station.attach_audio.stream != null and monitor.power_audio.stream != null, "Testing sounds are not connected")
	expect(station.attach_audio.stream.resource_path == "res://assets/sounds/gpu_sounds/gpu_attach_short.wav" and
		station.attach_audio.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED,
		"GPU attachment must use the supplied short recording without looping")
	expect(monitor.get_node("PowerButton").get_meta("action") == "monitor_power", "Physical monitor button is missing")
	expect(station.board.get_meta("action") == "test_board", "Testing board is not interactive")
	bench.select_view("testing")
	var test_board_mesh: MeshInstance3D = station.board.find_child("pcb-substrate", true, false)
	var board_screen: Vector2 = bench.camera_rig.camera.unproject_position(test_board_mesh.global_position)
	expect(bench.picker.hit_at(board_screen).get("action") == "test_board", "Testing board cannot be picked")
	var button_screen: Vector2 = bench.camera_rig.camera.unproject_position(monitor.button.global_position)
	expect(bench.picker.hit_at(button_screen).get("action") == "monitor_power", "Monitor power button cannot be picked")
	bench.activate(board_screen)
	await create_timer(0.6).timeout
	expect(station.installed and monitor.connected and monitor.simulated_fps <= 20, "Dirty GPU did not start the slow test")
	var housing: Node3D = bench.gpu.find_child("fan-housing", true, false)
	var housing_home := housing.transform
	for step in range(120): station._process(1.0 / 60.0)
	expect(station.fan_speed > 4.0 and station.quiet_audio.playing and station.loud_audio.playing,
		"Dirty installed GPU did not spin up and play fan loops with the monitor off")
	var rotor_before: Transform3D = station.rotor.transform
	station._process(0.013)
	expect(not station.rotor.transform.is_equal_approx(rotor_before) and housing.transform.is_equal_approx(housing_home),
		"Fan animation failed to rotate only the rotor")
	expect(station.quiet_audio.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and
		station.loud_audio.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Fan recordings do not loop")
	station.set_muted(true)
	station._process(0.1)
	expect(station.quiet_audio.volume_db == -80.0 and station.loud_audio.volume_db == -80.0,
		"Fan process overrode sound mute")
	station.set_muted(false)
	expect(station.loud_audio.volume_db > -20.0, "Fan sound did not unmute")
	expect(not bench.inspection.can_interact.call(), "Installed GPU can still be inspected")
	bench.activate(button_screen)
	for step in range(8): monitor._process(0.125)
	expect(monitor.powered and monitor.presented_frames > 0 and monitor.piece_cells.size() == 4 and monitor.piece_y > -2,
		"Falling-block test did not advance")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://build")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/testing-dirty.png")
		monitor.image.save_png("res://build/tetris-feed.png")
	monitor.reset_simulation()
	for step in range(240): monitor.advance_demo(1.0 / 60.0)
	expect(monitor.lines_cleared >= 1 and monitor.score >= 100,
		"Falling-block demonstration did not clear and score a row")
	monitor.reset_simulation()
	expect(station.detach(), "GPU could not be removed from test board")
	await create_timer(0.6).timeout
	expect(not station.installed and not monitor.connected and bench.gpu.global_transform.is_equal_approx(station.home),
		"GPU did not return to its repair-holder transform")
	for step in range(60): station._process(1.0 / 60.0)
	expect(station.fan_speed == 0.0 and not station.quiet_audio.playing and not station.loud_audio.playing and
		station.rotor.transform.is_equal_approx(station.rotor_home) and station.fan_label.transform.is_equal_approx(station.label_home),
		"Removed GPU did not stop its fan/audio and restore authored transforms")
	var inspection = bench.inspection
	var camera: Camera3D = bench.camera_rig.camera
	for view in ["both", "repair", "testing", "top"]:
		bench.select_view(view)
		expect(camera.position.is_finite(), "Camera preset produced invalid coordinates")
	bench.select_view("repair")
	var old_camera := camera.transform
	bench.camera_rig.orbit(Vector2(50, 25))
	bench.camera_rig.zoom(0.9)
	bench.camera_rig.pan(Vector2(20, 10))
	expect(not camera.transform.is_equal_approx(old_camera), "Orbit controls did not move camera")
	bench.select_view("repair")
	# Run picking through the scene geometry, not just the inspection button.
	await physics_frame
	var point: Vector3 = bench.gpu.global_transform * inspection.center
	bench.pick_gpu(camera.unproject_position(point))
	expect(inspection.held, "Whole-GPU picking failed")
	await create_timer(0.55).timeout
	for cycle in range(5):
		if not inspection.held:
			inspection.lift()
			await create_timer(0.55).timeout
		expect(inspection.held and not inspection.moving, "Inspection lift failed")
		var locked_camera := camera.transform
		bench.select_view("testing")
		expect(camera.transform.is_equal_approx(locked_camera), "Camera preset changed during inspection")
		inspection.rotate_item(Vector2(70, 30))
		inspection.flip()
		inspection.zoom(0.8)
		await process_frame
		expect(bench.gpu.global_position.is_finite(), "Held GPU position invalid")
		inspection.put_down()
		await create_timer(0.55).timeout
		expect(not inspection.held and not inspection.moving, "GPU return failed")
		expect(bench.gpu.transform.is_equal_approx(inspection.home), "GPU home transform drifted")

	await ServiceFlow.new().run(self, bench, expect)
	# Every generated fan patch must be reachable from the mounted top view.
	bench.select_view("top")
	var inaccessible_fan: Array[String] = []
	for surface in dust.surfaces:
		if surface.owner != "fan-assembly" or surface.remaining <= 0.0: continue
		var mesh: MeshInstance3D = surface.mesh
		for si in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(si)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for ti in range(indices.size() / 3):
				if surface.remaining <= surface.mass * 0.01: break
				var a: Vector3 = vertices[indices[ti * 3]]
				var b: Vector3 = vertices[indices[ti * 3 + 1]]
				var c: Vector3 = vertices[indices[ti * 3 + 2]]
				var normal: Vector3 = dust.surface_normal(a, b, c)
				if (mesh.global_basis * normal).normalized().y < 0.6: continue
				var fan_point: Vector3 = mesh.global_transform * ((a + b + c) / 3.0)
				var fan_screen: Vector2 = camera.unproject_position(fan_point)
				var hit: Dictionary = bench.picker.surface_hit_at(fan_screen, true)
				if hit.get("mesh") == mesh:
					dust.clean_at(mesh, hit.point, hit.normal, 0.6, 1.1)
		if surface.remaining > surface.mass * 0.01:
			inaccessible_fan.append("%s: %.1f%% left" % [surface.name, surface.remaining / surface.mass * 100.0])
	expect(inaccessible_fan.is_empty(), "Mounted fan dust remains unreachable: " + str(inaccessible_fan))
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://build")
		bench.select_view("repair")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/repair.png")
		bench.select_view("both")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/both.png")
		inspection.lift()
		await create_timer(0.55).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/inspection.png")
		inspection.flip()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/back.png")
		inspection.put_down()
		await create_timer(0.55).timeout
	expect(dust.jingle.stream != null and dust.air.stream != null, "Cleaning sounds are not configured")
	expect(dust.air.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and dust.air.stream.loop_begin > 0,
		"Blower sustain segment is not looped")
	for owner in ["fan-assembly", "board", "cooler-assembly"]:
		for surface in dust.surfaces:
			if surface.owner == owner: surface.remaining = surface.mass * 0.019
		expect(dust.finish_if_ready(), "Part did not finish at 98%: " + owner)
		expect(is_equal_approx(dust.part_progress(owner), 1.0), "Part retained dust after completion: " + owner)
		expect(not dust.finish_if_ready(), "Part jingle was triggered twice: " + owner)
	expect(is_equal_approx(dust.progress, 1.0) and dust.completed_count == 3 and dust.celebrated,
		"Cleaning did not complete all three parts once")
	expect(not dust.highlighted, "Dust highlight remained on after full cleaning")
	expect(station.attach(), "Clean GPU did not reattach to test board")
	await create_timer(0.6).timeout
	expect(monitor.connected and monitor.simulated_fps == 60, "Clean GPU did not start the smooth test")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		bench.select_view("testing")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/testing-clean.png")
	station.attach_audio.stop()
	dust.jingle.stop()
	station.attach_audio.stream = null
	dust.jingle.stream = null
	await create_timer(0.1).timeout
	bench.queue_free()
	await process_frame
	# Debug shortcuts must leave the same controller state as normal service.
	var debug_bench = packed.instantiate()
	root.add_child(debug_bench)
	await process_frame
	expect(debug_bench.hud.debug_clean_button.visible and debug_bench.hud.debug_disassemble_button.visible,
		"Debug shortcuts are missing from the HUD")
	expect(debug_bench.testing_station.attach(), "Dirty GPU could not attach before debug cleaning")
	await create_timer(0.6).timeout
	expect(debug_bench.test_monitor.simulated_fps <= 20, "Debug fixture did not start dirty")
	var fan_station = debug_bench.testing_station
	for step in range(120): fan_station._process(1.0 / 60.0)
	var dirty_volume: float = fan_station.loud_audio.volume_db
	# Partial repair must produce an intermediate speed/noise, not an on/off switch.
	for surface in debug_bench.cleaning.surfaces: surface.remaining = surface.mass * 0.5
	for step in range(180): fan_station._process(1.0 / 60.0)
	expect(fan_station.fan_speed > 4.0 and fan_station.fan_speed < 5.0 and
		fan_station.loud_audio.volume_db < dirty_volume - 4.0, "Partial cleaning did not reduce fan speed/noise")
	debug_bench.hud.debug_clean_button.pressed.emit()
	expect(is_equal_approx(debug_bench.cleaning.progress, 1.0) and debug_bench.cleaning.celebrated and
		debug_bench.cleaning.completed_count == 3 and not debug_bench.cleaning.highlighted,
		"Debug clean did not complete all dust state")
	for surface in debug_bench.cleaning.surfaces:
		expect(surface.remaining == 0.0 and surface.data.count(0) == surface.data.size(),
			"Debug clean left visible dust on " + surface.name)
	expect(debug_bench.test_monitor.simulated_fps == 60,
		"Debug cleaning did not update the connected monitor")
	for step in range(240): fan_station._process(1.0 / 60.0)
	expect(absf(fan_station.fan_speed - fan_station.CLEAN_FAN_SPEED) < 0.01 and
		fan_station.loud_audio.volume_db < -60.0 and fan_station.quiet_audio.playing,
		"Clean installed GPU did not settle to the quiet fan loop")
	expect(debug_bench.testing_station.detach(), "Debug GPU could not leave test board")
	await create_timer(0.6).timeout
	debug_bench.hud.debug_disassemble_button.pressed.emit()
	var debug_service = debug_bench.service
	expect(debug_service.removed.size() == 10 and not debug_service.cable_connected and
		debug_service.held_part == "" and debug_service.turns.is_empty() and debug_service.stored.is_empty(),
		"Debug disassembly left incomplete service state")
	for id in debug_service.fan_screws + debug_service.cooler_screws:
		expect(id in debug_service.removed and debug_bench.asset_contract.objects[id].get_parent() == debug_bench and
			debug_service.screw_seats[id].get_parent() == debug_bench.asset_contract.homes[id].parent,
			"Debug disassembly misplaced " + id)
	for id in ["fan-assembly", "cooler-assembly"]:
		var part: Node3D = debug_bench.asset_contract.objects[id]
		expect(id in debug_service.removed and part.get_parent() == debug_bench and part.visible and
			part.global_position.y > -1.0, "Debug disassembly did not place " + id)
	expect(not debug_bench.testing_station.can_attach(), "Disassembled GPU could attach to the test board")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		debug_bench.select_view("repair")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/debug-disassembled.png")
	expect(debug_service.refit_assembly(), "Debug-disassembled heatsink could not refit")
	await debug_service.motion.finished
	expect(debug_service.refit_assembly(), "Debug-disassembled fan could not refit")
	await debug_service.motion.finished
	expect(debug_service.cable_progress == 1.0 and "fan-assembly" not in debug_service.removed and
		"cooler-assembly" not in debug_service.removed, "Debug disassembly broke normal assembly refit")
	debug_bench.testing_station.attach_audio.stop()
	debug_bench.testing_station.attach_audio.stream = null
	debug_bench.queue_free()
	await process_frame
	print("PASS: %d reference rule decisions, invalid graph checks, asset hierarchy, camera/picking and five inspection cycles." % checked if failures.is_empty() else "FAIL: " + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
