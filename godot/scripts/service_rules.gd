extends RefCounted
## Service dependency evaluator. No scene, UI, or animation dependency.
## Invalid definitions fail closed and report errors; no debug-only assertions.

var parts: Dictionary = {}
var removal: Dictionary = {}
var surfaces: Dictionary = {}
var openings: Dictionary = {}
var errors: Array[String] = []
## Service-surface actions and the one tool that performs each.
const SURFACE_TOOLS := {"scrape": "spudger", "wipe": "ipa-wipe", "apply": "paste-syringe", "oil": "fan-oiler"}

func _init(definitions: Array, exceptions: Array = [], contact_surfaces: Array = [], part_openings: Array = []) -> void:
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
	# Thermal-interface surfaces are exposed only while their covering assembly is detached.
	for surface in contact_surfaces:
		if surfaces.has(surface.id):
			errors.append("Duplicate contact surface: " + surface.id)
		elif parts.get(surface.exposedBy, {}).get("kind", "") != "assembly":
			errors.append("Contact surface %s is exposed by unknown assembly %s" % [surface.id, surface.exposedBy])
		surfaces[surface.id] = surface.duplicate(true)
	# Openings inside a detached assembly (a hub sticker, a rotor) open in declared order.
	for opening in part_openings:
		if openings.has(opening.id):
			errors.append("Duplicate opening: " + opening.id)
		elif parts.get(opening.insideOf, {}).get("kind", "") != "assembly":
			errors.append("Opening %s is inside unknown assembly %s" % [opening.id, opening.insideOf])
		openings[opening.id] = opening.duplicate(true)
	for opening in openings.values():
		for required in opening.get("requires", []):
			if not openings.has(required):
				errors.append("Unknown opening requirement %s for %s" % [required, opening.id])
	for surface in surfaces.values():
		for required in surface.get("needsOpen", []):
			if not openings.has(required):
				errors.append("Contact surface %s needs unknown opening %s" % [surface.id, required])
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
	var actions: Dictionary = {"fastener": ["remove", "refit"], "assembly": ["remove", "refit", "pickup", "inspect"], "connector": ["connect", "disconnect"]}
	if kind not in actions.get(part.kind, []):
		return deny("Invalid %s action: %s" % [part.kind, kind])
	if part.kind == "fastener" and tool != "screwdriver":
		return deny("Pick up the screwdriver to remove or refit a screw.")
	if kind == "inspect" and id not in removed:
		return deny("Detach the part before inspecting it in your hand.")
	if part.kind != "fastener" and kind != "inspect" and not tool.is_empty():
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

func check_surface(kind: String, id: String, removed: Array = [], tool: String = "", opened: Array = []) -> Dictionary:
	if not errors.is_empty():
		return deny("Invalid service definitions: " + "; ".join(errors))
	if not surfaces.has(id):
		return deny("Unknown contact surface: " + id)
	if not SURFACE_TOOLS.has(kind):
		return deny("Invalid contact-surface action: " + kind)
	var surface: Dictionary = surfaces[id]
	var label := String(surface.get("label", id))
	if tool != SURFACE_TOOLS[kind]:
		return deny("Use the %s to %s." % [SURFACE_TOOLS[kind].replace("-", " "), kind])
	if kind == "apply" and not surface.get("applyPaste", false):
		return deny("Apply fresh paste to the GPU die, not the %s." % label)
	if kind not in surface.get("actions", ["scrape", "wipe", "apply"]):
		return deny("Only the fan bearing takes oil." if kind == "oil" else String(surface.get("hint", "The %s does not need that." % label)))
	var cover: String = surface.exposedBy
	if installed(cover, removed, {}):
		return deny("Remove the %s to reach the %s." % [cover.replace("-", " "), label], [cover])
	for required in surface.get("needsOpen", []):
		if required not in opened:
			return deny("Open the %s to reach the %s." % [String(openings[required].get("label", required)), label], [required])
	return {"allowed": true, "missing": [], "reason": ""}

## Opens or closes a part inside a detached assembly. Closing waits for anything opened after it.
func check_opening(kind: String, id: String, removed: Array = [], opened: Array = [], tool: String = "") -> Dictionary:
	if not errors.is_empty():
		return deny("Invalid service definitions: " + "; ".join(errors))
	if not openings.has(id):
		return deny("Unknown opening: " + id)
	if kind not in ["open", "close"]:
		return deny("Invalid opening action: " + kind)
	var opening: Dictionary = openings[id]
	var label := String(opening.get("label", id))
	if tool not in opening.get("tools", [""]):
		return deny("Set the %s down before handling the %s." % [tool.replace("-", " "), label])
	if installed(opening.insideOf, removed, {}):
		return deny("Remove the %s to reach the %s." % [String(opening.insideOf).replace("-", " "), label], [opening.insideOf])
	var required: Array = []
	if kind == "open":
		for dependency in opening.get("requires", []):
			if dependency not in opened: required.append(dependency)
		if not required.is_empty():
			return deny("Open the %s first." % String(openings[required[0]].get("label", required[0])), required)
	else:
		for other in openings.values():
			if id in other.get("requires", []) and other.id in opened: required.append(other.id)
		if not required.is_empty():
			return deny("Refit the %s first." % String(openings[required[0]].get("label", required[0])), required)
	return {"allowed": true, "missing": [], "reason": ""}
