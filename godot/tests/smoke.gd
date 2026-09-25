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
	bench.queue_free()
	await process_frame
	print("PASS: %d reference rule decisions, invalid graph checks, asset hierarchy, camera/picking and five inspection cycles." % checked if failures.is_empty() else "FAIL: " + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
