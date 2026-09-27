extends SceneTree
var failures: Array[String] = []
func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func _initialize() -> void: call_deferred("run")
func key(bench: Node3D, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	# The close-up owns keys while it is open; otherwise first-person play does.
	if bench.closeup.mode != "": bench.closeup._input(event)
	else: bench.first_person_input(event)
func settle(bench: Node3D) -> void:
	for step in range(90):
		await process_frame
		if not bench.tool_selection_busy and not bench.tools.busy and not bench.inspection.moving: return
func run() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	root.add_child(bench)
	await process_frame
	var toolbox: Node3D = bench.get_node("RepairDesk/Toolbox")
	# Stand well away from the toolbox: clicking the roll would be out of reach, T still works.
	bench.camera_rig.body.global_position.x = toolbox.global_position.x - 9.0
	bench.camera_rig.update_camera()
	bench.camera_rig.set_captured(true)
	expect(not bench.near_node(toolbox), "Test setup is still within reach of the toolbox")
	key(bench, KEY_T)
	expect(bench.tool_menu_open and bench.closeup.mode == "bag", "T did not open the tool bag away from the toolbox")
	# The roll finishes unrolling before it can close again.
	await settle(bench)
	key(bench, KEY_T)
	await settle(bench)
	expect(not bench.tool_menu_open and bench.closeup.mode == "", "T did not close the tool bag")
	# From inside a part's close-up: pick a tool and land back on the same part.
	bench.inspection.lift()
	await settle(bench)
	bench.closeup.show_view("service", bench.gpu)
	key(bench, KEY_T)
	expect(bench.closeup.mode == "bag" and bench.focus_return == bench.gpu, "T in a close-up did not open the bag for that part")
	await settle(bench)
	await bench.select_tool("spudger")
	await settle(bench)
	expect(bench.tools.equipped_tool == "spudger", "Choosing a tool from the bag did not equip it")
	expect(bench.closeup.mode == "service" and bench.closeup.subject == bench.gpu, "The close-up did not return to the same part")
	expect(bench.inspection.held, "Swapping tools dropped the held card")
	# Swapping again returns the old tool first, still without leaving the job.
	key(bench, KEY_T)
	await settle(bench)
	await bench.select_tool("ipa-wipe")
	await settle(bench)
	expect(bench.tools.equipped_tool == "ipa-wipe" and bench.tools.tool_location("spudger") == "toolbox", "Swap did not return the previous tool")
	expect(bench.closeup.mode == "service" and bench.closeup.subject == bench.gpu, "Second swap lost the close-up")
	# Empty hands is a choice in the bag too.
	key(bench, KEY_T)
	await settle(bench)
	await bench.select_tool("")
	await settle(bench)
	expect(bench.tools.equipped_tool == "" and bench.closeup.mode == "service", "Choosing empty hands did not return to the close-up")
	bench.closeup.close()
	bench.queue_free()
	await process_frame
	print("PASS: T opens the tool bag anywhere, swaps tools while holding a part and returns to the same close-up" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
