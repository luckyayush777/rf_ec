extends Node
## Cable, fastener and assembly state. Every entry point checks rules and action guards.
const Contract = preload("res://scripts/asset_contract.gd")
signal changed
signal notice(text: String)

var contract: Dictionary
var rules: RefCounted
var world: Node3D
var camera: Camera3D
var can_use: Callable
var get_tool: Callable
var removed: Array = []
var stored: Array = []
var held_part := ""
var held_center := Vector3.ZERO
var held_radius := 2.0
var held_zoom := 1.0
var cable_connected := true
var cable_progress := 0.0
var moving := false
var active_screw := ""
var turns: Dictionary = {}
var fan_screws: Array = []
var cooler_screws: Array = []
var screw_seats: Dictionary = {}
var wires: Array = []
var motion: Tween
var muted := false
var audio: AudioStreamPlayer
var busy: bool:
	get: return moving or not active_screw.is_empty()

func configure(parts: Dictionary, evaluator: RefCounted, scene: Node3D, view_camera: Camera3D, allowed: Callable, tool: Callable) -> void:
	contract = parts
	rules = evaluator
	world = scene
	camera = view_camera
	can_use = allowed
	get_tool = tool
	for definition in contract.service_parts:
		if definition.kind != "assembly": continue
		contract.objects[definition.id].set_meta("action", "assembly")
		contract.objects[definition.id].set_meta("part_id", definition.id)
		var screws: Array = []
		for id in definition.requires:
			if rules.parts[id].kind == "fastener": screws.append(id)
		if definition.id == "fan-assembly": fan_screws = screws
		if definition.id == "cooler-assembly": cooler_screws = screws
	for id in ["fan-plug", "board-fan-socket", "fan-cable"]:
		contract.objects[id].set_meta("action", "cable")
	for id in fan_screws + cooler_screws:
		contract.objects[id].set_meta("action", "screw")
		contract.objects[id].set_meta("part_id", id)
		create_screw_seat(id)
	for index in range(2):
		var id := "fan-positive-wire" if index == 0 else "fan-ground-wire"
		var wire: MeshInstance3D = contract.objects[id]
		wires.append({"node": wire, "mesh": wire.mesh, "end": Vector3(2.54, 0.244 if index == 0 else 0.205, 0.39)})
	audio = AudioStreamPlayer.new()
	audio.stream = preload("res://assets/manual-screwdriver.wav")
	audio.volume_db = -4.0
	add_child(audio)

func create_screw_seat(id: String) -> void:
	var home: Dictionary = contract.homes[id]
	var seat := Node3D.new()
	seat.name = id + "-seat"
	seat.transform = home.transform
	seat.set_meta("action", "screw_hole")
	seat.set_meta("part_id", id)
	home.parent.add_child(seat)
	var rim_material := StandardMaterial3D.new()
	rim_material.albedo_color = Color(0.31, 0.34, 0.36)
	rim_material.metallic = 0.65
	rim_material.roughness = 0.54
	var rim := MeshInstance3D.new()
	rim.name = "MetalRim"
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = 0.085
	rim_mesh.outer_radius = 0.135
	rim_mesh.material = rim_material
	rim.mesh = rim_mesh
	rim.position.y = 0.017
	seat.add_child(rim)
	var well_material := StandardMaterial3D.new()
	well_material.albedo_color = Color(0.027, 0.031, 0.034)
	well_material.roughness = 1.0
	var well := MeshInstance3D.new()
	well.name = "Recess"
	var well_mesh := CylinderMesh.new()
	well_mesh.top_radius = 0.085
	well_mesh.bottom_radius = 0.085
	well_mesh.height = 0.006
	well_mesh.material = well_material
	well.mesh = well_mesh
	well.position.y = 0.015
	seat.add_child(well)
	screw_seats[id] = seat

func debug_disassemble() -> bool:
	if not OS.is_debug_build() or busy or not can_use.call(): return false
	# Normalize partial service too: paused turns and stored/placed assemblies end
	# in the same fully separated, refittable layout.
	audio.stop()
	active_screw = ""
	turns.clear()
	removed.clear()
	stored.clear()
	held_part = ""
	cable_connected = false
	apply_cable_pose(1.0)
	for id in fan_screws + cooler_screws:
		var part: Node3D = contract.objects[id]
		part.reparent(world, true)
		var fan: bool = id in fan_screws
		var index: int = (fan_screws if fan else cooler_screws).find(id)
		part.global_transform = Transform3D(Basis(Vector3.BACK, PI / 2),
			Vector3(3.1 + index * 0.48, 0.20, 3.38 if fan else 4.12))
		removed.append(id)
	debug_place_assembly("fan-assembly", Vector3(-7, 0.05, 4))
	debug_place_assembly("cooler-assembly", Vector3(-2, 0.05, -4))
	changed.emit()
	notice.emit("Debug: GPU fully disassembled. Refit the heatsink, then fan, screws and cable.")
	return true

func debug_place_assembly(id: String, table_point: Vector3) -> void:
	var part: Node3D = contract.objects[id]
	var home: Transform3D = contract.objects["gpu"].global_transform * contract.homes["cooler-assembly"].transform
	if id == "fan-assembly": home *= contract.homes[id].transform
	part.reparent(world, true)
	part.global_transform = home
	part.visible = true
	var bounds: AABB = part.global_transform * Contract.bounds_in(part)
	var offset := table_point - bounds.get_center()
	offset.y = table_point.y + 0.025 - bounds.position.y
	part.global_position += offset
	removed.append(id)

func decision(kind: String, id: String) -> Dictionary:
	return rules.check(kind, id, removed, {"fan-plug": cable_connected}, get_tool.call())

func toggle_cable() -> bool:
	if busy or held_part != "" or not can_use.call(): return false
	var check := decision("disconnect" if cable_connected else "connect", "fan-plug")
	if not check.allowed:
		notice.emit(check.reason)
		return false
	cable_connected = not cable_connected
	moving = true
	changed.emit()
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	motion.tween_method(apply_cable_pose, cable_progress, 0.0 if cable_connected else 1.0, 0.24)
	motion.finished.connect(func():
		moving = false
		changed.emit()
		notice.emit("Fan cable connected." if cable_connected else "Fan cable unplugged. Cooler screws are now accessible with the screwdriver."))
	return true

func apply_cable_pose(value: float) -> void:
	cable_progress = value
	var plug: Node3D = contract.objects["fan-plug"]
	var home: Transform3D = contract.homes["fan-plug"].transform
	plug.transform = home
	plug.position += Vector3(0, 0.22, 0.58) * value
	plug.basis = home.basis * Basis(Vector3.RIGHT, -0.22 * value)
	for wire in wires:
		if is_zero_approx(value):
			wire.node.mesh = wire.mesh
			continue
		var bent := ArrayMesh.new()
		for surface in range(wire.mesh.get_surface_count()):
			var arrays: Array = wire.mesh.surface_get_arrays(surface).duplicate(true)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in range(vertices.size()):
				var weight: float = smoothstep(0.0, 1.0, 1.0 - maxf(0.0, vertices[i].distance_to(wire.end) - 0.06) / 0.7)
				vertices[i] += Vector3(0, 0.22, 0.58) * value * weight
			arrays[Mesh.ARRAY_VERTEX] = vertices
			# Regenerate normals for the bent geometry; imported originals stay untouched.
			arrays[Mesh.ARRAY_TANGENT] = null
			var temporary := ArrayMesh.new()
			temporary.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var surface_tool := SurfaceTool.new()
			surface_tool.create_from(temporary, 0)
			surface_tool.generate_normals()
			surface_tool.set_material(wire.mesh.surface_get_material(surface))
			surface_tool.commit(bent)
		wire.node.mesh = bent

func begin_screw(id: String) -> bool:
	if busy or held_part != "" or not can_use.call() or id not in fan_screws + cooler_screws: return false
	var reinstall: bool = id in removed
	var check := decision("refit" if reinstall else "remove", id)
	if not check.allowed:
		notice.emit(check.reason)
		return false
	if not turns.has(id):
		turns[id] = {"progress": 0.0, "reinstall": reinstall, "from": contract.objects[id].global_transform}
	active_screw = id
	changed.emit()
	notice.emit("Hold to %s %s. Release to pause." % ["tighten" if reinstall else "remove", id.replace("-", " ")])
	return true

func end_screw() -> void:
	if active_screw.is_empty(): return
	var id := active_screw
	active_screw = ""
	audio.stop()
	changed.emit()
	notice.emit("%s: %d%% — hold the same screw to continue." % [id.replace("-", " "), roundi(turns[id].progress * 100)])

func advance_turn(delta: float) -> void:
	if active_screw.is_empty(): return
	var id := active_screw
	var part: Node3D = contract.objects[id]
	var turn: Dictionary = turns[id]
	turn.progress = minf(1.0, turn.progress + maxf(0.0, delta) / 1.5)
	var home: Transform3D = contract.homes[id].transform
	if turn.reinstall:
		var destination: Transform3D = contract.homes[id].parent.global_transform * home
		part.global_transform = (turn.from as Transform3D).interpolate_with(destination, turn.progress)
		part.global_position.y += sin(PI * turn.progress) * 0.35
		part.basis = part.basis * Basis(Vector3.UP, -TAU * 3 * turn.progress)
	else:
		part.transform = home
		part.position += home.basis.y * 0.34 * turn.progress
		part.basis = home.basis * Basis(Vector3.UP, TAU * 3 * turn.progress)
	changed.emit()
	if turn.progress >= 1.0:
		complete_screw(id)

func complete_screw(id: String) -> void:
	var part: Node3D = contract.objects[id]
	var reinstall: bool = turns[id].reinstall
	turns.erase(id)
	active_screw = ""
	audio.stop()
	if reinstall:
		part.reparent(contract.homes[id].parent, true)
		part.transform = contract.homes[id].transform
		removed.erase(id)
		changed.emit()
		notice.emit(id.replace("-", " ").capitalize() + " refitted.")
		return
	removed.append(id)
	part.reparent(world, true)
	var fan: bool = id in fan_screws
	var index: int = (fan_screws if fan else cooler_screws).find(id)
	var destination := Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(3.1 + index * 0.48, 0.20, 3.38 if fan else 4.12))
	var origin := part.global_transform
	moving = true
	changed.emit()
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	motion.tween_method(func(t: float):
		part.global_transform = origin.interpolate_with(destination, t)
		part.global_position.y += sin(PI * t) * 0.7, 0.0, 1.0, 0.68)
	motion.finished.connect(func():
		part.global_transform = destination
		moving = false
		changed.emit()
		notice.emit(id.replace("-", " ").capitalize() + " in tray. Hold it with the screwdriver to refit."))

func held_position(basis: Basis) -> Vector3:
	var size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = size.x / maxf(size.y, 1.0)
	var distance: float = maxf(7.0, held_radius * 1.2 / (tan(deg_to_rad(camera.fov / 2.0)) * minf(1.0, aspect))) * held_zoom
	return camera.global_transform * Vector3(0, -0.1, -distance) - basis * held_center

func lift_assembly(id: String) -> bool:
	if busy or held_part != "" or not can_use.call() or id not in ["fan-assembly", "cooler-assembly"]: return false
	var already_removed: bool = id in removed
	var check := decision("pickup" if already_removed else "remove", id)
	if not check.allowed:
		notice.emit(check.reason)
		return false
	var part: Node3D = contract.objects[id]
	var was_stored: bool = id in stored
	if not already_removed: removed.append(id)
	stored.erase(id)
	part.visible = true
	part.reparent(world, true)
	var bounds: AABB = Contract.bounds_in(part)
	held_center = bounds.get_center()
	held_radius = bounds.size.length() * 0.5
	held_zoom = 1.0
	held_part = id
	var facing := camera.global_basis * Basis.from_euler(Vector3(0.95, -0.12, -0.08))
	var destination := Transform3D(facing, held_position(facing))
	if was_stored: part.global_position = destination.origin + Vector3(0, -0.4, 0)
	animate_assembly(part, destination, func(): notice.emit("%s lifted. Drag to rotate; click a clear table spot to place it, or use Refit." % assembly_name(id)))
	return true

func assembly_name(id: String) -> String:
	return "Fan and cable" if id == "fan-assembly" else "Heatsink and cooler"

func animate_assembly(part: Node3D, destination: Transform3D, done: Callable) -> void:
	moving = true
	changed.emit()
	var origin := part.global_transform
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	motion.tween_method(func(t: float):
		part.global_transform = origin.interpolate_with(destination, t)
		part.global_position.y += sin(PI * t) * 0.5, 0.0, 1.0, 0.45)
	motion.finished.connect(func():
		part.global_transform = destination
		moving = false
		changed.emit()
		done.call())

func rotate_held(relative: Vector2) -> void:
	if held_part == "" or busy: return
	var part: Node3D = contract.objects[held_part]
	part.global_basis = (Basis(camera.global_basis.y.normalized(), relative.x * 0.009)
		* Basis(camera.global_basis.x.normalized(), relative.y * 0.009) * part.global_basis).orthonormalized()

func zoom_held(factor: float) -> void:
	if held_part != "" and not busy: held_zoom = clampf(held_zoom * factor, 0.5, 1.5)

func placement_for(point: Vector3, obstacles: Array) -> Dictionary:
	if held_part == "" or busy: return {}
	var part: Node3D = contract.objects[held_part]
	var original := part.global_transform
	var home: Dictionary = contract.homes[held_part]
	var upright: Basis = home.parent.global_basis * home.transform.basis
	part.global_transform = Transform3D(upright, original.origin)
	var bounds: AABB = part.global_transform * Contract.bounds_in(part)
	part.global_transform = original
	var offset := point - bounds.get_center()
	offset.y = point.y + 0.025 - bounds.position.y
	var proposed := AABB(bounds.position + offset, bounds.size)
	var allowed: bool = proposed.position.x >= -9.75 and proposed.end.x <= 9.75 and proposed.position.z >= -5.75 and proposed.end.z <= 5.75
	for obstacle in obstacles:
		if proposed.intersects(obstacle.grow(0.08)): allowed = false
	return {"allowed": allowed, "destination": Transform3D(upright, original.origin + offset)}

func place_assembly(point: Vector3, obstacles: Array) -> bool:
	if held_part == "" or busy or not can_use.call(): return false
	if get_tool.call() != "":
		notice.emit("Return the tool before placing the assembly.")
		return false
	var placement := placement_for(point, obstacles)
	if not placement.allowed:
		notice.emit("Choose a clear table spot with room for the whole assembly.")
		return false
	var part: Node3D = contract.objects[held_part]
	animate_assembly(part, placement.destination, func():
		held_part = ""
		changed.emit()
		notice.emit("Assembly on the table. Click it to pick it up, or use Refit to mount it."))
	return true

func store_assembly() -> bool:
	if held_part == "" or busy or not can_use.call(): return false
	if get_tool.call() != "":
		notice.emit("Return the tool before storing the assembly.")
		return false
	var id := held_part
	var part: Node3D = contract.objects[id]
	part.visible = false
	part.global_position = Vector3(0, -100, 0)
	stored.append(id)
	held_part = ""
	changed.emit()
	notice.emit("%s stored. Use its lift button to retrieve it." % assembly_name(id))
	return true

func refit_assembly() -> bool:
	if busy or not can_use.call(): return false
	if get_tool.call() != "":
		notice.emit("Return the tool before refitting the assembly.")
		return false
	var id := held_part if held_part != "" else "cooler-assembly" if "cooler-assembly" in removed else "fan-assembly" if "fan-assembly" in removed else ""
	if id == "": return false
	var check := decision("refit", id)
	if not check.allowed:
		notice.emit(check.reason)
		return false
	var part: Node3D = contract.objects[id]
	var home: Dictionary = contract.homes[id]
	var destination: Transform3D = home.parent.global_transform * home.transform
	if id in stored: part.global_transform = Transform3D(destination.basis, destination.origin + Vector3(0, 0.5, 0))
	part.visible = true
	stored.erase(id)
	animate_assembly(part, destination, func():
		part.reparent(home.parent, true)
		part.transform = home.transform
		removed.erase(id)
		held_part = ""
		changed.emit()
		notice.emit("%s seated. Refit its screws from the tray." % assembly_name(id)))
	return true

func set_muted(value: bool) -> void:
	muted = value
	if muted: audio.stop()
	changed.emit()

func _process(delta: float) -> void:
	advance_turn(delta)
	if held_part != "" and not moving:
		var part: Node3D = contract.objects[held_part]
		part.global_position = held_position(part.global_basis)
	if not active_screw.is_empty() and not muted and not audio.playing:
		audio.play()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and audio != null:
		end_screw()
