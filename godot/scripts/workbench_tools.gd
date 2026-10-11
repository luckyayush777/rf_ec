extends Node
## Each tool has one location, and only one may be equipped.
signal changed
signal notice(text: String)

const PASTE_TOOLS := ["spudger", "ipa-wipe", "paste-syringe"]
## Hand tools that work a surface in focus: the paste kit and the fan oiler.
const SURFACE_TOOLS := PASTE_TOOLS + ["fan-oiler"]
## Hand tools that only look: the jeweller's loupe magnifies the focus view.
const VIEW_TOOLS := ["loupe"]
## Megacorp glue removal in focus (gpu_glue.gd): the heat gun softens it, the suction pen sucks it off.
const GLUE_TOOLS := ["heat-gun", "suction-pen"]
const TOOLS := ["screwdriver", "air-blower", "dev-blower", "thermal-camera", "spudger", "ipa-wipe", "paste-syringe", "fan-oiler", "loupe",
	"heat-gun", "suction-pen"]
## Tools that live on their own bench stand instead of a roll pocket. The heat gun's cradle is
## built here under the repair desk (so it moves with it) at a desk-local spot.
const STANDS := {"thermal-camera": "ThermalCameraStand", "heat-gun": "HeatGunStand"}
const STAND_SCENES := {"heat-gun": "res://scenes/heat_gun.tscn"}
const STAND_LABELS := {"heat-gun": "HEAT GUN"}
const STAND_TOOL_SCALE := 0.45
## The shop air blower is the regular cleaning tool; the debug-only Dev blower clears a wide spot.
const BLOWERS := ["air-blower", "dev-blower"]
## Roll-pocket tools and their node names in scenes/toolbox.tscn.
const ROLL_NODES := {"screwdriver": "Screwdriver", "air-blower": "AirBlower", "dev-blower": "DevBlower", "spudger": "Spudger", "ipa-wipe": "IpaWipe", "paste-syringe": "PasteSyringe", "fan-oiler": "FanOiler", "loupe": "Loupe", "suction-pen": "SuctionPen"}
const EQUIP_NOTICES := {
	"screwdriver": "Screwdriver equipped. Click the GPU for a close-up, then hold a screw to turn it.",
	"air-blower": "Air blower equipped. Click a part for a close-up, then hold and sweep the jet over the dust. Air carries into the fins and spins the fan.",
	"dev-blower": "Hold and sweep over dusty surfaces to clean them.",
	"thermal-camera": "Thermal camera equipped. Hold RMB to inspect surface heat.",
	"spudger": "Plastic spudger equipped. Click the bare die or heatsink base, then hold and drag to scrape off old paste.",
	"ipa-wipe": "IPA wipe equipped. Hold and rub the scraped surfaces to lift the remaining film.",
	"paste-syringe": "Paste syringe equipped. Click the bare die, then hold to squeeze; drag to lay a line.",
	"fan-oiler": "Fan oiler equipped. Click the detached fan, pull its rotor, then hold on the bearing for a drop.",
	"loupe": "Loupe equipped. Click the GPU to look over its gold fingers; click to magnify, wheel to zoom.",
	"heat-gun": "Heat gun equipped. Click the GPU, then hold LMB to heat every glue blob facing you until they turn soft and glossy.",
	"suction-pen": "Suction pen equipped. Click the GPU, then hold LMB on softened glue to suck it off."}
const NAMES := {"screwdriver": "screwdriver", "air-blower": "air blower", "dev-blower": "Dev blower", "thermal-camera": "thermal camera",
	"spudger": "spudger", "ipa-wipe": "IPA wipe", "paste-syringe": "paste syringe", "fan-oiler": "fan oiler", "loupe": "loupe",
	"heat-gun": "heat gun", "suction-pen": "suction pen"}
const RETURN_NOTICES := {
	"screwdriver": "Screwdriver returned. Hands are free for the fan cable.",
	"air-blower": "Air blower returned.",
	"dev-blower": "Dev blower returned.",
	"thermal-camera": "Thermal camera returned."}

var locations := {"screwdriver": "toolbox", "air-blower": "toolbox", "dev-blower": "toolbox", "thermal-camera": "stand",
	"spudger": "toolbox", "ipa-wipe": "toolbox", "paste-syringe": "toolbox", "fan-oiler": "toolbox", "loupe": "toolbox",
	"heat-gun": "stand", "suction-pen": "toolbox"}
## Stand-mounted tools' stand nodes, by tool id.
var stands: Dictionary = {}
var location: String:
	get: return locations["screwdriver"]
	set(value): locations["screwdriver"] = value
var dev_location: String:
	get: return locations["dev-blower"]
	set(value): locations["dev-blower"] = value
var thermal_location: String:
	get: return locations["thermal-camera"]
	set(value): locations["thermal-camera"] = value
## Tools still packed in their box: hidden and never equipped (the thermal camera, for now).
var locked: Array[String] = []
var nodes: Dictionary = {}
var homes: Dictionary = {}
var thermal_camera: Node3D
var thermal_stand: Node3D
var thermal_home: Transform3D
var equipped_tool: String:
	get:
		for id in TOOLS:
			if locations[id] == "held": return id
		return ""
var open := false
var busy := false
var toolbox: Node3D
var lid: Node3D
var screwdriver: Node3D
var dev_blower: Node3D
var camera: Camera3D
var world: Node3D
var home: Transform3D
var dev_home: Transform3D
var can_use: Callable

func configure(box: Node3D, view_camera: Camera3D, scene: Node3D, allowed: Callable) -> void:
	toolbox = box
	lid = box.get_node("Lid")
	for id in ROLL_NODES:
		var node: Node3D = box.get_node(ROLL_NODES[id])
		nodes[id] = node
		homes[id] = node.get_meta("roll_home")
		node.set_meta("action", id)
	screwdriver = nodes["screwdriver"]
	dev_blower = nodes["dev-blower"]
	home = homes["screwdriver"]
	dev_home = homes["dev-blower"]
	dev_blower.visible = OS.is_debug_build()
	camera = view_camera
	world = scene
	thermal_stand = world.get_node("ThermalCameraStand")
	thermal_camera = thermal_stand.get_node("ThermalCamera")
	thermal_home = thermal_camera.transform
	thermal_camera.set_meta("action", "thermal-camera")
	nodes["thermal-camera"] = thermal_camera
	homes["thermal-camera"] = thermal_home
	stands["thermal-camera"] = thermal_stand
	for id in STAND_SCENES:
		build_stand(id, world.get_node("RepairDesk"))
	can_use = allowed
	toolbox.set_meta("action", "toolbox")

## A small rubber-footed cradle on the repair desk holding a stand tool, labelled on its plinth.
## The starter shop moves it with `place_stands`.
func build_stand(id: String, desk: Node3D) -> void:
	var stand := Node3D.new()
	stand.name = STANDS[id]
	desk.add_child(stand)
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color("2a3134")
	rubber.roughness = 0.9
	var ivory := StandardMaterial3D.new()
	ivory.albedo_color = Color("ece0c4")
	ivory.roughness = 0.6
	for piece in [[Vector3(1.3, 0.08, 0.6), Vector3(0, 0.04, 0), rubber], [Vector3(0.1, 0.24, 0.42), Vector3(-0.38, 0.2, 0), ivory],
			[Vector3(0.1, 0.24, 0.42), Vector3(0.36, 0.2, 0), ivory]]:
		var mesh := BoxMesh.new()
		mesh.size = piece[0]
		var block := MeshInstance3D.new()
		block.mesh = mesh
		block.material_override = piece[2]
		block.position = piece[1]
		stand.add_child(block)
	var plate := Label3D.new()
	plate.name = "StandLabel"
	plate.text = STAND_LABELS[id]
	plate.pixel_size = 0.004
	plate.font_size = 26
	plate.outline_size = 0
	plate.modulate = Color("ece0c4")
	plate.position = Vector3(0, 0.05, 0.302)
	stand.add_child(plate)
	var tool: Node3D = load(STAND_SCENES[id]).instantiate()
	tool.name = "HeatGun"
	stand.add_child(tool)
	tool.scale = Vector3.ONE * STAND_TOOL_SCALE
	# The gun stands on its foot between the cradles.
	tool.position = Vector3(0, 0.42, 0)
	tool.set_meta("action", id)
	stands[id] = stand
	nodes[id] = tool
	homes[id] = tool.transform
	place_stands(desk, false)

## Desk-local spot for the heat gun's stand: right of the mat and in front of the unrolled tool
## roll in the starter shop, behind the roll at the right end of the full-size fixture desk.
func place_stands(_desk: Node3D, starter: bool) -> void:
	if stands.has("heat-gun"): stands["heat-gun"].position = Vector3(4.65, 0.0, 0.15) if starter else Vector3(7.6, 0.0, -1.6)

func tool_node(id: String) -> Node3D:
	return nodes.get(id, screwdriver)

func tool_home(id: String) -> Transform3D:
	return homes.get(id, home)

func tool_location(id: String) -> String:
	return locations.get(id, "")

func set_tool_location(id: String, value: String) -> void:
	locations[id] = value

func set_locked(id: String, value: bool) -> void:
	if value == (id in locked) or tool_location(id) == "held": return
	if value: locked.append(id)
	else: locked.erase(id)
	tool_node(id).set_meta("shop_locked", value)
	tool_node(id).visible = not value and (STANDS.has(id) or open)
	# A glue tool's cradle arrives with the tool; the thermal stand is shown on purchase.
	if STAND_SCENES.has(id): stands[id].visible = not value
	changed.emit()

func toggle_box() -> void:
	if busy or not can_use.call("toolbox"): return
	busy = true
	changed.emit()
	await move_lid(not open)
	busy = false
	changed.emit()

func move_lid(value: bool) -> void:
	open = value
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(toolbox.set_opening, toolbox.opening, 1.0 if open else 0.0, 0.55)
	await tween.finished

func equip(id: String = "screwdriver") -> void:
	if id not in TOOLS or id in locked or (id == "dev-blower" and not OS.is_debug_build()): return
	if busy or equipped_tool != "" or not can_use.call(id): return
	busy = true
	changed.emit()
	if tool_location(id) == "toolbox" and not open:
		await move_lid(true)
	set_tool_location(id, "held")
	tool_node(id).reparent(camera, true)
	await move_tool(id, held_pose(id))
	busy = false
	changed.emit()
	notice.emit(EQUIP_NOTICES[id])

func grab(id: String = "screwdriver") -> void:
	if tool_location(id) == "toolbox" and not open: return
	equip(id)

func return_tool() -> void:
	var id := equipped_tool
	if busy or id == "" or not can_use.call(id): return
	busy = true
	changed.emit()
	if not STANDS.has(id) and not open: await move_lid(true)
	set_tool_location(id, "stand" if STANDS.has(id) else "toolbox")
	tool_node(id).reparent(stands[id] if STANDS.has(id) else toolbox, true)
	await move_tool(id, tool_home(id))
	busy = false
	changed.emit()
	notice.emit(RETURN_NOTICES.get(id, NAMES[id].capitalize() + " returned."))

func place(point: Vector3, obstacles: Array) -> bool:
	var id := equipped_tool
	if busy or id == "" or not can_use.call(id): return false
	var large := id in BLOWERS
	var target := point + Vector3(0, 0.37 if large else 0.205, 0)
	var footprint := AABB(target + (Vector3(-1.45, -0.35, -0.4) if large else Vector3(-1.35, -0.19, -0.25)),
		Vector3(2.9, 0.7, 0.8) if large else Vector3(2.7, 0.41, 0.5))
	if id == "thermal-camera":
		target = point + Vector3(0, 1.055, 0)
		footprint = AABB(point + Vector3(-0.6, 0.01, -0.55), Vector3(1.2, 1.45, 1.1))
	if not preload("res://scripts/asset_contract.gd").fits_table(footprint, world.get_node("RepairDesk/Tabletop")):
		notice.emit("Choose a clear spot with room for the whole tool.")
		return false
	for obstacle in obstacles:
		if footprint.intersects(obstacle):
			notice.emit("Choose a clear spot on the desk.")
			return false
	busy = true
	set_tool_location(id, "desk")
	changed.emit()
	tool_node(id).reparent(world, true)
	move_tool(id, Transform3D(Basis.IDENTITY, target)).connect(func():
		busy = false
		changed.emit())
	return true

func move_tool(id: String, destination: Transform3D) -> Signal:
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(tool_node(id), "transform", destination, 0.32)
	return tween.finished

func held_pose(id: String = "screwdriver") -> Transform3D:
	if id == "thermal-camera":
		return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.7), Vector3(0.85, -0.55, -1.7))
	var aspect: float = get_viewport().get_visible_rect().size.aspect()
	var half_height: float = 2.3 * tan(deg_to_rad(camera.fov / 2.0))
	var blower: bool = id in BLOWERS
	var size: float = minf(0.32 if blower else 0.36, half_height * aspect * 0.58)
	return Transform3D(Basis.from_euler(Vector3(0.1, -0.2, 2.2 if blower else 0.9)).scaled(Vector3.ONE * size),
		Vector3(half_height * aspect * (0.42 if blower else 0.65),
			-half_height * (0.42 if blower else 0.60), -2.3))

func blower_equipped() -> bool:
	return equipped_tool in BLOWERS

## The equipped tool works in a part's focus view (click the part to open it).
func focus_tool() -> bool:
	var id := equipped_tool
	return id == "screwdriver" or id in BLOWERS or id in SURFACE_TOOLS or id in VIEW_TOOLS or id in GLUE_TOOLS

## The held blower's nozzle axis in world space.
func blower_axis() -> Vector3:
	return tool_node(equipped_tool).global_basis.x.normalized()

func aim_blower(screen: Vector2, hit: Dictionary = {}) -> void:
	if not blower_equipped() or busy: return
	var pose := held_pose(equipped_tool)
	var target: Vector3 = hit.get("point", camera.project_ray_origin(screen) + camera.project_ray_normal(screen) * 20.0)
	var direction: Vector3 = (camera.to_local(target) - pose.origin).normalized()
	pose.basis = Basis(Quaternion(Vector3.RIGHT, direction)).scaled(pose.basis.get_scale())
	tool_node(equipped_tool).transform = pose

func blower_points_at(point: Vector3) -> bool:
	if not blower_equipped() or busy: return false
	var blower := tool_node(equipped_tool)
	var to_point := point - blower.global_position
	return to_point.length() > 0.01 and blower_axis().dot(to_point.normalized()) > 0.985

func _process(_delta: float) -> void:
	var id := equipped_tool
	if (id == "screwdriver" or id in SURFACE_TOOLS or id in VIEW_TOOLS or id in GLUE_TOOLS) and not busy:
		tool_node(id).transform = held_pose(id)
