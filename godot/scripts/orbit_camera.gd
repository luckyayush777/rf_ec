extends Node3D

@onready var camera: Camera3D = $Camera3D
var target := Vector3.ZERO
var yaw := 0.0
var pitch := 0.55
var distance := 30.0
var testing_target := Vector3(23, 0, 0)

func select_view(view: String) -> void:
	var offset := Vector3(12, 16, 23)
	target = Vector3(0, -0.3, 0)
	match view:
		"testing":
			target = testing_target
			offset = Vector3(5, 7, 11)
		"both":
			target = testing_target * 0.5
			offset = Vector3(0, 26, 48)
		"top":
			offset = Vector3(0, 30, 0.1)
	distance = offset.length()
	pitch = asin(offset.y / distance)
	yaw = atan2(offset.x, offset.z)
	apply_pose()

func orbit(relative: Vector2) -> void:
	yaw -= relative.x * 0.006
	pitch = clampf(pitch + relative.y * 0.006, 0.025, PI * 0.495)
	apply_pose()

func zoom(factor: float) -> void:
	distance = clampf(distance * factor, 8.0, 150.0)
	apply_pose()

func pan(relative: Vector2) -> void:
	var viewport_height: float = maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var scale_factor: float = 2.0 * distance * tan(deg_to_rad(camera.fov / 2.0)) / viewport_height
	target += (-camera.global_basis.x * relative.x + camera.global_basis.y * relative.y) * scale_factor
	apply_pose()

func apply_pose() -> void:
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(target)
