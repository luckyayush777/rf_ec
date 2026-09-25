extends RefCounted
## Port of src/service-rules.ts. No scene, UI, or animation dependency.
## Invalid definitions fail closed and report errors; no debug-only assertions.

var parts: Dictionary = {}
var removal: Dictionary = {}
var errors: Array[String] = []

func _init(definitions: Array, exceptions: Array = []) -> void:
	for part in definitions:
		if parts.has(part.id):
			errors.append("Duplicate service part ID: " + part.id)
		parts[part.id] = part.duplicate(true)
		removal[part.id] = part.requires.duplicate()
	for exception in exceptions:
		var assembly: Dictionary = parts.get(exception.assembly, {})
		if assembly.is_empty() or assembly.kind != "assembly":
			errors.append("Missing service assembly: " + exception.assembly)
			continue
		var found := false
		for id in assembly.requires:
			if parts.get(id, {}).get("kind", "") == "fastener":
				removal[id].append_array(exception.fastenersRequire)
				found = true
		if not found:
			errors.append("No fasteners declared for " + exception.assembly)
	for id in removal:
		for required in removal[id]:
			if not parts.has(required):
				errors.append("Unknown service requirement %s for %s" % [required, id])
	if errors.is_empty():
		var visited: Dictionary = {}
		for id in parts:
			visit(id, {}, visited)

func visit(id: String, visiting: Dictionary, visited: Dictionary) -> void:
	if visiting.has(id):
		errors.append("Circular service requirements involving " + id)
		return
	if visited.has(id):
		return
	visiting[id] = true
	for required in removal[id]:
		visit(required, visiting, visited)
	visiting.erase(id)
	visited[id] = true

func dependents(id: String) -> Array:
	var result: Array = []
	for part in parts.values():
		if part.kind == "assembly" and id in part.requires:
			result.append(part.id)
	return result

func installed(id: String, removed: Array, connected: Dictionary) -> bool:
	return bool(connected.get(id, false)) if parts[id].kind == "connector" else id not in removed

func deny(reason: String, missing: Array = []) -> Dictionary:
	return {"allowed": false, "missing": missing, "reason": reason}

func check(kind: String, id: String, removed: Array = [], connected: Dictionary = {}, tool: String = "") -> Dictionary:
	if not errors.is_empty():
		return deny("Invalid service definitions: " + "; ".join(errors))
	if not parts.has(id):
		return deny("Unknown service part: " + id)
	var part: Dictionary = parts[id]
	var actions: Dictionary = {"fastener": ["remove", "refit"], "assembly": ["remove", "refit", "pickup"], "connector": ["connect", "disconnect"]}
	if kind not in actions.get(part.kind, []):
		return deny("Invalid %s action: %s" % [part.kind, kind])
	if part.kind == "fastener" and tool != "screwdriver":
		return deny("Pick up the screwdriver to remove or refit a screw.")
	if part.kind != "fastener" and not tool.is_empty():
		return deny("Set the %s down before handling the %s." % [tool, id.replace("-", " ")])
	var required: Array = []
	if kind == "remove":
		for dependency in removal[id]:
			if installed(dependency, removed, connected) and dependency not in required:
				required.append(dependency)
	elif kind == "refit":
		var candidates: Array = dependents(id)
		if part.kind == "assembly":
			var parent: String = part.get("parent", "")
			candidates = [parent] if parts.get(parent, {}).get("kind", "") == "assembly" else []
		for dependency in candidates:
			if not installed(dependency, removed, connected):
				required.append(dependency)
	elif kind == "connect":
		for dependency in dependents(id):
			if not installed(dependency, removed, connected):
				required.append(dependency)
	if not required.is_empty():
		return deny("%s requires: %s" % [kind.capitalize(), ", ".join(required)], required)
	return {"allowed": true, "missing": [], "reason": ""}
