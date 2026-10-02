extends SceneTree
## Run the existing workbench with the separate rounded GPU draft.
## --check validates the draft; --job-flow uses the normal empty-bench job loop.
const Contract = preload("res://scripts/asset_contract.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	root.get_texture().get_image().save_png("res://build/" + name + ".png")

func run() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var draft_path := ProjectSettings.globalize_path("res://../models/gpu-rounded.glb")
	if document.append_from_file(draft_path, state) != OK:
		push_error("Cannot load the rounded draft: " + draft_path)
		quit(1)
		return
	var imported := document.generate_scene(state)
	if imported == null:
		push_error("Cannot instantiate the rounded draft")
		quit(1)
		return
	# The document loader can add a scene wrapper; use the canonical GPU hierarchy.
	var gpu: Node3D = imported
	if not gpu.has_node("board"):
		gpu = imported.find_child("gpu", true, false) as Node3D
		if gpu == null:
			imported.free()
			push_error("Rounded draft has no gpu root")
			quit(1)
			return
		gpu.get_parent().remove_child(gpu)
		imported.free()
	var bench = load("res://scenes/workbench.tscn").instantiate()
	var original: Node3D = bench.get_node("GPUAsset")
	gpu.transform = original.transform
	bench.remove_child(original)
	original.free()
	gpu.name = "GPUAsset"
	bench.add_child(gpu)
	bench.job_flow = "--job-flow" in OS.get_cmdline_user_args()
	root.add_child(bench)
	await process_frame
	expect(bench.asset_contract.errors.is_empty(), "Rounded draft violates the asset contract")
	expect(bench.service_rules.errors.is_empty(), "Rounded draft violates service dependencies")
	if not failures.is_empty():
		bench.queue_free()
		await process_frame
		quit(1)
		return
	if not bench.job_flow:
		bench.jobs.apply_faults([])
	if "--check" not in OS.get_cmdline_user_args():
		print("Rounded GPU preview ready. Existing workbench controls apply.")
		return
	# Exercise this imported model, rather than the production GLB.
	bench.hud.audio_save_timer.stop()
	bench.service.set_muted(true)
	bench.cleaning.set_muted(true)
	bench.testing_station.set_muted(true)
	var home: Transform3D = gpu.global_transform
	var card_scale: Vector3 = home.basis.get_scale()
	expect(card_scale.is_equal_approx(Vector3.ONE * .25), "Draft changed physical card scale")
	for id in ["gpu-die", "heatsink-base", "fan-rotor", "fan-hub-cap", "fan-plug",
			"gold-contact-17-1", "gold-contact-24-1"]:
		expect(gpu.find_child(id, true, false) != null, "Draft lost repair surface: " + id)
	expect(bench.service.debug_disassemble(), "Draft cannot disassemble")
	expect(bench.service.removed.size() == 10, "Draft disassembly lost screws or assemblies")
	expect(not bench.testing_station.can_attach(), "Draft allows testing while disassembled")
	expect(bench.service.debug_reassemble(), "Draft cannot reassemble")
	expect(bench.service.removed.is_empty() and bench.service.cable_connected, "Draft did not reassemble completely")
	for id in ["cooler-assembly", "fan-assembly"] + bench.service.fan_screws + bench.service.cooler_screws:
		var part: Node3D = bench.asset_contract.objects[id]
		var original_home: Dictionary = bench.asset_contract.homes[id]
		expect(part.get_parent() == original_home.parent and part.transform.is_equal_approx(original_home.transform),
			"Draft did not restore the home of " + id)
	# Confirm the larger screw heads remain exposed to focus picking.
	await bench.tools.equip("screwdriver")
	bench.closeup.show_view("service", gpu)
	bench.closeup.direction = gpu.global_basis.y.normalized()
	bench.closeup.update_camera()
	await process_frame
	await process_frame
	await capture("gpu-rounded-in-game-front")
	for id in bench.service.fan_screws:
		var screw: Node3D = bench.asset_contract.objects[id]
		var screen: Vector2 = bench.closeup.camera.unproject_position(screw.global_position)
		expect(bench.closeup.pick.hit_at(screen).get("target") == screw, "Draft obscures fan screw: " + id)
	bench.closeup.direction = -gpu.global_basis.y.normalized()
	bench.closeup.update_camera()
	await capture("gpu-rounded-in-game-rear")
	bench.closeup.close()
	await bench.tools.return_tool()
	expect(bench.testing_station.attach(), "Rounded card cannot seat on the test board")
	if bench.testing_station.motion != null:
		await bench.testing_station.motion.finished
	expect(bench.testing_station.installed, "Rounded card did not finish seating")
	expect(gpu.global_basis.get_scale().is_equal_approx(card_scale), "Draft changed scale on the test board")
	expect(bench.testing_station.detach(), "Rounded card cannot leave the test board")
	if bench.testing_station.motion != null:
		await bench.testing_station.motion.finished
	expect(gpu.global_transform.is_equal_approx(home), "Draft did not return to its holder")
	print("ROUNDED_GPU_PREVIEW_PASS" if failures.is_empty() else "ROUNDED_GPU_PREVIEW_FAIL: " + str(failures))
	bench.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
