extends Node3D

const Contract = preload("res://scripts/asset_contract.gd")
const Rules = preload("res://scripts/service_rules.gd")
const Picker = preload("res://scripts/interaction_picker.gd")
const Paste = preload("res://scripts/gpu_paste.gd")
const Bearing = preload("res://scripts/gpu_bearing.gd")
const AudioMix = preload("res://scripts/audio_mix.gd")
const RepairStatus = preload("res://scripts/repair_status.gd")
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
@onready var thermal: Node = $Thermal
@onready var thermal_viewer: Node = $ThermalViewer
var asset_contract: Dictionary
var service_rules: RefCounted
var picker: RefCounted
var dragging_button := 0
var press_position := Vector2.ZERO
var dragged := false
var service_press := false
var jaws: Array[Node3D] = []
var hover_elapsed := 0.0
var tool_menu_open := false
var tool_selection_busy := false
var closeup: CanvasLayer
var paste: Node
var bearing: Node
var placement_marker: MeshInstance3D
var placement_material: StandardMaterial3D
var status_elapsed := 0.0
## The close-up to reopen after the tool bag closes, when T was pressed inside one.
var focus_return: Node3D

func _ready() -> void:
	AudioMix.ensure_buses()
	gpu.name = "gpu"
	asset_contract = Contract.bind_parts(gpu)
	service_rules = Rules.new(asset_contract.service_parts,
		[{"assembly": "cooler-assembly", "fastenersRequire": ["fan-plug"]}], Paste.SURFACES + Bearing.SURFACES, Bearing.OPENINGS)
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
	testing_desk.position += Vector3(14.5 - table_bounds.position.x, -table_bounds.end.y, -table_bounds.get_center().z)
	table_bounds = tabletop.global_transform * tabletop.get_aabb()
	var board: Node3D = testing_desk.find_child("gpu-testing-board", true, false)
	board.scale *= Vector3(0.67, 0.5, 0.67)
	# Scale the holder around its authored card center, keeping it on the mat.
	var card_center: Vector3 = $RepairDesk.to_local(gpu.global_transform * Contract.bounds_in(gpu).get_center())
	var holder_shift := Vector3(card_center.x + 2.3, 0, card_center.z - 0.7)
	for holder in $RepairDesk.get_children():
		if String(holder.name).begins_with("Jaw") or String(holder.name).begins_with("HolderRail"):
			holder.position = Vector3(-2.3, 0.08, 0.7) + (holder.position - Vector3(-2.3, 0.08, 0.7)) * 0.25
			holder.position += holder_shift
			holder.scale *= 0.25
	camera_rig.testing_target = table_bounds.get_center() + Vector3(0, 1.2, 0)
	if camera_rig.legacy_test_mode: camera_rig.select_view("repair")
	else:
		$ShopInterior.enclose_room()
		camera_rig.build_collisions(self)
	inspection.configure(gpu, camera_rig.camera, Contract.bounds_in(gpu))
	inspection.can_interact = func(): return not service.busy and service.held_part == "" and not tools.busy and not testing_station.installed and not testing_station.moving and (inspection.held or near_node(gpu))
	tools.configure($RepairDesk/Toolbox, camera_rig.camera, self,
		func(id: String): return not service.busy and not inspection.moving and (tool_menu_open or tools.equipped_tool != "" or near_node(tools.tool_node(id) if id != "toolbox" else $RepairDesk/Toolbox)))
	service.configure(asset_contract, service_rules, self, camera_rig.camera,
		func(): return not tools.busy and not inspection.moving and not testing_station.installed and not testing_station.moving and (inspection.held or service.held_part != "" or near_node(gpu)),
		func(): return tools.equipped_tool)
	for node in $RepairDesk.find_children("Jaw*", "Node3D", true, false):
		jaws.append(node)
		node.set_meta("home_z", node.position.z)
		node.set_meta("opening_direction", signf(node.position.z - card_center.z))
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
	paste = Paste.new()
	paste.name = "Paste"
	add_child(paste)
	paste.configure(self)
	service.assembly_seated.connect(func(id: String): if id == "cooler-assembly": paste.seat())
	service.assembly_detached.connect(func(id: String): if id == "cooler-assembly": paste.lift())
	bearing = Bearing.new()
	bearing.name = "Bearing"
	add_child(bearing)
	bearing.configure(self)
	service.refit_block = bearing.refit_block
	testing_station.bearing = bearing
	thermal.configure(self)
	thermal_viewer.configure(self)
	hud.view_requested.connect(select_view)
	hud.test_requested.connect(toggle_test_gpu)
	hud.inspect_requested.connect(toggle_inspection)
	hud.flip_requested.connect(inspection.flip)
	hud.toolbox_requested.connect(open_tool_menu)
	hud.tool_selected.connect(select_tool)
	hud.tool_menu_closed.connect(close_tool_menu)
	hud.equip_requested.connect(tools.equip)
	hud.dev_blower_requested.connect(func(): tools.equip("dev-blower"))
	hud.highlight_dust_requested.connect(cleaning.toggle_highlight)
	hud.debug_clean_requested.connect(debug_clean_gpu)
	hud.debug_disassemble_requested.connect(debug_disassemble_gpu)
	hud.debug_dry_paste_requested.connect(paste.debug_dry)
	hud.debug_repaste_requested.connect(paste.debug_repaste)
	hud.debug_dry_bearing_requested.connect(bearing.debug_dry)
	hud.debug_oil_bearing_requested.connect(bearing.debug_oil)
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
		paste.set_muted(service.muted)
		bearing.set_muted(service.muted)
		testing_station.set_muted(service.muted)
		test_monitor.set_muted(service.muted))
	inspection.changed.connect(refresh_ui)
	tools.changed.connect(refresh_ui)
	service.changed.connect(refresh_ui)
	cleaning.changed.connect(func(): hud.refresh_cleaning(cleaning))
	paste.changed.connect(func(): hud.refresh_paste(paste))
	bearing.changed.connect(func(): hud.refresh_bearing(bearing))
	testing_station.changed.connect(refresh_ui)
	test_monitor.changed.connect(refresh_ui)
	tools.notice.connect(hud.set_status)
	service.notice.connect(hud.set_status)
	cleaning.notice.connect(hud.set_status)
	testing_station.notice.connect(hud.set_status)
	test_monitor.notice.connect(hud.set_status)
	paste.notice.connect(hud.set_status)
	bearing.notice.connect(hud.set_status)
	refresh_ui()
	hud.refresh_paste(paste)
	hud.refresh_bearing(bearing)
	if not camera_rig.legacy_test_mode: hud.enable_first_person()
	closeup = preload("res://scripts/bench_closeup.gd").new()
	add_child(closeup)
	closeup.configure(self)
	placement_marker = MeshInstance3D.new()
	placement_marker.name = "PlacementMarker"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.22
	ring.outer_radius = 0.27
	placement_marker.mesh = ring
	placement_material = StandardMaterial3D.new()
	placement_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	placement_marker.material_override = placement_material
	placement_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(placement_marker)
	placement_marker.hide()

func near_node(node: Node3D) -> bool:
	return camera_rig.legacy_test_mode or camera_rig.camera.global_position.distance_to(node.global_position) <= camera_rig.REACH

func interaction_hit(point: Vector2) -> Dictionary:
	var hit: Dictionary = picker.hit_at(point)
	if not camera_rig.legacy_test_mode and hit.has("point") and camera_rig.camera.global_position.distance_to(hit.point) > camera_rig.REACH:
		return {}
	return hit

func ready_for_action() -> bool:
	return not inspection.moving and not tools.busy and not service.busy and not testing_station.moving

func select_view(view: String) -> void:
	if not camera_rig.legacy_test_mode: return
	if inspection.held or service.held_part != "" or not ready_for_action(): return
	camera_rig.select_view(view)
	hud.set_testing_mode(view == "testing")
	refresh_ui()

func toggle_test_gpu() -> void:
	if not ready_for_action(): return
	if not near_node(testing_station.board): return
	if tools.equipped_tool != "":
		hud.set_status("Return the tool before handling the GPU on the test board.")
		return
	var was_installed: bool = testing_station.installed
	if testing_station.toggle_gpu():
		if camera_rig.legacy_test_mode: camera_rig.select_view("repair" if was_installed else "testing")
		hud.set_testing_mode(not was_installed)

func debug_clean_gpu() -> void:
	if not OS.is_debug_build(): return
	cleaning.debug_clean()

func debug_disassemble_gpu() -> void:
	if not OS.is_debug_build() or not ready_for_action() or inspection.held or testing_station.installed: return
	cleaning.end()
	if service.debug_disassemble():
		if camera_rig.legacy_test_mode: camera_rig.select_view("repair")
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
	hud.refresh_tool_menu(tools, service, tool_selection_busy)
	if service.busy or tools.busy: return
	if not camera_rig.legacy_test_mode:
		hud.set_status("GPU powered on the test board. Heat builds over time; scan the exposed rear memory packages." if testing_station.installed else
			"Part in left hand. E on the mat places it and keeps your tool; R opens focus, T the tool bag. RMB rotates and F flips." if inspection.held or service.held_part != "" else
			"Thermal camera: hold RMB to scan visible surfaces. Q returns it to the stand." if tools.equipped_tool == "thermal-camera" else
			"E picks up a part with the blower equipped. Click a part to rotate and clean it in focus." if tools.equipped_tool == "dev-blower" else
			"Click the board or a screw to work in focus. E picks up a part with the screwdriver equipped." if tools.equipped_tool == "screwdriver" else
			"Click the GPU or the detached heatsink to scrape old paste in focus." if tools.equipped_tool == "spudger" else
			"Click the scraped die, heatsink base or detached fan to wipe in focus." if tools.equipped_tool == "ipa-wipe" else
			"Click the detached fan, pull its rotor, then hold on the bearing to oil it." if tools.equipped_tool == "fan-oiler" else
			"Click the clean GPU die, then hold to squeeze fresh paste." if tools.equipped_tool == "paste-syringe" else
			"RMB + mouse rotates the held part. Aim at a clear table spot and press E to place it; Q refits it." if service.held_part != "" else
			"GPU in left hand. E places it at the green marker; RMB rotates, F flips, Q returns it to the holder." if inspection.held else
			"Aim at the GPU or a tool and press E. The orange instrument is the thermal camera.")
		return
	hud.set_status("Setting the GPU down..." if inspection.moving and not inspection.held else
		"Lifting the GPU..." if inspection.moving else
		"Moving GPU between benches..." if testing_station.moving else
		"GPU on test board. Press the monitor power button to run the racing test, or remove the card to service it." if testing_station.installed else
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
	if paste != null: paste.end()
	if bearing != null: bearing.end()
	dragging_button = 0
	service_press = false

func _unhandled_input(event: InputEvent) -> void:
	if closeup != null and closeup.mode != "": return
	if not camera_rig.legacy_test_mode:
		first_person_input(event)
		return
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

func activate(screen_position: Vector2, pickup_with_tool: bool = false) -> void:
	if not ready_for_action(): return
	var hit: Dictionary = interaction_hit(screen_position)
	var target: Node = hit.get("target")
	if pickup_with_tool and hit.get("action") == "assembly" and target.get_meta("part_id") in service.removed:
		lift_assembly(target.get_meta("part_id"))
		return
	if pickup_with_tool and tools.equipped_tool != "" and not inspection.held and not testing_station.installed and target != null and (target == gpu or gpu.is_ancestor_of(target)):
		inspection.lift()
		return
	if open_service_view(hit): return
	if not camera_rig.legacy_test_mode and testing_station.installed and target != null and (target == gpu or gpu.is_ancestor_of(target)):
		toggle_test_gpu()
		return
	match hit.get("action", ""):
		"monitor_power": test_monitor.toggle_power()
		"test_board": toggle_test_gpu()
		"screwdriver", "dev-blower", "thermal-camera", "spudger", "ipa-wipe", "paste-syringe", "fan-oiler": tools.grab(hit.action)
		"toolbox":
			open_tool_menu()
		"cable": service.toggle_cable()
		"assembly":
			var id: String = hit.target.get_meta("part_id")
			if not camera_rig.legacy_test_mode and not inspection.held and id not in service.removed and not service.decision("remove", id).allowed:
				inspection.lift()
			else: lift_assembly(id)
		"screw":
			if not camera_rig.legacy_test_mode and tools.equipped_tool == "" and not inspection.held: inspection.lift()
		"gpu":
			if testing_station.installed: toggle_test_gpu()
			elif not inspection.held: inspection.lift()
		"desk":
			if service.held_part != "": service.place_assembly(hit.point, placement_obstacles(service.held_part))
			elif inspection.held: inspection.place(hit.point, placement_obstacles("gpu"))
			elif tools.equipped_tool != "": tools.place(hit.point, placement_obstacles())

func pick_gpu(screen_position: Vector2) -> void:
	var hit: Dictionary = picker.hit_at(screen_position)
	if hit.get("action", "") in ["gpu", "screw", "cable"]: inspection.lift()

func placement_obstacles(exclude_id: String = "") -> Array:
	var boxes: Array = [] if exclude_id == "gpu" else [gpu.global_transform * Contract.bounds_in(gpu)]
	for node in $RepairDesk.get_children():
		if node is MeshInstance3D and node.get_meta("action", "") != "desk" and node.name != "Floor":
			boxes.append(node.global_transform * node.get_aabb())
	boxes.append($RepairDesk/Toolbox.global_transform * Contract.bounds_in($RepairDesk/Toolbox))
	for id in service.removed:
		if id == exclude_id: continue
		var node: Node3D = asset_contract.objects[id]
		if not node.visible: continue
		boxes.append(node.global_transform * Contract.bounds_in(node))
	for id in tools.ROLL_NODES:
		if tools.tool_location(id) == "desk":
			boxes.append(tools.tool_node(id).global_transform * Contract.bounds_in(tools.tool_node(id)))
	if tools.thermal_location != "held":
		boxes.append(tools.thermal_camera.global_transform * Contract.bounds_in(tools.thermal_camera))
	return boxes

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		thermal_viewer.aiming = false
	# Release is global: holds end even over UI or off the canvas.
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		service.end_screw()
		cleaning.end()
		if paste != null: paste.end()
		if bearing != null: bearing.end()
		if get_viewport().gui_get_hovered_control() != null: cancel_press()
	if event is InputEventScreenTouch and (event.canceled or (event.pressed and event.index > 0)):
		cancel_press()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_instance_valid(service): cancel_press()

func _process(delta: float) -> void:
	update_placement_marker()
	status_elapsed += delta
	if hud.repair_panel.visible and status_elapsed >= 0.25:
		status_elapsed = 0.0
		hud.refresh_repair_status(RepairStatus.rows(self))
	if not camera_rig.legacy_test_mode:
		camera_rig.walking_enabled = ready_for_action() and service.active_screw == "" and (closeup == null or closeup.mode == "")
	if cleaning.blowing and (tools.equipped_tool != "dev-blower" or not ready_for_action()):
		cleaning.end()
	if tools.equipped_tool == "dev-blower" and (closeup == null or closeup.mode == ""):
		var pointer: Vector2 = get_viewport().get_mouse_position() if camera_rig.legacy_test_mode else get_viewport().get_visible_rect().size * 0.5
		var surface: Dictionary = {} if (camera_rig.legacy_test_mode and get_viewport().gui_get_hovered_control() != null) else picker.surface_hit_at(pointer, true)
		if not camera_rig.legacy_test_mode and surface.has("point") and camera_rig.camera.global_position.distance_to(surface.point) > camera_rig.REACH: surface = {}
		tools.aim_blower(pointer, surface)
		if cleaning.blowing and not testing_station.installed and ready_for_action() and not surface.is_empty():
			cleaning.blow_at(pointer, delta, surface)
		hud.refresh_cleaning(cleaning)
	for jaw in jaws:
		var home_z: float = jaw.get_meta("home_z")
		var target_z: float = home_z + float(jaw.get_meta("opening_direction")) * (0.26 if inspection.held or inspection.moving else 0.0)
		jaw.position.z = lerpf(jaw.position.z, target_z, 1.0 - exp(-13.0 * delta))
	hover_elapsed += delta
	if picker != null and dragging_button == 0 and ready_for_action() and hover_elapsed > 0.08:
		hover_elapsed = 0.0
		if not camera_rig.legacy_test_mode:
			hud.update_reticle(interaction_hit(get_viewport().get_visible_rect().size * 0.5), tools, inspection, service, camera_rig.captured)
			return
		var over_ui: bool = get_viewport().gui_get_hovered_control() != null
		var hit: Dictionary = {} if over_ui else picker.hit_at(get_viewport().get_mouse_position())
		var action: String = hit.get("action", "")
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if action in ["gpu", "cable", "screw", "screw_hole", "assembly", "toolbox", "test_board", "monitor_power"] or action in tools.TOOLS else Input.CURSOR_ARROW)

func update_placement_marker() -> void:
	if placement_marker == null: return
	placement_marker.hide()
	if not ready_for_action() or (not inspection.held and service.held_part == ""): return
	if closeup.mode != "" or (not camera_rig.legacy_test_mode and not camera_rig.captured): return
	var point: Vector2 = get_viewport().get_mouse_position() if camera_rig.legacy_test_mode else get_viewport().get_visible_rect().size * 0.5
	var hit := interaction_hit(point)
	if hit.get("action") != "desk": return
	var placement: Dictionary = inspection.placement_for(hit.point, placement_obstacles("gpu")) if inspection.held else service.placement_for(hit.point, placement_obstacles(service.held_part))
	if placement.is_empty(): return
	placement_marker.global_position = hit.point + Vector3(0, 0.035, 0)
	placement_material.albedo_color = Color("#71e6b0") if placement.allowed else Color("#e57c63")
	placement_marker.show()

func first_person_input(event: InputEvent) -> void:
	var center := get_viewport().get_visible_rect().size * 0.5
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_ESCAPE, KEY_TAB]:
			if tool_menu_open:
				close_tool_menu()
				return
			cancel_press()
			thermal_viewer.aiming = false
			camera_rig.set_captured(not camera_rig.captured)
			hud.set_menu_open(not camera_rig.captured)
			return
		if not camera_rig.captured: return
		match event.physical_keycode:
			KEY_E:
				if (inspection.held or service.held_part != "") and interaction_hit(center).get("action") == "desk": activate(center, true)
				elif (inspection.held or service.held_part != "") and tools.equipped_tool != "" and ready_for_action(): closeup.show_view("service", focused_held_part())
				else: activate(center, true)
			KEY_R:
				if (inspection.held or service.held_part != "") and ready_for_action(): closeup.show_view("service", focused_held_part())
			KEY_M: hud.mute_requested.emit()
			KEY_T: open_tool_menu(true)
			KEY_Q:
				cancel_press()
				if tools.equipped_tool != "": tools.return_tool()
				elif service.held_part != "": refit_assembly()
				else: inspection.put_down()
			KEY_F:
				if service.held_part != "": service.rotate_held(Vector2(0, PI / 0.009))
				else: inspection.flip()
	if not camera_rig.captured: return
	if event is InputEventMouseMotion:
		if service.busy or inspection.moving or tools.busy: return
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and ready_for_action():
			if service.held_part != "": service.rotate_held(event.relative)
			elif inspection.held: inspection.rotate_item(event.relative)
			else: camera_rig.look(event.relative)
		else: camera_rig.look(event.relative)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and tools.equipped_tool == "thermal-camera":
			thermal_viewer.aiming = event.pressed
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed: cancel_press()
			elif ready_for_action():
				var hit := interaction_hit(center)
				if tools.equipped_tool == "dev-blower" and hit.get("action", "") == "toolbox": open_tool_menu()
				elif tools.equipped_tool == "dev-blower" and (inspection.held or service.held_part != ""): closeup.show_view("service", focused_held_part())
				elif open_service_view(hit): pass
				elif tools.equipped_tool == "dev-blower" and not testing_station.installed: cleaning.begin()
				elif hit.get("action", "") in ["screw", "screw_hole"]: service.begin_screw(hit.target.get_meta("part_id"))
				else: activate(center)
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := 0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.9
			if service.held_part != "": service.zoom_held(factor)
			elif inspection.held: inspection.zoom(factor)

## Clicking the roll needs reach; T opens the bag from anywhere, even holding a part or in a close-up.
func open_tool_menu(anywhere: bool = false) -> void:
	if tool_menu_open or not ready_for_action() or (not anywhere and not near_node($RepairDesk/Toolbox)): return
	cancel_press()
	thermal_viewer.aiming = false
	focus_return = closeup.subject if closeup.mode == "service" else null
	if focus_return != null: closeup.close()
	tool_menu_open = true
	closeup.show_view("bag")
	if not tools.open: tools.toggle_box()

func close_tool_menu() -> void:
	if tool_selection_busy or tools.busy: return
	tool_selection_busy = true
	hud.refresh_tool_menu(tools, service, true)
	if tools.open: await tools.toggle_box()
	tool_menu_open = false
	tool_selection_busy = false
	# Re-enable Close while the overlay is still visible; the service view reuses it.
	hud.refresh_tool_menu(tools, service, false)
	closeup.close()
	# Back to the part being worked on, framed for whichever tool is now in hand.
	var part := focus_return
	focus_return = null
	if part != null and is_instance_valid(part) and not testing_station.installed:
		closeup.show_view("service", part)

func focused_held_part() -> Node3D:
	return asset_contract.objects[service.held_part] if service.held_part != "" else gpu

func service_subject(target: Node) -> Node3D:
	if target == gpu or gpu.is_ancestor_of(target): return gpu
	# Detached parts are discovered from the service metadata, not a fan/cooler list.
	for definition in asset_contract.service_parts:
		if definition.kind != "assembly" or definition.id not in service.removed: continue
		var part: Node3D = asset_contract.objects[definition.id]
		if target == part or part.is_ancestor_of(target): return part
	return null

func open_service_view(hit: Dictionary) -> bool:
	if camera_rig.legacy_test_mode or (tools.equipped_tool not in ["screwdriver", "dev-blower"] and tools.equipped_tool not in tools.SURFACE_TOOLS) or testing_station.installed or not ready_for_action(): return false
	if hit.get("action", "") not in ["gpu", "assembly", "screw", "screw_hole"]: return false
	var target: Node = hit.get("target")
	if target == null: return false
	var part := service_subject(target)
	if part == null: return false
	closeup.show_view("service", part)
	if hit.get("action") == "screw_hole" and tools.equipped_tool == "screwdriver":
		service.begin_screw(target.get_meta("part_id"))
		service.end_screw()
		closeup.sync_proxies()
	return true

func select_tool(id: String) -> void:
	if not tool_menu_open or tool_selection_busy or not ready_for_action(): return
	if id != "" and id not in tools.TOOLS: return
	tool_selection_busy = true
	hud.refresh_tool_menu(tools, service, true)
	if tools.equipped_tool != id:
		if tools.equipped_tool != "": await tools.return_tool()
		if tools.equipped_tool == "" and id != "": await tools.equip(id)
	tool_selection_busy = false
	close_tool_menu()
	refresh_ui()
