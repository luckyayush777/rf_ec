extends SceneTree
const Style = preload("res://scripts/gpu_style.gd")
const Contract = preload("res://scripts/asset_contract.gd")
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/" + name + ".png")
func frame_box(bench: Node3D) -> void:
	var camera: Camera3D = bench.camera_rig.camera
	bench.camera_rig.legacy_test_mode = true
	bench.hud.set_menu_open(false)
	camera.global_position = bench.delivery_box.global_position + Vector3(0.3, 3.3, 4.0)
	camera.look_at(bench.delivery_box.global_position + Vector3(0, 0.35, 0))
## Parcels come in through the window hatch; carry this one to the box's authored desk spot.
func fetch_parcel(bench: Node3D) -> void:
	bench.delivery_window.arrival_delay = 0.1
	while bench.delivery_box.location != "sill": await process_frame
	bench.pick_up_parcel()
	await create_timer(0.35).timeout
	bench.set_down_parcel(bench.parcel_spot)
	await create_timer(0.45).timeout
func run() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	bench.job_flow = true
	root.add_child(bench)
	await process_frame
	bench.camera_rig.set_captured(false)
	bench.hud.set_menu_open(false)
	bench.hud.audio_save_timer.stop()
	var gpu: Node3D = bench.gpu
	var home: Transform3D = gpu.transform
	var contact: MeshInstance3D = gpu.find_child("gold-contact-17-1", true, false)
	var gold: Color = contact.mesh.surface_get_material(0).albedo_color
	# A second imported card detects mutation of the shared asset resources.
	var untouched: Node3D = load("res://assets/gpu.glb").instantiate()
	var source_board: MeshInstance3D = untouched.find_child("board-top", true, false)
	var original_board: Color = source_board.mesh.surface_get_material(0).albedo_color
	var seen := {}
	for id in Style.BRANDS:
		var offer: Dictionary = bench.jobs.offers[0]
		offer.brand = id
		offer.model = id + " " + bench.jobs.MODEL
		offer.faults = ["bearing"]
		expect(bench.jobs.accept(offer.id), "Could not accept " + id)
		await fetch_parcel(bench)
		frame_box(bench)
		await capture("brand-" + id.to_lower() + "-sealed")
		expect(bench.delivery_box.brand == id and not bench.delivery_box.parked, "New box inherited the previous packaging state")
		expect(bench.delivery_box.transform.is_equal_approx(bench.delivery_box.rest), "New box did not land where it was set down")
		expect(is_zero_approx(bench.delivery_box.flaps[0].rotation.x), "New box arrived already open")
		await bench.jobs.unbox()
		expect(bench.gpu_style.brand == id and bench.delivery_box.brand == id, "Card/box brand mismatch")
		expect(bench.delivery_box.visible and bench.delivery_box.parked, "Empty packaging disappeared")
		var box_bounds: AABB = bench.delivery_box.global_transform * Contract.bounds_in(bench.delivery_box)
		var mat: MeshInstance3D = bench.get_node("RepairDesk/Mat")
		expect(not box_bounds.intersects(mat.global_transform * mat.get_aabb()), "Empty packaging stayed on the mat")
		expect(Contract.fits_table(box_bounds, bench.get_node("RepairDesk/Tabletop")), "Empty packaging overhung the table")
		for obstacle in bench.placement_obstacles("delivery_box"):
			expect(not box_bounds.intersects(obstacle), "Empty packaging overlaps a desk object")
		frame_box(bench)
		await capture("brand-" + id.to_lower() + "-opened")
		var colors := Style.palette(id)
		var roles := {}
		for entry in bench.gpu_style.materials.values():
			roles[entry.role] = true
			expect(entry.material.albedo_color.is_equal_approx(Color(colors[entry.role])), "Wrong colour for " + id + "/" + entry.role)
		expect(roles.size() == 8, "Brand palette did not reach the full component set: " + str(roles))
		var board: MeshInstance3D = gpu.find_child("board-top", true, false)
		seen[id] = board.mesh.surface_get_material(0).albedo_color
		expect(source_board.mesh.surface_get_material(0).albedo_color.is_equal_approx(original_board), "Palette leaked into another imported GPU")
		expect(contact.mesh.surface_get_material(0).albedo_color.is_equal_approx(gold), "Palette recoloured diagnostic gold contacts")
		expect(gpu.transform.is_equal_approx(home), "Palette changed card scale or placement")
		await bench.tools.equip("screwdriver")
		bench.closeup.show_view("service", gpu)
		bench.closeup.direction = gpu.global_basis.y.normalized()
		bench.closeup.update_camera()
		await process_frame
		await process_frame
		await capture("brand-" + id.to_lower() + "-card")
		var board_proxy: MeshInstance3D
		for proxy in bench.closeup.proxies:
			if proxy.source == board: board_proxy = proxy.node
		expect(board_proxy != null and board_proxy.mesh == board.mesh, "Focus did not share the current brand's materials")
		bench.closeup.close()
		await bench.tools.return_tool()
		expect(not bench.jobs.return_card().is_empty(), "Could not return the branded card")
		await create_timer(0.3).timeout
		expect(not bench.delivery_box.visible, "Old packaging was not cleared when the job ended")
	expect(seen.Lotac != seen.Vsus and seen.Vsus != seen.CSI and seen.CSI != seen.Lotac, "Brands share a board colour")
	bench.gpu_style.apply_brand("Lotac")
	expect((gpu.find_child("board-top", true, false) as MeshInstance3D).mesh.surface_get_material(0).albedo_color == seen.Lotac, "A repeated brand did not restore its original scheme")
	untouched.free()
	bench.queue_free()
	await process_frame
	print("PASS: three consistent brand palettes, isolated imported materials, live focus colours, branded retail packaging, side placement and next-job reset" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
