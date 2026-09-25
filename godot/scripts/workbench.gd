extends Node3D

const Contract = preload("res://scripts/asset_contract.gd")
const Rules = preload("res://scripts/service_rules.gd")
const Picker = preload("res://scripts/interaction_picker.gd")
@onready var camera_rig = $CameraRig
@onready var inspection = $Inspection
@onready var tools = $Tools
@onready var service = $Service
@onready var cleaning = $Cleaning
@onready var gpu: Node3D = $GPUAsset
@onready var testing_desk: Node3D = $TestingDesk
@onready var test_monitor: Node3D = $TestMonitor
@onready var testing_station: Node = $TestingStation
@onready var hud: CanvasLayer = $HUD
var asset_contract: Dictionary
var service_rules: RefCounted
var picker: RefCounted
var dragging_button := 0
var press_position := Vector2.ZERO
var dragged := false
var service_press := false
var jaws: Array[Node3D] = []
var hover_elapsed := 0.0

func _ready() -> void:
	gpu.name = "gpu"
	asset_contract = Contract.bind_parts(gpu)
	service_rules = Rules.new(asset_contract.service_parts,
		[{"assembly": "cooler-assembly", "fastenersRequire": ["fan-plug"]}])
	if not asset_contract.errors.is_empty() or not service_rules.errors.is_empty():
		var message := "Asset setup failed: " + str(asset_contract.errors + service_rules.errors)
		push_error(message)
		hud.set_status(message)
		set_process(false)
		set_process_unhandled_input(false)
		return
	var floor_node := testing_desk.find_child("floor", true, false)
	if floor_node:
		floor_node.get_parent().remove_child(floor_node)
		floor_node.queue_free()
	var tabletop := testing_desk.find_child("desk-top", true, false) as MeshInstance3D
	if tabletop == null:
		push_error("Testing desk is missing desk-top")
		return
	var table_bounds: AABB = tabletop.global_transform * tabletop.get_aabb()
	testing_desk.position += Vector3(12.5 - table_bounds.position.x, -table_bounds.end.y, -table_bounds.get_center().z)
	table_bounds = tabletop.global_transform * tabletop.get_aabb()
	camera_rig.testing_target = table_bounds.get_center() + Vector3(0, 1.2, 0)
	camera_rig.select_view("repair")
	inspection.configure(gpu, camera_rig.camera, Contract.bounds_in(gpu))
	inspection.can_interact = func(): return not service.busy and service.held_part == "" and not tools.busy and not testing_station.installed and not testing_station.moving
	tools.configure($RepairDesk/Toolbox, camera_rig.camera, self,
		func(id: String): return not service.busy and not inspection.moving and (service.held_part == "" or id in ["dev-blower", "toolbox"]))
	service.configure(asset_contract, service_rules, self, camera_rig.camera,
		func(): return not tools.busy and not inspection.moving and not testing_station.installed and not testing_station.moving,
		func(): return tools.equipped_tool)
	for node in $RepairDesk.find_children("Jaw*", "Node3D", true, false):
		jaws.append(node)
		node.set_meta("home_z", node.position.z)
	$RepairDesk/Tabletop.set_meta("action", "desk")
	$RepairDesk/Mat.set_meta("action", "desk")
	for node in $RepairDesk.get_children():
		if String(node.name).begins_with("Grid") or String(node.name).begins_with("MatPocket"):
			node.set_meta("action", "desk")
	testing_station.configure(gpu, testing_desk.find_child("gpu-testing-board", true, false), test_monitor,
		inspection, service, tools, cleaning)
	picker = Picker.new()
	picker.configure(self, gpu, camera_rig.camera, service)
	cleaning.configure(gpu, picker, tools)
	hud.view_requested.connect(select_view)
	hud.test_requested.connect(toggle_test_gpu)
	hud.inspect_requested.connect(toggle_inspection)
	hud.flip_requested.connect(inspection.flip)
	hud.toolbox_requested.connect(tools.toggle_box)
	hud.equip_requested.connect(tools.equip)
	hud.dev_blower_requested.connect(func(): tools.equip("dev-blower"))
	hud.highlight_dust_requested.connect(cleaning.toggle_highlight)
	hud.debug_clean_requested.connect(debug_clean_gpu)
	hud.debug_disassemble_requested.connect(debug_disassemble_gpu)
	hud.return_requested.connect(tools.return_tool)
	hud.cable_requested.connect(service.toggle_cable)
	hud.assembly_requested.connect(lift_assembly)
	hud.assembly_refit_requested.connect(refit_assembly)
	hud.assembly_store_requested.connect(service.store_assembly)
	hud.refit_started.connect(begin_refit)
	hud.refit_ended.connect(func():
		service.end_screw()
		hud.refresh(inspection.held, inspection.moving, tools, service, cleaning, testing_station))
	hud.mute_requested.connect(func():
		service.set_muted(not service.muted)
		cleaning.set_muted(service.muted)
		testing_station.set_muted(service.muted)
		test_monitor.set_muted(service.muted))
	inspection.changed.connect(refresh_ui)
	tools.changed.connect(refresh_ui)
	service.changed.connect(refresh_ui)
	cleaning.changed.connect(func(): hud.refresh_cleaning(cleaning))
	testing_station.changed.connect(refresh_ui)
	test_monitor.changed.connect(refresh_ui)
	tools.notice.connect(hud.set_status)
	service.notice.connect(hud.set_status)
	cleaning.notice.connect(hud.set_status)
	testing_station.notice.connect(hud.set_status)
	test_monitor.notice.connect(hud.set_status)
	refresh_ui()

func ready_for_action() -> bool:
	return not inspection.moving and not tools.busy and not service.busy and not testing_station.moving

func select_view(view: String) -> void:
	if inspection.held or service.held_part != "" or not ready_for_action(): return
	camera_rig.select_view(view)
	hud.set_testing_mode(view == "testing")
	refresh_ui()

func toggle_test_gpu() -> void:
	if not ready_for_action(): return
	var was_installed: bool = testing_station.installed
	if testing_station.toggle_gpu():
		camera_rig.select_view("repair" if was_installed else "testing")
		hud.set_testing_mode(not was_installed)

func debug_clean_gpu() -> void:
	if not OS.is_debug_build(): return
	if cleaning.debug_clean() and testing_station.installed:
		test_monitor.set_connection(true, cleaning.progress)

func debug_disassemble_gpu() -> void:
	if not OS.is_debug_build() or not ready_for_action() or inspection.held or testing_station.installed: return
	cleaning.end()
	if service.debug_disassemble():
		camera_rig.select_view("repair")
		hud.set_testing_mode(false)
		refresh_ui()

func toggle_inspection() -> void:
	if service.held_part != "": return
	if inspection.held: inspection.put_down()
	else: inspection.lift()

func lift_assembly(id: String) -> void:
	if not ready_for_action() or service.held_part != "": return
	if inspection.held:
		inspection.put_down()
		if inspection.moving: await inspection.motion.finished
	service.lift_assembly(id)

func refit_assembly() -> void:
	if not ready_for_action(): return
	if inspection.held:
		inspection.put_down()
		if inspection.moving: await inspection.motion.finished
	service.refit_assembly()

func refresh_ui() -> void:
	hud.refresh(inspection.held, inspection.moving, tools, service, cleaning, testing_station)
	if service.busy or tools.busy: return
	hud.set_status("Setting the GPU down..." if inspection.moving and not inspection.held else
		"Lifting the GPU..." if inspection.moving else
		"Moving GPU between benches..." if testing_station.moving else
		"GPU on test board. Press the monitor power button to run the Tetris test, or remove the card to service it." if testing_station.installed else
		"Hold and sweep over dusty surfaces with the Dev blower. Return it before servicing parts." if tools.equipped_tool == "dev-blower" else
		"Hold a screw to turn it. Release to pause. Return the screwdriver before handling the cable." if tools.equipped_tool == "screwdriver" else
		"Drag to rotate the assembly. Click a clear table spot to place it, or use Refit." if service.held_part != "" else
		"Drag to rotate. Click the fan cable to unplug/reconnect. Escape sets the GPU down." if inspection.held else
		"Click the GPU to inspect. Open the toolbox to get the screwdriver.")

func begin_refit() -> void:
	if service.held_part != "": return
	for id in service.cooler_screws + service.fan_screws:
		if id in service.removed and service.decision("refit", id).allowed:
			service.begin_screw(id)
			return

func cancel_press() -> void:
	service.end_screw()
	cleaning.end()
	dragging_button = 0
	service_press = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if not service.active_screw.is_empty(): cancel_press()
		elif service.held_part != "": refit_assembly()
		elif tools.equipped_tool != "": tools.return_tool()
		else: inspection.put_down()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if event.pressed and ready_for_action():
				var factor := 0.90 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.90
				if service.held_part != "": service.zoom_held(factor)
				elif inspection.held: inspection.zoom(factor)
				else: camera_rig.zoom(factor)
			return
		if event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if not ready_for_action(): return
			dragging_button = event.button_index
			press_position = event.position
			dragged = false
			service_press = false
			var hit: Dictionary = picker.hit_at(event.position)
			if event.button_index == MOUSE_BUTTON_LEFT and tools.equipped_tool == "dev-blower" and not testing_station.installed and hit.get("action", "") not in ["desk", "toolbox", "dev-blower", "test_board", "monitor_power"]:
				service_press = true
				cleaning.begin()
			elif event.button_index == MOUSE_BUTTON_LEFT and hit.get("action", "") in ["screw", "screw_hole"]:
				# A denied screw action owns the press, so it cannot rotate/lift the GPU.
				service_press = true
				service.begin_screw(hit.target.get_meta("part_id"))
		elif event.button_index == dragging_button:
			if not dragged and not service_press and event.button_index == MOUSE_BUTTON_LEFT:
				activate(event.position)
			cancel_press()
	elif event is InputEventMouseMotion and dragging_button != 0 and ready_for_action() and not service_press:
		dragged = dragged or event.position.distance_to(press_position) > 6.0
		if not dragged: return
		if service.held_part != "": service.rotate_held(event.relative)
		elif inspection.held: inspection.rotate_item(event.relative)
		elif dragging_button == MOUSE_BUTTON_MIDDLE: camera_rig.pan(event.relative)
		else: camera_rig.orbit(event.relative)

func activate(screen_position: Vector2) -> void:
	if not ready_for_action(): return
	var hit: Dictionary = picker.hit_at(screen_position)
	match hit.get("action", ""):
		"monitor_power": test_monitor.toggle_power()
		"test_board": toggle_test_gpu()
		"screwdriver": tools.grab()
		"dev-blower": tools.grab("dev-blower")
		"toolbox":
			if tools.equipped_tool != "" and tools.open: tools.return_tool()
			else: tools.toggle_box()
		"cable": service.toggle_cable()
		"assembly": lift_assembly(hit.target.get_meta("part_id"))
		"gpu":
			if testing_station.installed: toggle_test_gpu()
			elif not inspection.held: inspection.lift()
		"desk":
			if tools.equipped_tool != "": tools.place(hit.point, placement_obstacles())
			elif service.held_part != "": service.place_assembly(hit.point, placement_obstacles(service.held_part))

func pick_gpu(screen_position: Vector2) -> void:
	var hit: Dictionary = picker.hit_at(screen_position)
	if hit.get("action", "") in ["gpu", "screw", "cable"]: inspection.lift()

func placement_obstacles(exclude_id: String = "") -> Array:
	var boxes: Array = [gpu.global_transform * Contract.bounds_in(gpu)]
	for node in $RepairDesk.get_children():
		if node is MeshInstance3D and node.get_meta("action", "") != "desk" and node.name != "Floor":
			boxes.append(node.global_transform * node.get_aabb())
	boxes.append($RepairDesk/Toolbox.global_transform * Contract.bounds_in($RepairDesk/Toolbox))
	for id in service.removed:
		if id == exclude_id: continue
		var node: Node3D = asset_contract.objects[id]
		if not node.visible: continue
		boxes.append(node.global_transform * Contract.bounds_in(node))
	if tools.location == "desk":
		boxes.append(tools.screwdriver.global_transform * Contract.bounds_in(tools.screwdriver))
	if tools.dev_location == "desk":
		boxes.append(tools.dev_blower.global_transform * Contract.bounds_in(tools.dev_blower))
	return boxes

func _input(event: InputEvent) -> void:
	# Release is global: holds end even over UI or off the canvas.
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		service.end_screw()
		cleaning.end()
		if get_viewport().gui_get_hovered_control() != null: cancel_press()
	if event is InputEventScreenTouch and (event.canceled or (event.pressed and event.index > 0)):
		cancel_press()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_instance_valid(service): cancel_press()

func _process(delta: float) -> void:
	if cleaning.blowing and (tools.equipped_tool != "dev-blower" or not ready_for_action()):
		cleaning.end()
	if tools.equipped_tool == "dev-blower":
		var pointer: Vector2 = get_viewport().get_mouse_position()
		var surface: Dictionary = {} if get_viewport().gui_get_hovered_control() != null else picker.surface_hit_at(pointer, true)
		tools.aim_blower(pointer, surface)
		if cleaning.blowing and not testing_station.installed and ready_for_action() and get_viewport().gui_get_hovered_control() == null:
			cleaning.blow_at(pointer, delta, surface)
		hud.refresh_cleaning(cleaning)
	for jaw in jaws:
		var home_z: float = jaw.get_meta("home_z")
		var target_z: float = home_z + signf(home_z - 0.7) * (0.26 if inspection.held or inspection.moving else 0.0)
		jaw.position.z = lerpf(jaw.position.z, target_z, 1.0 - exp(-13.0 * delta))
	hover_elapsed += delta
	if picker != null and dragging_button == 0 and ready_for_action() and hover_elapsed > 0.08:
		hover_elapsed = 0.0
		var over_ui: bool = get_viewport().gui_get_hovered_control() != null
		var hit: Dictionary = {} if over_ui else picker.hit_at(get_viewport().get_mouse_position())
		var action: String = hit.get("action", "")
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if action in ["gpu", "cable", "screw", "screw_hole", "assembly", "toolbox", "screwdriver", "dev-blower", "test_board", "monitor_power"] else Input.CURSOR_ARROW)
