extends Node3D

const Contract = preload("res://scripts/asset_contract.gd")
const Rules = preload("res://scripts/service_rules.gd")
const Picker = preload("res://scripts/interaction_picker.gd")
@onready var camera_rig = $CameraRig
@onready var inspection = $Inspection
@onready var tools = $Tools
@onready var service = $Service
@onready var gpu: Node3D = $GPUAsset
@onready var testing_desk: Node3D = $TestingDesk
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
	camera_rig.testing_target = table_bounds.get_center()
	camera_rig.select_view("repair")
	inspection.configure(gpu, camera_rig.camera, Contract.bounds_in(gpu))
	inspection.can_interact = func(): return not service.busy and not tools.busy
	tools.configure($RepairDesk/Toolbox, camera_rig.camera, self,
		func(): return not service.busy and not inspection.moving)
	service.configure(asset_contract, service_rules, self,
		func(): return not tools.busy and not inspection.moving, func(): return tools.equipped_tool)
	for node in $RepairDesk.find_children("Jaw*", "Node3D", true, false):
		jaws.append(node)
		node.set_meta("home_z", node.position.z)
	$RepairDesk/Tabletop.set_meta("action", "desk")
	$RepairDesk/Mat.set_meta("action", "desk")
	for node in $RepairDesk.get_children():
		if String(node.name).begins_with("Grid") or String(node.name).begins_with("MatPocket"):
			node.set_meta("action", "desk")
	picker = Picker.new()
	picker.configure(self, gpu, camera_rig.camera, service)
	hud.view_requested.connect(select_view)
	hud.inspect_requested.connect(toggle_inspection)
	hud.flip_requested.connect(inspection.flip)
	hud.toolbox_requested.connect(tools.toggle_box)
	hud.equip_requested.connect(tools.equip)
	hud.return_requested.connect(tools.return_tool)
	hud.cable_requested.connect(service.toggle_cable)
	hud.refit_started.connect(begin_refit)
	hud.refit_ended.connect(func():
		service.end_screw()
		hud.refresh(inspection.held, inspection.moving, tools, service))
	hud.mute_requested.connect(func(): service.set_muted(not service.muted))
	inspection.changed.connect(refresh_ui)
	tools.changed.connect(refresh_ui)
	service.changed.connect(refresh_ui)
	tools.notice.connect(hud.set_status)
	service.notice.connect(hud.set_status)
	refresh_ui()

func ready_for_action() -> bool:
	return not inspection.moving and not tools.busy and not service.busy

func select_view(view: String) -> void:
	if inspection.held or not ready_for_action(): return
	camera_rig.select_view(view)
	refresh_ui()
	if view == "testing": hud.set_status("Testing desk is a visual prop.")

func toggle_inspection() -> void:
	if inspection.held: inspection.put_down()
	else: inspection.lift()

func refresh_ui() -> void:
	hud.refresh(inspection.held, inspection.moving, tools, service)
	if service.busy or tools.busy: return
	hud.set_status("Setting the GPU down..." if inspection.moving and not inspection.held else
		"Lifting the GPU..." if inspection.moving else
		"Hold a screw to turn it. Release to pause. Return the screwdriver before handling the cable." if tools.equipped_tool != "" else
		"Drag to rotate. Click the fan cable to unplug/reconnect. Escape sets the GPU down." if inspection.held else
		"Click the GPU to inspect. Open the toolbox to get the screwdriver.")

func begin_refit() -> void:
	for id in service.cooler_screws + service.fan_screws:
		if id in service.removed and service.decision("refit", id).allowed:
			service.begin_screw(id)
			return

func cancel_press() -> void:
	service.end_screw()
	dragging_button = 0
	service_press = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if not service.active_screw.is_empty(): cancel_press()
		elif tools.equipped_tool != "": tools.return_tool()
		else: inspection.put_down()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if event.pressed and ready_for_action():
				var factor := 0.90 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.90
				if inspection.held: inspection.zoom(factor)
				else: camera_rig.zoom(factor)
			return
		if event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if not ready_for_action(): return
			dragging_button = event.button_index
			press_position = event.position
			dragged = false
			service_press = false
			var hit: Dictionary = picker.hit_at(event.position)
			if event.button_index == MOUSE_BUTTON_LEFT and hit.get("action", "") == "screw":
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
		if inspection.held: inspection.rotate_item(event.relative)
		elif dragging_button == MOUSE_BUTTON_MIDDLE: camera_rig.pan(event.relative)
		else: camera_rig.orbit(event.relative)

func activate(screen_position: Vector2) -> void:
	if not ready_for_action(): return
	var hit: Dictionary = picker.hit_at(screen_position)
	match hit.get("action", ""):
		"screwdriver": tools.grab()
		"toolbox":
			if tools.equipped_tool != "" and tools.open: tools.return_tool()
			else: tools.toggle_box()
		"cable": service.toggle_cable()
		"gpu":
			if not inspection.held: inspection.lift()
		"desk":
			if tools.equipped_tool != "": tools.place(hit.point, placement_obstacles())

func pick_gpu(screen_position: Vector2) -> void:
	var hit: Dictionary = picker.hit_at(screen_position)
	if hit.get("action", "") in ["gpu", "screw", "cable"]: inspection.lift()

func placement_obstacles() -> Array:
	var boxes: Array = [gpu.global_transform * Contract.bounds_in(gpu)]
	for node in $RepairDesk.get_children():
		if node is MeshInstance3D and node.get_meta("action", "") != "desk" and node.name != "Floor":
			boxes.append(node.global_transform * node.get_aabb())
	boxes.append($RepairDesk/Toolbox.global_transform * Contract.bounds_in($RepairDesk/Toolbox))
	for id in service.removed:
		var node: Node3D = asset_contract.objects[id]
		boxes.append(node.global_transform * Contract.bounds_in(node))
	return boxes

func _input(event: InputEvent) -> void:
	# Release is global: holds end even over UI or off the canvas.
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		service.end_screw()
		if get_viewport().gui_get_hovered_control() != null: cancel_press()
	if event is InputEventScreenTouch and (event.canceled or (event.pressed and event.index > 0)):
		cancel_press()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_instance_valid(service): cancel_press()

func _process(delta: float) -> void:
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
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if action in ["gpu", "cable", "screw", "toolbox", "screwdriver"] else Input.CURSOR_ARROW)
