extends RefCounted
## Local-space triangle queries follow current transforms immediately, including held parts.
## Cache acceleration structures per mesh instance and rebuild after cable deformation.
var entries: Array = []
var camera: Camera3D
var targets: Array = []
var gpu: Node3D
var is_removed: Callable

func configure(scene: Node3D, card: Node3D, view_camera: Camera3D, service: Node) -> void:
	camera = view_camera
	gpu = card
	is_removed = func(id: String): return id in service.removed
	for mesh in scene.find_children("*", "MeshInstance3D", true, false):
		if mesh is Label3D or mesh.mesh == null: continue
		entries.append({"node": mesh, "source": mesh.mesh, "triangles": mesh.mesh.generate_triangle_mesh()})
	for id in service.fan_screws + service.cooler_screws:
		targets.append({"node": service.contract.objects[id], "id": id, "action": "screw", "radius": 0.14})
		targets.append({"node": service.screw_seats[id], "id": id, "action": "screw_hole", "radius": 0.14})
	targets.append({"node": service.contract.objects["fan-plug"], "id": "fan-plug", "action": "cable", "radius": 0.18})

func action_for(node: Node3D) -> Dictionary:
	var current: Node = node
	while current != null:
		if current == camera: return {"action": "", "target": null}
		if current.has_meta("action"):
			return {"action": current.get_meta("action"), "target": current}
		if current == gpu: return {"action": "gpu", "target": gpu}
		current = current.get_parent()
	return {"action": "", "target": node}

func hit_at(screen: Vector2) -> Dictionary:
	var result := surface_hit_at(screen)
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var nearest: float = origin.distance_to(result.point) if result.has("point") else INF
	# Small forgiving targets remain depth-tested against the actual visible surfaces.
	for target in targets:
		var node: Node3D = target.node
		if target.action == "screw_hole" and not is_removed.call(target.id): continue
		if target.action == "screw_hole" and node.global_basis.y.normalized().dot(-direction) < 0.15: continue
		if target.action == "screw" and not is_removed.call(target.id) and node.global_basis.y.normalized().dot(-direction) < 0.15: continue
		var center := node.global_position
		var offset := origin - center
		var b: float = offset.dot(direction)
		var discriminant: float = b * b - offset.length_squared() + target.radius * target.radius
		if discriminant < 0.0: continue
		var distance: float = -b - sqrt(discriminant)
		if distance < 0.0 or distance > nearest + 0.005: continue
		nearest = distance
		result = {"action": target.action, "target": node, "point": origin + direction * distance}
	return result

func surface_hit_at(screen: Vector2, cleaning: bool = false) -> Dictionary:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var nearest := INF
	var result: Dictionary = {}
	for entry in entries:
		var mesh: MeshInstance3D = entry.node
		# Decorative pieces above the dustable fan cap do not block cleaning air.
		if cleaning and mesh.name in ["fan-brand-label", "hub-center"]: continue
		if not mesh.is_visible_in_tree() or camera.is_ancestor_of(mesh): continue
		var inverse := mesh.global_transform.affine_inverse()
		var local_origin := inverse * origin
		var local_direction := (inverse.basis * direction).normalized()
		if not mesh.get_aabb().intersects_ray(local_origin, local_direction): continue
		if entry.source != mesh.mesh:
			entry.source = mesh.mesh
			entry.triangles = mesh.mesh.generate_triangle_mesh()
		if entry.triangles == null: continue
		var hit: Dictionary = entry.triangles.intersect_ray(local_origin, local_direction)
		if hit.is_empty(): continue
		var point: Vector3 = mesh.global_transform * hit.position
		var distance: float = origin.distance_to(point)
		if distance < nearest:
			nearest = distance
			result = action_for(mesh)
			result.point = point
			result.mesh = mesh
			result.normal = hit.normal
	return result
