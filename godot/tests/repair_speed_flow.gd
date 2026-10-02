extends SceneTree
var failures: Array[String] = []
func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func _initialize() -> void: call_deferred("run")
func sum_grid(values: PackedFloat32Array) -> float:
	var total := 0.0
	for value in values: total += value
	return total
func prepare_paste(paste: Node, layer: String) -> void:
	var face: Dictionary = paste.faces.die
	for key in ["glaze", "crust", "gum", "film", "paste"]:
		var grid := PackedFloat32Array()
		grid.resize(paste.N * paste.N)
		grid.fill(1.0 if key == layer else 0.0)
		face[key] = grid
func run() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	root.add_child(bench)
	await process_frame
	var hud: CanvasLayer = bench.hud
	# Isolated settings: never overwrite the player's tuned values.
	hud.repair_speed_settings_path = "res://build/repair-speed-test.cfg"
	bench.camera_rig.set_captured(false)
	hud.set_menu_open(true)
	expect(not hud.repair_speed_panel.is_visible_in_tree(), "Repair speeds should start collapsed")
	hud.menu_section_buttons.speeds.button_pressed = true
	await process_frame
	await process_frame
	await process_frame
	expect(hud.repair_speed_panel.is_visible_in_tree(), "Escape menu did not expose debug repair speeds")
	var screen := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	expect(screen.encloses(hud.repair_speed_panel.get_global_rect()), "Repair speed controls extend outside the window")
	expect(hud.repair_speed_sliders.size() == 3, "Expected dust, IPA and scraping controls")
	for slider in hud.repair_speed_sliders.values():
		expect(slider.value == 1.0 and slider.focus_mode == Control.FOCUS_NONE, "Fixture did not start at baseline with mouse-only sliders")
	hud.repair_speed_sliders.scrape.value = 4.0
	expect(bench.paste.debug_scrape_speed == 4.0 and hud.repair_speed_values.scrape.text == "4.0x", "Scraping slider did not apply live")
	# Same crust, same stroke duration: four times the material removed.
	var paste: Node = bench.paste
	var cell := Vector2(paste.N * 0.5, paste.N * 0.5)
	prepare_paste(paste, "crust")
	var initial: float = sum_grid(paste.faces.die.crust)
	hud.set_repair_speed("scrape", 1.0)
	paste.scrape("die", cell, 0.01)
	var baseline: float = initial - sum_grid(paste.faces.die.crust)
	prepare_paste(paste, "crust")
	hud.set_repair_speed("scrape", 4.0)
	paste.scrape("die", cell, 0.01)
	var faster: float = initial - sum_grid(paste.faces.die.crust)
	expect(baseline > 0.0 and absf(faster / baseline - 4.0) < 0.01, "Scrape multiplier did not change removed material by 4x")
	prepare_paste(paste, "film")
	hud.set_repair_speed("wipe", 1.0)
	paste.wipe("die", cell, 0.01)
	baseline = initial - sum_grid(paste.faces.die.film)
	prepare_paste(paste, "film")
	hud.repair_speed_sliders.wipe.value = 3.0
	paste.wipe("die", cell, 0.01)
	faster = initial - sum_grid(paste.faces.die.film)
	expect(baseline > 0.0 and absf(faster / baseline - 3.0) < 0.01, "IPA multiplier did not change film removal by 3x")
	expect(bench.bearing.debug_wipe_speed == 3.0, "IPA multiplier did not reach fan shaft wiping")
	# Wiping still cannot bypass the crust, even at maximum speed.
	prepare_paste(paste, "crust")
	var film: PackedFloat32Array = paste.faces.die.film
	film.fill(1.0)
	paste.faces.die.film = film
	hud.set_repair_speed("wipe", 20.0)
	expect(not paste.wipe("die", cell, 1.0) and sum_grid(paste.faces.die.film) == initial, "IPA speed bypassed the scrape-first rule")
	# The shaft uses the same multiplier, without changing oil-drop timing.
	var bearing: Node = bench.bearing
	bearing.gunk.fill(1.0)
	bearing.initial_gunk = bearing.ROWS
	bearing.shaft_clean = false
	hud.set_repair_speed("wipe", 1.0)
	bearing.wipe(Vector3.ZERO, 0.01)
	baseline = bearing.ROWS - bearing.total_gunk()
	bearing.gunk.fill(1.0)
	hud.set_repair_speed("wipe", 3.0)
	bearing.wipe(Vector3.ZERO, 0.01)
	faster = bearing.ROWS - bearing.total_gunk()
	expect(baseline > 0.0 and absf(faster / baseline - 3.0) < 0.01, "IPA multiplier did not change shaft removal by 3x")
	# Exercise the actual mask remover shared by both blowers, allowing byte rounding.
	var cleaning: Node = bench.cleaning
	var surface: Dictionary = cleaning.surfaces[0]
	var data: PackedByteArray = surface.data
	data.fill(120)
	surface.data = data
	surface.remaining = surface.mass
	var point: Vector3 = surface.mesh.to_global(surface.bounds.get_center())
	hud.set_repair_speed("dust", 1.0)
	baseline = cleaning.clean_at(surface.mesh, point, Vector3.UP, 0.02, 0.2)
	data.fill(120)
	surface.data = data
	surface.remaining = surface.mass
	hud.repair_speed_sliders.dust.value = 4.0
	faster = cleaning.clean_at(surface.mesh, point, Vector3.UP, 0.02, 0.2)
	expect(baseline > 0.0 and absf(faster / baseline - 4.0) < 0.1, "Dust multiplier did not speed up actual mask removal")
	# Persistence and reset are driven by the menu controls.
	hud.save_repair_speeds()
	hud.set_repair_speed("dust", 1.0)
	hud.set_repair_speed("wipe", 1.0)
	hud.set_repair_speed("scrape", 1.0)
	hud.load_repair_speeds()
	expect(cleaning.debug_clear_speed == 4.0 and paste.debug_wipe_speed == 3.0 and paste.debug_scrape_speed == 4.0, "Saved tuning did not restore all rates")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/repair-speeds.png")
	hud.repair_speed_reset.pressed.emit()
	expect(cleaning.debug_clear_speed == 1.0 and paste.debug_wipe_speed == 1.0 and paste.debug_scrape_speed == 1.0 and bearing.debug_wipe_speed == 1.0, "Reset did not restore every authored rate")
	hud.set_menu_open(false)
	expect(not hud.repair_speed_panel.is_visible_in_tree(), "Speed controls remained visible during play")
	DirAccess.remove_absolute(hud.repair_speed_settings_path)
	bench.queue_free()
	await process_frame
	print("PASS: debug repair speed UI, live dust/scrape/IPA removal, crust guard, shaft wiping, persistence and reset" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
