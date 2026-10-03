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
## Also captures the face from a low angle, where the relief and cut edges show.
func capture_angled(view: CanvasLayer, name: String) -> void:
	await capture(name)
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	var facing: Vector3 = view.direction
	var side := facing.cross(Vector3.UP if absf(facing.y) < 0.9 else Vector3.RIGHT).normalized()
	view.direction = (facing * 0.32 + side).normalized()
	view.zoom = 0.75
	view.update_camera()
	await process_frame
	await capture(name + "-angle")
	view.direction = facing
	view.zoom = 1.0
	view.update_camera()
func press(view: CanvasLayer, at: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	view.view_input(down)
## Real pointer strokes through the close-up picker, in rows across the face.
func sweep(bench: Node3D, view: CanvasLayer, face: String, passes: int, portion := 1.0) -> void:
	var rect := layer_rect(view, bench.paste.faces[face].mesh)
	press(view, rect.get_center())
	for pass_index in range(passes):
		var y := rect.position.y
		while y <= rect.end.y:
			var x := rect.position.x
			while x <= rect.position.x + rect.size.x * portion:
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
## Points the close-up pointer at a view position; rendered runs also move the real cursor
## there, since the view follows the mouse every frame.
func hover(view: CanvasLayer, at: Vector2) -> void:
	view.cleaning_pointer = at
	if DisplayServer.get_name() != "headless":
		Input.warp_mouse(view.surface.get_viewport().get_screen_transform() * (view.surface.get_global_transform_with_canvas() * at))
func total(values: PackedFloat32Array) -> float:
	var sum := 0.0
	for value in values: sum += value
	return sum
## Mean dried stack over die cells within a rim band (0 centre, 1 die edge), skipping bare cells.
func band_mean(paste: Node, face: Dictionary, low: float, high: float, layer: String = "") -> float:
	var sum := 0.0
	var count := 0
	for k in range(paste.N * paste.N):
		var i: int = k % paste.N
		var j: int = k / paste.N
		if not paste.is_inner(i, j): continue
		var stack: float = paste.dried_stack(face, k)
		if stack <= 0.0: continue
		var rim := maxf(absf((i - paste.MARGIN + 0.5) / paste.INNER * 2.0 - 1.0), absf((j - paste.MARGIN + 0.5) / paste.INNER * 2.0 - 1.0))
		if rim < low or rim >= high: continue
		sum += stack if layer == "" else face[layer][k] / stack
		count += 1
	return sum / maxf(count, 1)
## Old compound is uneven and layered, chips from exposed edges and smears its pasty base.
func check_layers(paste: Node) -> void:
	var die: Dictionary = paste.faces.die
	var stacks: Array[float] = []
	for k in range(paste.N * paste.N):
		if paste.is_inner(k % paste.N, k / paste.N) and paste.dried_stack(die, k) > 0.0: stacks.append(paste.dried_stack(die, k))
	var mean: float = stacks.reduce(func(sum, value): return sum + value, 0.0) / stacks.size()
	var variance: float = stacks.reduce(func(sum, value): return sum + (value - mean) * (value - mean), 0.0) / stacks.size()
	print("dried die stack: mean %.2f, spread %.2f, min %.2f, max %.2f" % [mean, sqrt(variance), stacks.min(), stacks.max()])
	expect(sqrt(variance) / mean > 0.3, "Old paste is still a near-uniform layer")
	expect(band_mean(paste, die, 0.65, 1.0) > 1.3 * band_mean(paste, die, 0.0, 0.4), "Pump-out left no ridge toward the die edges")
	expect(band_mean(paste, die, 0.0, 0.4, "gum") > band_mean(paste, die, 0.7, 1.0, "gum") + 0.15, "The middle is not pastier than the dried rim")
	expect(band_mean(paste, die, 0.7, 1.0, "glaze") > band_mean(paste, die, 0.0, 0.4, "glaze"), "The rim did not dry harder than the middle")
	var sink_stack := 0.0
	for k in range(paste.N * paste.N): sink_stack += paste.dried_stack(paste.faces.heatsink, k)
	expect(sink_stack > 0.2 * stacks.reduce(func(sum, value): return sum + value, 0.0), "Lifting tore no old paste onto the heatsink base")
	var size: int = paste.N * paste.N
	var zero := PackedFloat32Array()
	zero.resize(size)
	var sheet := PackedFloat32Array()
	sheet.resize(size)
	sheet.fill(0.3)
	var middle: int = paste.N / 2
	var c: int = middle * paste.N + middle
	var at := Vector2(middle + 0.5, middle + 0.5)
	# Glaze chips far faster once the blade is under an exposed edge, and protects the crust.
	for layer in ["crust", "gum", "film", "paste"]: die[layer] = zero.duplicate()
	die.glaze = sheet.duplicate()
	die.crust = sheet.duplicate()
	paste.scrape("die", at, 0.02)
	var intact: float = 0.3 - die.glaze[c]
	expect(intact > 0.0 and is_equal_approx(die.crust[c], 0.3), "The blade reached the crust through intact glaze")
	die.glaze = sheet.duplicate()
	die.glaze[c + 1] = 0.0
	paste.scrape("die", at, 0.02)
	expect(0.3 - die.glaze[c] > 3.0 * intact, "Glaze beside a gap did not chip faster")
	# Pasty gum is ploughed ahead of a moving blade, not just lifted.
	die.glaze = zero.duplicate()
	die.crust = zero.duplicate()
	die.gum = sheet.duplicate()
	var row := 14
	paste.scrape("die", Vector2(10.5, row + 0.5), 0.05, Vector2(1, 0))
	expect(die.gum[row * paste.N + 13] > 0.3 and is_equal_approx(die.gum[row * paste.N + 7], 0.3), "Gum was not pushed ahead of the blade")
	var gum_total := 0.0
	for value in die.gum: gum_total += value
	expect(gum_total < 0.3 * size and gum_total > 0.3 * size - 0.05 * 13 * 1.8, "Smearing lost or created gum")
	paste.reset_dried()
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
	check_layers(paste)
	expect(paste.dried and paste.contact_quality() < 0.2, "Layer checks did not restore the dried paste")
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
	await capture_angled(view, "paste-die-dried")
	var hard_before: float = total(paste.faces.die.glaze) + total(paste.faces.die.crust)
	var gum_before: float = total(paste.faces.die.gum)
	sweep(bench, view, "die", 2)
	expect(is_equal_approx(total(paste.faces.die.glaze) + total(paste.faces.die.crust), hard_before), "IPA wipe removed dried glaze or crust")
	expect(notices.any(func(text: String): return "Scrape it off" in text), "Wiping crust gave no scrape hint")
	await switch_tool(bench, "spudger")
	expect(await open_face(bench, bench.gpu, "gpu") and view.paste_face() == "die", "Spudger view lost the die")
	# A brief scrape on the thickest spot only gets partway down the stack; it takes time.
	var die_face: Dictionary = paste.faces.die
	var thickest := 0
	for k in range(paste.N * paste.N):
		if paste.dried_stack(die_face, k) > paste.dried_stack(die_face, thickest): thickest = k
	var stack_before: float = paste.dried_stack(die_face, thickest)
	var die_mesh: MeshInstance3D = die_face.mesh
	var die_size: Vector2 = (die_mesh.mesh as PlaneMesh).size
	var spot := die_mesh.to_global(Vector3(((thickest % paste.N + 0.5) / paste.N - 0.5) * die_size.x, 0.0,
		((thickest / paste.N + 0.5) / paste.N - 0.5) * die_size.y))
	squeeze_at(bench, view, view.camera.unproject_position(spot), 0.1)
	var stack_after: float = paste.dried_stack(die_face, thickest)
	print("die scrape: thickest cell %.2f -> %.2f after 0.1 s" % [stack_before, stack_after])
	expect(stack_after < stack_before and stack_after > 0.25 * stack_before, "A brief scrape did not take the stack partway down")
	var crumbs := [0]
	var clumps := [0]
	paste.shed.connect(func(_point, _normal, _direction, count: int, color: Color, _size):
		if color == paste.CRUMB_COLOR: crumbs[0] += count
		else: clumps[0] += count)
	var voice: AudioStreamPlayer = paste.scrape_sound
	voice.report_age = 1.0
	sweep(bench, view, "die", 1, 0.5)
	# The scrape loop (a supplied recording) is driven by contact; the blade picks up compound.
	expect(voice.report_age == 0.0 and voice.target > 0.0 and paste.blade_load > 0.0, "Scraping reported no contact to its sound or blade")
	expect(voice.stream != null or not ResourceLoader.exists(paste.SCRAPE_RECORDING), "The supplied scrape recording was not loaded")
	# Aim, then lock: circling near the press point turns the blade freely; once the pointer
	# travels away the heading holds until release. It may curve, but never turns around.
	paste.begin()
	paste.press_cell = Vector2(10, 10)
	paste.steer(Vector2(11, 10), Vector2(1, 0))
	paste.steer(Vector2(9, 10.2), Vector2(-2, 0.2))
	expect(paste.aiming and paste.stroke_dir.x < -0.9, "Circling near the press point did not turn the blade")
	paste.steer(Vector2(10, 13.5), Vector2(1, 3.3))
	expect(not paste.aiming and paste.stroke_dir.y > 0.9, "Moving away did not lock the aimed heading")
	paste.steer(Vector2(10, 12.5), Vector2(0, -1))
	expect(paste.stroke_dir.y > 0.9, "Moving back reversed the locked stroke")
	paste.steer(Vector2(11, 13.5), Vector2(1, 1))
	expect(paste.stroke_dir.x > 0.0 and paste.stroke_dir.y > 0.0, "A curving stroke did not bend its heading")
	paste.end()
	paste.begin()
	expect(paste.stroke_dir == Vector2.ZERO and paste.aiming, "A new press kept the last stroke's heading")
	paste.end()
	# The blade is seen riding the face, pressed and tilted low, with compound on its edge.
	var rect := layer_rect(view, paste.faces.die.mesh)
	press(view, rect.get_center())
	hover(view, rect.get_center() + Vector2(rect.size.x * 0.15, 0))
	for frame in range(4): view.place_work_tool(0.1)
	var blade: Node3D = view.work_tools["spudger"]
	var cell: float = paste.cell_size(paste.faces.die.mesh)
	expect(blade.visible and blade.global_position.distance_to(paste.faces.die.mesh.global_position) < cell * 20.0 and view.tool_press > 0.9,
		"The spudger was not shown pressed on the die")
	await capture_angled(view, "paste-die-half-scraped")
	paste.end()
	sweep(bench, view, "die", 6)
	expect(crumbs[0] > 0 and clumps[0] > 0, "Scraping shed no crumbs or clumps (%d, %d)" % [crumbs[0], clumps[0]])
	expect(total(paste.faces.die.glaze) + total(paste.faces.die.crust) < 0.02 * hard_before, "Spudger left glaze or crust on the die")
	expect(total(paste.faces.die.gum) < 0.35 * gum_before, "Spudger did not plough off the pasty gum")
	expect(not paste.faces.die.clean and total(paste.faces.die.film) > 50.0, "Scraping alone removed the residue film")
	await capture("paste-die-scraped")
	await switch_tool(bench, "ipa-wipe")
	expect(await open_face(bench, bench.gpu, "gpu"), "Wipe view did not reopen")
	sweep(bench, view, "die", 6)
	expect(paste.faces.die.clean and paste.face_progress("die") >= 0.99, "Wiping did not finish the die")
	# The pad greys with what it lifted, and its loop is driven by contact.
	var wipe_voice: AudioStreamPlayer = paste.wipe_sound
	expect(paste.pad_soil > 0.3 and wipe_voice.target > 0.0, "The IPA pad did not soil or report contact (soil %.2f)" % paste.pad_soil)
	var pad_rect := layer_rect(view, paste.faces.die.mesh)
	press(view, pad_rect.get_center())
	hover(view, pad_rect.get_center())
	for frame in range(4): view.place_work_tool(0.1)
	expect(view.work_tools["ipa-wipe"].visible and not view.work_tools["spudger"].visible and view.pad_material.albedo_color.v < 0.85,
		"The soiled IPA pad was not shown on the die")
	await capture("paste-wipe-at-work")
	paste.end()
	expect(notices.any(func(text: String): return "die clean" in text.to_lower()), "Clean die gave no completion notice")
	await capture("paste-die-clean")
	# The heatsink base needs the same two stages.
	await switch_tool(bench, "spudger")
	expect(await open_face(bench, cooler, "assembly") and view.paste_face() == "heatsink", "Detached heatsink base was not framed")
	await capture("paste-heatsink-dried")
	sweep(bench, view, "heatsink", 7)
	await switch_tool(bench, "ipa-wipe")
	expect(await open_face(bench, cooler, "assembly"), "Heatsink wipe view did not open")
	sweep(bench, view, "heatsink", 6)
	expect(paste.faces.heatsink.clean, "Heatsink base could not be cleaned")
	# Fresh paste: a held squeeze grows a bead on the die.
	await switch_tool(bench, "paste-syringe")
	expect(await open_face(bench, bench.gpu, "gpu") and view.paste_face() == "die", "Syringe view lost the die")
	var die_layer: MeshInstance3D = paste.faces.die.mesh
	squeeze_at(bench, view, view.camera.unproject_position(die_layer.global_position), 1.5)
	var bead: float = paste.paste_volume()
	expect(paste.squeeze_sound.stream != null and paste.squeeze_sound.target > 0.0,
		"The held squeeze did not drive its toothpaste loop")
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
	# The audio server drops a sound still playing at free only a few frames later; quitting
	# sooner reports its stream as leaked at exit.
	for frame in range(10): await process_frame
	print("PASS: paste reach rules, tool kit, scrape/wipe stages, squeeze bead, seat spread, lift imprint and pattern coverage" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
