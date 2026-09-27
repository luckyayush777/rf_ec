extends RefCounted
## Frame a held part in the left hand while leaving the centre ray unobstructed.
static func center_offset(camera: Camera3D, radius: float, zoom: float) -> Vector3:
	var aspect := camera.get_viewport().get_visible_rect().size.aspect()
	var tangent := tan(deg_to_rad(camera.fov * 0.5))
	if camera.get_parent().get("legacy_test_mode") == true:
		var old_distance := maxf(1.8, radius * 1.2 / (tangent * minf(1, aspect))) * zoom
		return Vector3(0, -0.1, -old_distance)
	var framing := tangent * minf(0.7, aspect * 0.32)
	var distance := maxf(maxf(1.8, radius * 1.6 / framing) * zoom, radius * 1.3 / framing)
	var half_height := distance * tangent
	return Vector3(-half_height * aspect * 0.58, -half_height * 0.28, -distance)
