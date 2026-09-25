extends Node
## Each tool has one location, and only one may be equipped.
signal changed
signal notice(text: String)

var location := "toolbox"
var dev_location := "toolbox"
var equipped_tool: String:
	get: return "screwdriver" if location == "held" else "dev-blower" if dev_location == "held" else ""
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
	screwdriver = box.get_node("Screwdriver")
	dev_blower = box.get_node("DevBlower")
	home = screwdriver.transform
	dev_home = dev_blower.transform
	dev_blower.visible = OS.is_debug_build()
	camera = view_camera
	world = scene
	can_use = allowed
	toolbox.set_meta("action", "toolbox")
	screwdriver.set_meta("action", "screwdriver")
	dev_blower.set_meta("action", "dev-blower")

func tool_node(id: String) -> Node3D:
	return dev_blower if id == "dev-blower" else screwdriver

func tool_home(id: String) -> Transform3D:
	return dev_home if id == "dev-blower" else home

func tool_location(id: String) -> String:
	return dev_location if id == "dev-blower" else location

func set_tool_location(id: String, value: String) -> void:
	if id == "dev-blower": dev_location = value
	else: location = value

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
	tween.tween_property(lid, "rotation:x", -1.72 if open else 0.0, 0.55)
	await tween.finished

func equip(id: String = "screwdriver") -> void:
	if id not in ["screwdriver", "dev-blower"] or (id == "dev-blower" and not OS.is_debug_build()): return
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
	notice.emit("Hold and sweep over dusty surfaces to clean them." if id == "dev-blower" else
		"Screwdriver equipped. Hold a screw to turn it; release to pause.")

func grab(id: String = "screwdriver") -> void:
	if tool_location(id) == "toolbox" and not open: return
	equip(id)

func return_tool() -> void:
	var id := equipped_tool
	if busy or id == "" or not can_use.call(id): return
	busy = true
	changed.emit()
	if not open: await move_lid(true)
	set_tool_location(id, "toolbox")
	tool_node(id).reparent(toolbox, true)
	await move_tool(id, tool_home(id))
	busy = false
	changed.emit()
	notice.emit("Dev blower returned." if id == "dev-blower" else "Screwdriver returned. Hands are free for the fan cable.")

func place(point: Vector3, obstacles: Array) -> bool:
	var id := equipped_tool
	if busy or id == "" or not can_use.call(id): return false
	var large := id == "dev-blower"
	var target := point + Vector3(0, 0.37 if large else 0.205, 0)
	var footprint := AABB(target + (Vector3(-1.45, -0.35, -0.4) if large else Vector3(-1.35, -0.19, -0.25)),
		Vector3(2.9, 0.7, 0.8) if large else Vector3(2.7, 0.41, 0.5))
	if footprint.position.x < -9.75 or footprint.end.x > 9.75 or footprint.position.z < -5.75 or footprint.end.z > 5.75:
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
	var aspect: float = get_viewport().get_visible_rect().size.aspect()
	var half_height: float = 2.3 * tan(deg_to_rad(camera.fov / 2.0))
	var size: float = minf(0.32 if id == "dev-blower" else 0.36, half_height * aspect * 0.58)
	return Transform3D(Basis.from_euler(Vector3(0.1, -0.2, 2.2 if id == "dev-blower" else 0.9)).scaled(Vector3.ONE * size),
		Vector3(half_height * aspect * (0.42 if id == "dev-blower" else 0.65),
			-half_height * (0.42 if id == "dev-blower" else 0.60), -2.3))

func aim_blower(screen: Vector2, hit: Dictionary = {}) -> void:
	if equipped_tool != "dev-blower" or busy: return
	var pose := held_pose("dev-blower")
	var target: Vector3 = hit.get("point", camera.project_ray_origin(screen) + camera.project_ray_normal(screen) * 20.0)
	var direction: Vector3 = (camera.to_local(target) - pose.origin).normalized()
	pose.basis = Basis(Quaternion(Vector3.RIGHT, direction)).scaled(pose.basis.get_scale())
	dev_blower.transform = pose

func blower_points_at(point: Vector3) -> bool:
	if equipped_tool != "dev-blower" or busy: return false
	var origin := dev_blower.global_position
	var direction := dev_blower.global_basis.x.normalized()
	var to_point := point - origin
	return to_point.length() > 0.01 and direction.dot(to_point.normalized()) > 0.985

func _process(_delta: float) -> void:
	if equipped_tool == "screwdriver" and not busy:
		screwdriver.transform = held_pose()
