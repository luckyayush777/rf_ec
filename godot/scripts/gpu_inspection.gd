extends Node
## Whole-card inspection only. Assembly servicing will build on the captured asset contract.
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
	radius = bounds.size.length() * 0.5

func held_position() -> Vector3:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)
	# Camera uses KEEP_HEIGHT; preserve enough horizontal room in a narrow window.
	var view_distance: float = maxf(7.0, radius * 1.2 / (tan(deg_to_rad(camera.fov / 2.0)) * minf(1.0, aspect))) * zoom_factor
	return camera.global_transform * Vector3(0, -0.1, -view_distance) - gpu.global_basis * center

func lift() -> void:
	if held or moving or not can_interact.call():
		return
	held = true
	zoom_factor = 1.0
	var facing: Basis = camera.global_basis * Basis.from_euler(Vector3(0.95, -0.12, -0.08))
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

func animate_to(destination: Transform3D) -> void:
	moving = true
	changed.emit()
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	motion.tween_property(gpu, "global_transform", destination, 0.48)
	motion.finished.connect(func():
		if not held:
			gpu.transform = home
		moving = false
		changed.emit())

func rotate_item(relative: Vector2) -> void:
	if not held or moving or not can_interact.call():
		return
	gpu.global_basis = (Basis(camera.global_basis.y.normalized(), relative.x * 0.009)
		* Basis(camera.global_basis.x.normalized(), relative.y * 0.009) * gpu.global_basis).orthonormalized()

func zoom(factor: float) -> void:
	if held and not moving and can_interact.call():
		zoom_factor = clampf(zoom_factor * factor, 0.42, 1.5)

func flip() -> void:
	rotate_item(Vector2(0, PI / 0.009))

func _process(_delta: float) -> void:
	if held and not moving:
		gpu.global_position = held_position()
