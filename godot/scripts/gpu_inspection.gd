extends Node
## Whole-card inspection. Detached assembly inspection lives in gpu_service.gd.
signal changed

var gpu: Node3D
var camera: Camera3D
var home := Transform3D.IDENTITY
var held := false
var moving := false
var radius := 4.0
var zoom_factor := 1.0
var center := Vector3.ZERO
var motion: Tween
var can_interact: Callable = func(): return true

func configure(card: Node3D, view_camera: Camera3D, bounds: AABB) -> void:
	gpu = card
	camera = view_camera
	home = gpu.transform
	center = bounds.get_center()
	radius = (bounds.size * gpu.global_basis.get_scale()).length() * 0.5

func held_position() -> Vector3:
	var offset := preload("res://scripts/held_part_pose.gd").center_offset(camera, radius, zoom_factor)
	return camera.global_transform * offset - gpu.global_basis * center

func lift() -> void:
	if held or moving or not can_interact.call():
		return
	held = true
	zoom_factor = 1.0
	var facing: Basis = camera.global_basis * Basis.from_euler(Vector3(0.95, -0.12, -0.08)).scaled(home.basis.get_scale())
	var destination := Transform3D(facing, Vector3.ZERO)
	var original_basis: Basis = gpu.global_basis
	gpu.global_basis = facing
	destination.origin = held_position()
	gpu.global_basis = original_basis
	animate_to(destination)

func put_down() -> void:
	if not held or moving or not can_interact.call():
		return
	held = false
	animate_to((gpu.get_parent() as Node3D).global_transform * home)

func animate_to(destination: Transform3D, restore_holder: bool = true) -> void:
	moving = true
	changed.emit()
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	motion.tween_property(gpu, "global_transform", destination, 0.48)
	motion.finished.connect(func():
		if not held and restore_holder:
			gpu.transform = home
		moving = false
		changed.emit())

func placement_for(point: Vector3, obstacles: Array) -> Dictionary:
	if not held or moving: return {}
	var upright: Basis = gpu.get_parent().global_basis * home.basis
	var pose := Transform3D(upright, gpu.global_position)
	var bounds: AABB = pose * preload("res://scripts/asset_contract.gd").bounds_in(gpu)
	var offset := point - bounds.get_center()
	offset.y = point.y + 0.025 - bounds.position.y
	var proposed := AABB(bounds.position + offset, bounds.size)
	var allowed: bool = preload("res://scripts/asset_contract.gd").fits_table(proposed, gpu.get_parent().get_node("RepairDesk/Tabletop"))
	for obstacle in obstacles:
		if proposed.intersects(obstacle.grow(0.08)): allowed = false
	return {"allowed": allowed, "destination": Transform3D(upright, pose.origin + offset)}

func place(point: Vector3, obstacles: Array) -> bool:
	if not held or moving or not can_interact.call(): return false
	var placement := placement_for(point, obstacles)
	if not placement.get("allowed", false): return false
	held = false
	animate_to(placement.destination, false)
	return true

func rotate_item(relative: Vector2) -> void:
	if not held or moving or not can_interact.call():
		return
	gpu.global_basis = (Basis(camera.global_basis.y.normalized(), relative.x * 0.009)
		* Basis(camera.global_basis.x.normalized(), relative.y * 0.009) * gpu.global_basis).orthonormalized().scaled(home.basis.get_scale())

func zoom(factor: float) -> void:
	if held and not moving and can_interact.call():
		zoom_factor = clampf(zoom_factor * factor, 0.42, 1.5)

func flip() -> void:
	rotate_item(Vector2(0, PI / 0.009))

func _process(_delta: float) -> void:
	if held and not moving:
		gpu.global_position = held_position()
