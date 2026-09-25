extends RefCounted
## A sidecar exported from the GLB avoids depending on importer-specific extras handling.

static func bind_parts(gpu: Node3D) -> Dictionary:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/gpu-parts.json"))
	var objects: Dictionary = {}
	for node in gpu.find_children("*", "Node3D", true, false):
		objects[String(node.name)] = node
	objects[String(gpu.name)] = gpu
	var service_parts: Array = []
	var homes: Dictionary = {}
	var errors: Array[String] = []
	for part in manifest.parts:
		var id: String = part.id
		if not objects.has(id):
			errors.append("Missing imported part: " + id)
			continue
		var node: Node3D = objects[id]
		if id != "gpu" and String(node.get_parent().name) != part.parent:
			errors.append("Imported parent changed for " + id)
		node.set_meta("part", part.duplicate(true))
		homes[id] = {"parent": node.get_parent(), "transform": node.transform}
		if id != "gpu" and part.role in ["assembly", "fastener", "removable"]:
			service_parts.append({"id": id, "kind": "connector" if part.role == "removable" else part.role,
				"parent": part.parent, "requires": part.get("requires", [])})
	return {"objects": objects, "homes": homes, "service_parts": service_parts, "errors": errors}

static func bounds_in(root: Node3D) -> AABB:
	var bounds := AABB()
	var started := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var local: Transform3D = root.global_transform.affine_inverse() * mesh_node.global_transform
		var box: AABB = local * mesh_node.get_aabb()
		bounds = bounds.merge(box) if started else box
		started = true
	return bounds
