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
	bench.queue_free()
	await process_frame
	print("PASS: %d reference rule decisions, invalid graph checks, asset hierarchy, camera/picking and five inspection cycles." % checked if failures.is_empty() else "FAIL: " + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
