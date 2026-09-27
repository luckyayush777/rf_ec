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
## Screen rectangle covering a paste layer in the close-up camera.
func layer_rect(view: CanvasLayer, layer: MeshInstance3D) -> Rect2:
	var size: Vector2 = (layer.mesh as PlaneMesh).size
	var rect := Rect2(view.camera.unproject_position(layer.global_position), Vector2.ZERO)
	for corner in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5)]:
		rect = rect.expand(view.camera.unproject_position(layer.to_global(corner * Vector3(size.x, 0, size.y))))
	return rect
func press(view: CanvasLayer, at: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	view.view_input(down)
## Real pointer strokes through the close-up picker, in rows across the face.
func sweep(bench: Node3D, view: CanvasLayer, face: String, passes: int) -> void:
	var rect := layer_rect(view, bench.paste.faces[face].mesh)
	press(view, rect.get_center())
	for pass_index in range(passes):
		var y := rect.position.y
		while y <= rect.end.y:
			var x := rect.position.x
			while x <= rect.end.x:
				view.cleaning_pointer = Vector2(x, y)
				view.paste_under_pointer(0.05)
				x += 5.0
			y += 5.0
	bench.paste.end()
func squeeze_at(bench: Node3D, view: CanvasLayer, point: Vector2, seconds: float) -> void:
	press(view, point)
	var elapsed := 0.0
	while elapsed < seconds:
		view.cleaning_pointer = point
		view.paste_under_pointer(0.05)
		elapsed += 0.05
	bench.paste.end()
func switch_tool(bench: Node3D, id: String) -> void:
	bench.closeup.close()
	if bench.tools.equipped_tool != "": await bench.tools.return_tool()
	await bench.tools.equip(id)
func open_face(bench: Node3D, subject: Node3D, action: String) -> bool:
	var opened: bool = bench.open_service_view({"action": action, "target": subject})
	# The close-up viewport is laid out over the next frames.
	await process_frame
	await process_frame
	return opened
func total(values: PackedFloat32Array) -> float:
	var sum := 0.0
	for value in values: sum += value
	return sum
func clear_paste(paste: Node) -> void:
	for id in paste.faces:
		var zero := PackedFloat32Array()
		zero.resize(paste.N * paste.N)
		paste.faces[id].paste = zero
		paste.refresh(id)
## Deposits volume along cell-space segments, then presses it like a seated heatsink.
func pattern_quality(paste: Node, segments: Array, volume: float) -> Dictionary:
	clear_paste(paste)
	var points: Array[Vector2] = []
	for segment in segments:
		var steps: int = maxi(1, roundi(segment[0].distance_to(segment[1]) * 2.0))
		for step in range(steps + 1): points.append(segment[0].lerp(segment[1], step / float(steps)))
	for point in points:
		paste.squeeze("die", point, volume / (paste.SQUEEZE_RATE * points.size()))
	paste.seated = false
	var started := Time.get_ticks_usec()
	paste.seat()
	var result: Dictionary = paste.report.duplicate()
	result.quality = paste.quality
	result.ms = (Time.get_ticks_usec() - started) / 1000.0
	paste.lift()
	return result
func run() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	root.add_child(bench)
	await process_frame
	bench.camera_rig.set_physics_process(false)
	bench.camera_rig.body.position = Vector3(0, -4.35, 6.2)
	bench.camera_rig.update_camera()
	var paste: Node = bench.paste
	var view: CanvasLayer = bench.closeup
	var rules: RefCounted = bench.service_rules
	var cooler: Node3D = bench.asset_contract.objects["cooler-assembly"]
	paste.notice.connect(func(text: String): notices.append(text))
	expect(paste.dried and paste.contact_quality() < 0.2 and paste.seated, "Card did not start seated on dried paste")
	expect(bench.gpu.find_child("gpu-die", true, false).get_node_or_null("paste-die") == paste.faces.die.mesh, "Die paste layer is not carried by the die")
	expect(cooler.is_ancestor_of(paste.faces.heatsink.mesh), "Heatsink paste layer does not travel with the cooler")
	expect(paste.face_of(bench.gpu.find_child("gpu-die", true, false)) == "die" and paste.face_of(bench.gpu.find_child("heatsink-base", true, false)) == "heatsink",
		"A ray slipping through the layer onto its part lost the contact face")
	# Rules own reachability and tool choice.
	expect(not rules.check_surface("scrape", "die", [], "spudger").allowed, "Die was scrapable under a mounted heatsink")
	expect(not rules.check_surface("scrape", "die", ["cooler-assembly"], "ipa-wipe").allowed, "Wrong tool could scrape")
	expect(not rules.check_surface("apply", "heatsink", ["cooler-assembly"], "paste-syringe").allowed, "Paste could be applied to the heatsink base")
	expect(rules.check_surface("apply", "die", ["cooler-assembly"], "paste-syringe").allowed, "Exposed die refused fresh paste")
	var broken = preload("res://scripts/service_rules.gd").new(bench.asset_contract.service_parts, [], [{"id": "x", "exposedBy": "missing"}])
	expect(not broken.check_surface("scrape", "x", ["missing"], "spudger").allowed, "Malformed contact surface did not fail closed")
	# Tool roll now carries the paste kit; tools stay exclusive.
	await bench.tools.equip("spudger")
	expect(bench.tools.equipped_tool == "spudger", "Spudger could not be equipped")
	bench.tools.equip("paste-syringe")
	expect(bench.tools.equipped_tool == "spudger", "Two paste tools were equipped together")
	expect(await open_face(bench, bench.gpu, "gpu") and view.paste_face() == "", "Mounted heatsink exposed the die paste")
	view.close()
	await bench.tools.return_tool()
	expect(bench.service.debug_disassemble(), "Setup disassembly failed")
	expect(not paste.seated, "Detaching the heatsink did not lift the paste interface")
	# Dried die: the wipe only smears crust; the spudger lifts crust but leaves film.
	await bench.tools.equip("ipa-wipe")
	expect(await open_face(bench, bench.gpu, "gpu") and view.paste_face() == "die", "Exposed die was not framed for paste work")
	await capture("paste-die-dried")
	var crust_before: float = total(paste.faces.die.crust)
	sweep(bench, view, "die", 2)
	expect(is_equal_approx(total(paste.faces.die.crust), crust_before), "IPA wipe removed dried crust")
	expect(notices.any(func(text: String): return "Scrape it off" in text), "Wiping crust gave no scrape hint")
	await switch_tool(bench, "spudger")
	expect(await open_face(bench, bench.gpu, "gpu") and view.paste_face() == "die", "Spudger view lost the die")
	sweep(bench, view, "die", 4)
	expect(total(paste.faces.die.crust) < 0.02 * crust_before, "Spudger left crust on the die")
	expect(not paste.faces.die.clean and total(paste.faces.die.film) > 50.0, "Scraping alone removed the residue film")
	await capture("paste-die-scraped")
	await switch_tool(bench, "ipa-wipe")
	expect(await open_face(bench, bench.gpu, "gpu"), "Wipe view did not reopen")
	sweep(bench, view, "die", 4)
	expect(paste.faces.die.clean and paste.face_progress("die") >= 0.99, "Wiping did not finish the die")
	expect(notices.any(func(text: String): return "die clean" in text.to_lower()), "Clean die gave no completion notice")
	await capture("paste-die-clean")
	# The heatsink base needs the same two stages.
	await switch_tool(bench, "spudger")
	expect(await open_face(bench, cooler, "assembly") and view.paste_face() == "heatsink", "Detached heatsink base was not framed")
	await capture("paste-heatsink-dried")
	sweep(bench, view, "heatsink", 4)
	await switch_tool(bench, "ipa-wipe")
	expect(await open_face(bench, cooler, "assembly"), "Heatsink wipe view did not open")
	sweep(bench, view, "heatsink", 4)
	expect(paste.faces.heatsink.clean, "Heatsink base could not be cleaned")
	# Fresh paste: a held squeeze grows a bead on the die.
	await switch_tool(bench, "paste-syringe")
	expect(await open_face(bench, bench.gpu, "gpu") and view.paste_face() == "die", "Syringe view lost the die")
	var die_layer: MeshInstance3D = paste.faces.die.mesh
	squeeze_at(bench, view, view.camera.unproject_position(die_layer.global_position), 1.5)
	var bead: float = paste.paste_volume()
	expect(bead > 0.3 * paste.IDEAL_VOLUME and bead < 0.5 * paste.IDEAL_VOLUME, "Squeeze rate did not build a bead (%.1f)" % bead)
	squeeze_at(bench, view, view.camera.unproject_position(die_layer.global_position), 2.2)
	expect(absf(paste.paste_volume() - paste.IDEAL_VOLUME) < 0.1 * paste.IDEAL_VOLUME, "Held squeeze did not reach a full dot")
	await capture("paste-die-dot")
	view.close()
	await bench.tools.return_tool()
	# Seat, then lift again to read the imprint.
	notices.clear()
	expect(bench.service.refit_assembly(), "Heatsink refit was refused")
	await create_timer(0.6).timeout
	expect(paste.seated and paste.report.has("coverage"), "Seating did not spread the paste")
	var dot_quality: float = paste.quality
	expect(dot_quality > 0.6 and dot_quality < 0.97, "Single dot contact out of range (%.2f)" % dot_quality)
	expect(is_equal_approx(bench.thermal.paste_load(), 1.0 - dot_quality), "Thermal model ignores the spread paste")
	expect(notices.any(func(text: String): return "pressed across" in text), "Seating gave no spread report")
	expect(bench.service.lift_assembly("cooler-assembly"), "Could not lift the heatsink for an imprint check")
	await create_timer(0.6).timeout
	expect(notices.any(func(text: String): return "imprint shows" in text), "Lift did not report the paste imprint")
	expect(total(paste.faces.heatsink.paste) > 0.3 * paste.IDEAL_VOLUME, "Lift left no imprint on the heatsink base")
	await bench.tools.equip("paste-syringe")
	bench.closeup.show_view("service", cooler)
	await capture("paste-imprint-heatsink")
	view.close()
	bench.service.place_assembly(Vector3(-2, 0.0, -4), bench.placement_obstacles("cooler-assembly"))
	await create_timer(0.6).timeout
	expect(await open_face(bench, bench.gpu, "gpu"), "Die imprint view did not open")
	await capture("paste-imprint-die")
	view.close()
	# Pattern physics: an X of the same volume reaches the corners a dot misses.
	var middle: float = paste.N * 0.5
	var low: float = paste.MARGIN + 1.5
	var high: float = paste.N - paste.MARGIN - 1.5
	var dot := pattern_quality(paste, [[Vector2(middle, middle), Vector2(middle, middle)]], paste.IDEAL_VOLUME)
	var cross := pattern_quality(paste, [[Vector2(low, low), Vector2(high, high)], [Vector2(high, low), Vector2(low, high)]], paste.IDEAL_VOLUME)
	var scant := pattern_quality(paste, [[Vector2(middle, middle), Vector2(middle, middle)]], paste.IDEAL_VOLUME * 0.35)
	var flood := pattern_quality(paste, [[Vector2(middle, middle), Vector2(middle, middle)]], paste.IDEAL_VOLUME * 2.2)
	print("paste patterns: dot %.2f/%.2f  X %.2f/%.2f  scant %.2f  flood %.2f overflow %.0f  spread %.0f ms" % [
		dot.quality, dot.coverage, cross.quality, cross.coverage, scant.quality, flood.quality, flood.overflow, cross.ms])
	expect(cross.coverage > dot.coverage and cross.quality > 0.9, "X pattern did not out-cover a dot of equal volume")
	expect(scant.quality < 0.5, "Too little paste still gave good contact")
	expect(flood.quality > 0.95 and flood.overflow > 0.12 * paste.IDEAL_VOLUME, "Excess paste did not squeeze onto the package")
	expect(cross.ms < 400.0, "Paste spread is too slow for a seating animation (%.0f ms)" % cross.ms)
	# No paste at all is worse than dried paste.
	clear_paste(paste)
	notices.clear()
	paste.seated = false
	paste.seat()
	expect(paste.quality < 0.02 and notices.any(func(text: String): return "no thermal paste" in text), "Bare die seated without a warning")
	paste.lift()
	expect(paste.debug_dry() and paste.dried and paste.contact_quality() < 0.2, "Debug dry did not restore old paste")
	bench.queue_free()
	await process_frame
	print("PASS: paste reach rules, tool kit, scrape/wipe stages, squeeze bead, seat spread, lift imprint and pattern coverage" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
