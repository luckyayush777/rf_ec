extends Node
## The screwdriver's single location is authoritative; scene parenting follows it.
signal changed
signal notice(text: String)

var location := "toolbox"
var equipped_tool: String:
	get: return "screwdriver" if location == "held" else ""
var open := false
var busy := false
var toolbox: Node3D
var lid: Node3D
var screwdriver: Node3D
var camera: Camera3D
var world: Node3D
var home: Transform3D
var can_use: Callable

func configure(box: Node3D, view_camera: Camera3D, scene: Node3D, allowed: Callable) -> void:
	toolbox = box
	lid = box.get_node("Lid")
	screwdriver = box.get_node("Screwdriver")
	home = screwdriver.transform
	camera = view_camera
	world = scene
	can_use = allowed
	toolbox.set_meta("action", "toolbox")
	screwdriver.set_meta("action", "screwdriver")

func toggle_box() -> void:
	if busy or not can_use.call(): return
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

func equip() -> void:
	if busy or equipped_tool != "" or not can_use.call(): return
	busy = true
	changed.emit()
	if location == "toolbox" and not open:
		await move_lid(true)
	location = "held"
	screwdriver.reparent(camera, true)
	await move_tool(held_pose())
	busy = false
	changed.emit()
	notice.emit("Screwdriver equipped. Hold a screw to turn it; release to pause.")

func grab() -> void:
	if location == "toolbox" and not open: return
	equip()

func return_tool() -> void:
	if busy or equipped_tool == "" or not can_use.call(): return
	busy = true
	changed.emit()
	if not open: await move_lid(true)
	location = "toolbox"
	screwdriver.reparent(toolbox, true)
	await move_tool(home)
	busy = false
	changed.emit()
	notice.emit("Screwdriver returned. Hands are free for the fan cable.")

func place(point: Vector3, obstacles: Array) -> bool:
	if busy or equipped_tool == "" or not can_use.call(): return false
	var target := point + Vector3(0, 0.205, 0)
	var footprint := AABB(target + Vector3(-1.35, -0.19, -0.25), Vector3(2.7, 0.41, 0.5))
	if footprint.position.x < -9.75 or footprint.end.x > 9.75 or footprint.position.z < -5.75 or footprint.end.z > 5.75:
		notice.emit("Choose a clear spot with room for the whole screwdriver.")
		return false
	for obstacle in obstacles:
		if footprint.intersects(obstacle):
			notice.emit("Choose a clear spot on the desk.")
			return false
	busy = true
	location = "desk"
	changed.emit()
	screwdriver.reparent(world, true)
	move_tool(Transform3D(Basis.IDENTITY, target)).connect(func():
		busy = false
		changed.emit())
	return true

func move_tool(destination: Transform3D) -> Signal:
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(screwdriver, "transform", destination, 0.32)
	return tween.finished

func held_pose() -> Transform3D:
	var aspect: float = get_viewport().get_visible_rect().size.aspect()
	var half_height: float = 2.3 * tan(deg_to_rad(camera.fov / 2.0))
	var size: float = minf(0.36, half_height * aspect * 0.58)
	return Transform3D(Basis.from_euler(Vector3(0.1, -0.2, 0.9)).scaled(Vector3.ONE * size),
		Vector3(half_height * aspect * 0.65, -half_height * 0.60, -2.3))

func _process(_delta: float) -> void:
	if equipped_tool != "" and not busy:
		screwdriver.transform = held_pose()
