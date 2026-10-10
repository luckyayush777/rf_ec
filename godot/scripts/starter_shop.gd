extends RefCounted
## The inexpensive first workshop. Native furniture keeps the GPU and tool scales intact.
const Contract = preload("res://scripts/asset_contract.gd")
const Room = preload("res://scripts/shop_interior.gd")
const FLOOR_Y := -4.5
const FLOOR_AREA := Rect2(Vector2(10.5, -16.5), Vector2(22.0, 26.0))
## Inner wall faces of the starter room, (x, z) in world units: 4.5 m wide, 5.2 m long. The
## right edge is the window wall and the front edge the door facade; both stay fixed.
const ROOM := Rect2(Vector2(10.5, -16.5), Vector2(22.5, 26.0))
## Build view plops expansions down as squares as wide as the starter room is long (ROOM.size.y).
const EXPANSION_SIZE := 26.0
const MAX_EXPANSIONS := 3
## Expansions stay behind the front facade and left of the window wall: two squares out to the
## left, one row behind (x -41.5..33, z -42.5..9.5). Further back, the yard's trees begin.
const LOT := Rect2(Vector2(-41.5, -42.5), Vector2(74.5, 52.0))
## A square must share at least this much wall with the floor it joins (1.6 m).
const MIN_OPENING := 8.0
## Along the shared wall the square snaps to 0.2 m steps and to corners within 0.6 m.
const SNAP := 1.0
const CORNER_SNAP := 3.0
const WALL := 0.5
const CEILING_Y := 10.5
enum {SIDE_LEFT, SIDE_BACK, SIDE_RIGHT, SIDE_FRONT}

## The starter room and each built expansion, as inner floor rectangles.
static func rooms(squares: Array) -> Array[Rect2]:
	var result: Array[Rect2] = [ROOM]
	for square in squares: result.append(square)
	return result

## Floor that equipment may cover: the starter's clear floor (short of the hatch counter) and
## every built square.
static func floor_rects(squares: Array) -> Array[Rect2]:
	var result: Array[Rect2] = [FLOOR_AREA]
	for square in squares: result.append(square)
	return result

static func is_floor(rects: Array, point: Vector2) -> bool:
	for rect in rects:
		if rect.has_point(point): return true
	return false

## True when `rect` lies entirely on the union of `rects`.
static func covers(rects: Array, rect: Rect2) -> bool:
	var pending: Array[Rect2] = [rect]
	for floor_rect in rects:
		var rest: Array[Rect2] = []
		for piece in pending: rest.append_array(subtract(piece, floor_rect))
		pending = rest
		if pending.is_empty(): return true
	return pending.is_empty()

## What is left of `a` outside `b`, as up to four strips.
static func subtract(a: Rect2, b: Rect2) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var cut := a.intersection(b)
	if cut.size.x <= 0.001 or cut.size.y <= 0.001:
		result.append(a)
		return result
	var strips: Array[Rect2] = [
		Rect2(a.position.x, a.position.y, a.size.x, cut.position.y - a.position.y),
		Rect2(a.position.x, cut.end.y, a.size.x, a.end.y - cut.end.y),
		Rect2(a.position.x, cut.position.y, cut.position.x - a.position.x, cut.size.y),
		Rect2(cut.end.x, cut.position.y, a.end.x - cut.end.x, cut.size.y)]
	for strip in strips:
		if strip.size.x > 0.001 and strip.size.y > 0.001: result.append(strip)
	return result

## Length of wall `a` and `b` share, zero unless they touch side by side.
static func shared_length(a: Rect2, b: Rect2) -> float:
	if absf(a.end.x - b.position.x) < 0.01 or absf(b.end.x - a.position.x) < 0.01:
		return maxf(0.0, minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y))
	if absf(a.end.y - b.position.y) < 0.01 or absf(b.end.y - a.position.y) < 0.01:
		return maxf(0.0, minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x))
	return 0.0

## A new square fits on the lot, overlaps no floor and opens onto existing floor.
static func expansion_fits(squares: Array, square: Rect2) -> bool:
	if not LOT.encloses(square): return false
	var joined := false
	for room in rooms(squares):
		var overlap := square.intersection(room)
		if overlap.size.x > 0.01 and overlap.size.y > 0.01: return false
		joined = joined or shared_length(square, room) >= MIN_OPENING - 0.01
	return joined

## The square the build view offers for a pointer at `point`: flush against the nearest side of
## the existing floor, following the pointer along it. Fitting squares are preferred.
static func expansion_at(squares: Array, point: Vector2) -> Rect2:
	var best := Rect2()
	var best_score := INF
	for room in rooms(squares):
		for side in [SIDE_LEFT, SIDE_BACK, SIDE_RIGHT, SIDE_FRONT]:
			var square := beside(room, side, point)
			var nearest := Vector2(clampf(point.x, square.position.x, square.end.x), clampf(point.y, square.position.y, square.end.y))
			var score := nearest.distance_to(point) + (0.0 if expansion_fits(squares, square) else 1000.0)
			if score < best_score:
				best_score = score
				best = square
	return best

static func beside(room: Rect2, side: int, point: Vector2) -> Rect2:
	var k := EXPANSION_SIZE
	var along_x: bool = side in [SIDE_BACK, SIDE_FRONT]
	var low: float = room.position.x if along_x else room.position.y
	var high: float = room.end.x if along_x else room.end.y
	var start := snappedf((point.x if along_x else point.y) - k * 0.5, SNAP)
	if absf(start - low) < CORNER_SNAP: start = low
	if absf(start + k - high) < CORNER_SNAP: start = high - k
	start = clampf(start, LOT.position.x if along_x else LOT.position.y, (LOT.end.x if along_x else LOT.end.y) - k)
	start = clampf(start, low - k + MIN_OPENING, high - MIN_OPENING)
	match side:
		SIDE_LEFT: return Rect2(room.position.x - k, start, k, k)
		SIDE_RIGHT: return Rect2(room.end.x, start, k, k)
		SIDE_BACK: return Rect2(start, room.position.y - k, k, k)
	return Rect2(start, room.end.y, k, k)

static func prepare(bench: Node3D) -> void:
	var desk: Node3D = bench.get_node("RepairDesk")
	desk.position = Vector3(18, -0.29260135, -5)
	# 2.4 x 1.6 m, down from 4 x 2.4 m. Never scale the tools or the card with the table.
	desk.get_node("Tabletop").scale = Vector3(0.6, 1, 2.0 / 3.0)
	for name in ["FrontApron", "RearApron"]:
		var apron: Node3D = desk.get_node(name)
		apron.scale.x = 0.6
		apron.position.z = 3.5 if name == "FrontApron" else -3.5
	for node in desk.get_children():
		var name := String(node.name)
		if name.begins_with("Leg") or name.begins_with("Foot"):
			node.position.x = signf(node.position.x) * 5.4
			node.position.z = signf(node.position.z) * 3.4
		elif name.begins_with("Grid") or name.begins_with("MatPocket") or name == "MatLabel" or name == "SpareParts":
			node.hide()
		elif name.begins_with("Tray"):
			node.position += Vector3(0.6, 0, -1.8)
		elif name.begins_with("Lamp"):
			node.position += Vector3(0.5, 0, 0.3)
	var mat: Node3D = desk.get_node("Mat")
	mat.position = Vector3(-1.8, 0.024, 1.7)
	mat.scale = Vector3(7.0 / 10.5, 1, 3.6 / 7.4)
	desk.get_node("Toolbox").position = Vector3(-0.5, 0.015, -2)
	var card_bounds: AABB = bench.gpu.global_transform * Contract.bounds_in(bench.gpu)
	bench.gpu.global_position += desk.global_position + Vector3(-1.2, 0.275, 2.0) - card_bounds.get_center()
	# Clear of the standing room in front of the desk, so the starting layout is a valid one.
	bench.computer.position = Vector3(12.5, FLOOR_Y, 4.5)
	bench.computer.rotation.y = PI * 0.5
	bench.delivery_box.position = desk.global_position + Vector3(-4, 0.01, 1.0)
	bench.get_node("ThermalCameraStand").position = desk.global_position + Vector3(5.0, 1.055, -2.5)
	bench.get_node("ThermalCameraStand").hide()
	bench.get_node("ThermalCameraBox").hide()
	bench.testing_desk.hide()
	bench.test_monitor.hide()
	bench.queue_monitor.hide()
	bench.camera_rig.spawn_position = Vector3(17, -4.35, 3)
	bench.camera_rig.respawn()
	# A tired wooden top and an old rubber mat.
	desk.get_node("Tabletop").material_override = Room.flat(Color("514334"), 0.95)
	mat.material_override = Room.flat(Color("303f39"), 0.95)

static func enclose(bench: Node3D) -> void:
	var room: Node3D = bench.get_node("ShopInterior")
	room.get_node("Model").hide()
	var shell := Node3D.new()
	shell.name = "StarterShell"
	room.add_child(shell)
	shell.global_transform = Transform3D.IDENTITY
	# Shared by every plaster face, so refurbishing also covers later expansions.
	var plaster := Room.flat(Color("655e4d"), 0.98)
	var concrete := Room.flat(Color("444440"), 1.0)
	var wood := Room.flat(Color("332c26"), 0.95)
	for entry in [["plaster", plaster], ["concrete", concrete], ["wood", wood]]: shell.set_meta(entry[0], entry[1])
	room.piece(shell, "StarterFloor", Vector3(10, -4.8, -17), Vector3(33.8, FLOOR_Y, 10), concrete)
	# The left and back walls are generated with the floor plan (`build_plan`).
	room.piece(shell, "StarterFrontLeft", Vector3(10, FLOOR_Y, 9.5), Vector3(14.5, 10.5, 10), plaster)
	room.piece(shell, "StarterFrontRight", Vector3(19.5, FLOOR_Y, 9.5), Vector3(33.8, 10.5, 10), plaster)
	room.piece(shell, "StarterDoorHeader", Vector3(14.5, 6.5, 9.5), Vector3(19.5, 10.5, 10), plaster)
	var ceiling: MeshInstance3D = room.piece(shell, "StarterCeiling", Vector3(10, 10.5, -17), Vector3(33.8, 10.8, 10), plaster)
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for z in [-13.0, -5.0, 3.0]:
		room.piece(shell, "CeilingBeam", Vector3(10.5, 10, z), Vector3(33, 10.5, z + 0.35), wood)
	# Retain the delivery window in its established world position and close its shorter wall.
	for entry in [["WallBackOfWindow", -17.0, Room.WINDOW_Z.x], ["WallFrontOfWindow", Room.WINDOW_Z.y, 10.0]]:
		var piece: MeshInstance3D = room.find_child(entry[0], true, false)
		piece.mesh = piece.mesh.duplicate()
		piece.mesh.size.z = entry[2] - entry[1]
		piece.position.z = (entry[1] + entry[2]) * 0.5
	for name in ["WallBelowWindow", "WallAboveWindow"]:
		var piece: MeshInstance3D = room.find_child(name, true, false)
		piece.mesh = piece.mesh.duplicate()
		piece.mesh.size.z = 27.0
		piece.position.z = -3.5
	for name in ["WallBelowWindow", "WallAboveWindow", "WallBackOfWindow", "WallFrontOfWindow"]:
		room.find_child(name, true, false).material_override = plaster
	var door: MeshInstance3D = room.get_node("EntranceDoor")
	door.global_position = Vector3(17, 1, 9.7)
	door.mesh = door.mesh.duplicate()
	door.mesh.size.x = 1.0
	door.get_node("DoorHandle").position.x = 0.38
	# Sparse scuffs on the floor and worn patches on the wall, kept outside working surfaces.
	var stain := Room.flat(Color("373a33"), 1.0)
	for index in range(12):
		var x := 11.5 + fmod(index * 7.3, 20.0)
		var z := -15.0 + fmod(index * 5.7, 23.0)
		room.add_block(shell, "FloorWear", Vector3(0.4 + fmod(index * 0.63, 1.5), 0.003, 0.12), Vector3(x, FLOOR_Y + 0.005, z), stain)
	for index in range(5):
		room.add_block(shell, "WallWear", Vector3(0.008, 0.4 + index * 0.14, 2.4), Vector3(10.51, -2.2 + index * 0.36, -13 + index * 4.3), stain)
	# Furniture collision is added for the whole room afterwards.
	build_plan(bench, [], false)
	Room.shadowless(shell)

## Rebuilds the generated part of the shell for the starter room plus `squares`: a wall along
## every stretch of floor edge with no floor beyond it (where floors meet, the wall is knocked
## through under a lintel), and each square's floor, ceiling, beams and fixture. Walls along x
## run on past convex corners to close them. Generated pieces collide when `collide` is set.
static func build_plan(bench: Node3D, squares: Array, collide := true) -> void:
	var room: Node3D = bench.get_node("ShopInterior")
	var shell: Node3D = room.get_node("StarterShell")
	var old := shell.get_node_or_null("Plan")
	if old != null:
		shell.remove_child(old)
		old.free()
	var plan := Node3D.new()
	plan.name = "Plan"
	shell.add_child(plan)
	var plaster: Material = shell.get_meta("plaster")
	var wood: Material = shell.get_meta("wood")
	var rects := rooms(squares)
	var solid: Array[MeshInstance3D] = []
	for index in rects.size():
		var rect: Rect2 = rects[index]
		for side in [SIDE_LEFT, SIDE_BACK, SIDE_RIGHT, SIDE_FRONT]:
			# The starter's window wall and door facade are fixed pieces.
			if index == 0 and side in [SIDE_RIGHT, SIDE_FRONT]: continue
			for span in open_spans(rects, rect, side):
				solid.append(wall(room, plan, rects, rect, side, span, plaster))
			# Each opening gets one lintel, from the later of the two floors.
			for other in rects.slice(0, index):
				var line := edge(rect, side)
				if absf(edge(other, opposite(side)) - line) > 0.01: continue
				var along_x: bool = side in [SIDE_BACK, SIDE_FRONT]
				var low := maxf(rect.position.x if along_x else rect.position.y, other.position.x if along_x else other.position.y)
				var high := minf(rect.end.x if along_x else rect.end.y, other.end.x if along_x else other.end.y)
				if high - low < 0.01: continue
				var half := WALL * 0.5
				if along_x: room.piece(plan, "Lintel", Vector3(low, 9.6, line - half), Vector3(high, CEILING_Y, line + half), wood)
				else: room.piece(plan, "Lintel", Vector3(line - half, 9.6, low), Vector3(line + half, CEILING_Y, high), wood)
		if index == 0: continue
		# Just under the starter floor and above its ceiling where they overlap at an opening.
		var outer := rect.grow(WALL)
		solid.append(room.piece(plan, "ExpansionFloor", Vector3(outer.position.x, -4.8, outer.position.y), Vector3(outer.end.x, FLOOR_Y - 0.002, outer.end.y), shell.get_meta("concrete")))
		solid.append(room.piece(plan, "ExpansionCeiling", Vector3(outer.position.x, CEILING_Y + 0.002, outer.position.y), Vector3(outer.end.x, CEILING_Y + 0.3, outer.end.y), plaster))
		for third in [1.0 / 3.0, 2.0 / 3.0]:
			var z: float = rect.position.y + rect.size.y * third
			room.piece(plan, "CeilingBeam", Vector3(rect.position.x + 0.5, 10, z), Vector3(rect.end.x - 0.5, CEILING_Y, z + 0.35), wood)
		var centre := rect.get_center()
		room.add_block(plan, "ExpansionLamp", Vector3(1.6, 0.18, 0.5), Vector3(centre.x, CEILING_Y - 0.09, centre.y), Room.flat(Color("e9dcc0"), 0.4))
	if collide:
		for piece in solid: piece.create_trimesh_collision()
	# Wear on a knocked-through stretch of the starter's left wall goes with it.
	for mesh in shell.get_children():
		if String(mesh.name).begins_with("WallWear"):
			mesh.visible = not shell.get_meta("refurbished", false) and not is_floor(rects, Vector2(ROOM.position.x - WALL * 0.5, mesh.position.z))
	Room.shadowless(plan)

## The coordinate of a rectangle's side: x for left/right, z for back/front.
static func edge(rect: Rect2, side: int) -> float:
	match side:
		SIDE_LEFT: return rect.position.x
		SIDE_RIGHT: return rect.end.x
		SIDE_BACK: return rect.position.y
	return rect.end.y

static func opposite(side: int) -> int:
	return {SIDE_LEFT: SIDE_RIGHT, SIDE_RIGHT: SIDE_LEFT, SIDE_BACK: SIDE_FRONT, SIDE_FRONT: SIDE_BACK}[side]

## Stretches of a side, as (start, end) along it, with no other floor on the far side.
static func open_spans(rects: Array, rect: Rect2, side: int) -> Array[Vector2]:
	var along_x: bool = side in [SIDE_BACK, SIDE_FRONT]
	var spans: Array[Vector2] = [Vector2(rect.position.x, rect.end.x) if along_x else Vector2(rect.position.y, rect.end.y)]
	for other in rects:
		if other == rect or absf(edge(other, opposite(side)) - edge(rect, side)) > 0.01: continue
		var cut := Vector2(other.position.x, other.end.x) if along_x else Vector2(other.position.y, other.end.y)
		var rest: Array[Vector2] = []
		for span in spans:
			for piece in [Vector2(span.x, minf(span.y, cut.x)), Vector2(maxf(span.x, cut.y), span.y)]:
				if piece.y - piece.x > 0.01: rest.append(piece)
		spans = rest
	return spans

static func wall(room: Node3D, plan: Node3D, rects: Array, rect: Rect2, side: int, span: Vector2, material: Material) -> MeshInstance3D:
	var line := edge(rect, side)
	var outward := -1.0 if side in [SIDE_LEFT, SIDE_BACK] else 1.0
	var far := line + outward * WALL
	if side in [SIDE_LEFT, SIDE_RIGHT]:
		return room.piece(plan, "Wall", Vector3(minf(line, far), FLOOR_Y, span.x), Vector3(maxf(line, far), CEILING_Y, span.y), material)
	# Past a convex corner the outside diagonal is not floor: run on to close it.
	var middle := line + outward * WALL * 0.5
	if not is_floor(rects, Vector2(span.x - WALL * 0.5, middle)): span.x -= WALL
	if not is_floor(rects, Vector2(span.y + WALL * 0.5, middle)): span.y += WALL
	return room.piece(plan, "Wall", Vector3(span.x, FLOOR_Y, minf(line, far)), Vector3(span.y, CEILING_Y, maxf(line, far)), material)

static func refurbish(bench: Node3D) -> void:
	var room: Node3D = bench.get_node("ShopInterior")
	var shell: Node3D = room.get_node("StarterShell")
	var plaster: StandardMaterial3D = shell.get_meta("plaster")
	plaster.albedo_color = Color("ada991")
	plaster.roughness = 0.85
	shell.set_meta("refurbished", true)
	for mesh in shell.get_children():
		if String(mesh.name).begins_with("FloorWear") or String(mesh.name).begins_with("WallWear"): mesh.hide()
	bench.get_node("RepairDesk/Tabletop").material_override = Room.flat(Color("94704b"), 0.8)
