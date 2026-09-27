extends SceneTree
var failures: Array[String] = []
func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func _initialize() -> void: call_deferred("run")
func states(bench: Node3D) -> Dictionary:
	var result := {}
	for entry in preload("res://scripts/repair_status.gd").rows(bench): result[entry.label] = entry.state
	return result
func run() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	bench.get_node("CameraRig").legacy_test_mode = true
	root.add_child(bench)
	await process_frame
	# A fresh job: every fault is red, the card is assembled and off the board.
	var fresh := states(bench)
	expect(fresh == {"Dust": "fault", "Thermal paste": "fault", "Fan bearing": "fault", "Assembly": "done", "Test run": "info"},
		"Fresh card status was %s" % fresh)
	expect(bench.testing_station.attach(), "Card could not attach for a test run")
	await create_timer(0.6).timeout
	bench.thermal.advance(6)
	expect(states(bench)["Test run"] == "fault", "Throttling, erroring test run was not red")
	# Partial work turns rows yellow.
	for surface in bench.cleaning.surfaces: surface.remaining = surface.mass * 0.5
	expect(states(bench)["Dust"] == "partial", "Half-cleaned card was not in progress")
	# Every fix done: all green.
	bench.debug_clean_gpu()
	expect(bench.paste.debug_repaste(), "Debug repaste was refused")
	expect(bench.bearing.debug_oil(), "Debug oil was refused")
	bench.thermal.advance(6)
	var fixed := states(bench)
	expect(fixed.values().all(func(state: String): return state == "done"), "Repaired card was not all green: %s" % fixed)
	# Pulling the card apart shows the reassembly still owed.
	expect(bench.testing_station.detach(), "Card could not leave the test board")
	await create_timer(0.6).timeout
	expect(bench.service.debug_disassemble(), "Debug disassembly failed")
	var apart := states(bench)
	expect(apart["Assembly"] == "partial" and apart["Thermal paste"] == "partial" and apart["Test run"] == "info",
		"Disassembled card status was %s" % apart)
	# The overlay draws one coloured row per entry.
	var rows: Array[Dictionary] = preload("res://scripts/repair_status.gd").rows(bench)
	bench.hud.refresh_repair_status(rows)
	expect(bench.hud.repair_rows.get_child_count() == rows.size(), "Overlay row count does not match the status")
	expect((bench.hud.repair_rows.get_child(0).get_child(0) as ColorRect).color == Color("#5ec46f"), "Clean dust row was not green")
	expect("broken" in bench.hud.repair_summary.text, "Overlay summary is missing")
	expect(bench.hud.repair_toggle.visible == OS.is_debug_build(), "Overlay toggle is not limited to debug builds")
	bench.queue_free()
	await process_frame
	print("PASS: repair status rows for fresh, partial, repaired and disassembled cards, and overlay rendering" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
