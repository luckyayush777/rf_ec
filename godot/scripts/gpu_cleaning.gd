extends Node
## Independent local-space dust masks stay with each mesh during removal and refit.
signal changed
signal notice(text: String)

const TILE := 48
const WIDTH := TILE * 3
const HEIGHT := TILE * 2
const DUST_COVERAGE := 0.40
const AXES := [[2, 1], [2, 1], [0, 2], [0, 2], [0, 1], [0, 1]]
const DUST_SHADER = preload("res://shaders/dust_overlay.gdshader")
const HIGHLIGHT_SHADER = preload("res://shaders/dust_highlight.gdshader")

var surfaces: Array[Dictionary] = []
var lookup: Dictionary = {}
var picker: RefCounted
var tools: Node
var blowing := false
var celebrated := false
var completed_count := 0
var completed_parts: Dictionary = {}
var target_part := ""
var highlighted := false
var blower_held := false
var blower_elapsed := -1.0
var auto_highlight_shown := false
var muted := false
var jingle: AudioStreamPlayer
var air: AudioStreamPlayer

var progress: float:
	get:
		var total := 0.0
		var left := 0.0
		for surface in surfaces:
			total += surface.mass
			left += surface.remaining
		return 1.0 - left / total if total > 0.0 else 1.0

func configure(card: Node3D, scene_picker: RefCounted, workbench_tools: Node) -> void:
	picker = scene_picker
	tools = workbench_tools
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pattern := RegEx.new()
	pattern.compile("^(board-top|board-bottom|fan-housing|fan-blade-[0-9]+|fan-hub-cap|heatsink-base|heatsink-fins|heatsink-fin-[0-9]+|(?:fan|cooler)-screw-[0-9]+-head)$")
	for node in card.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or pattern.search(String(mesh.name)) == null: continue
		var owner := "board"
		var ancestor: Node = mesh
		while ancestor != card:
			var part: Dictionary = ancestor.get_meta("part", {})
			if part.get("role", "") in ["assembly", "fastener"]:
				owner = String(ancestor.name)
				if part.get("role", "") == "fastener":
					owner = "fan-assembly" if owner.begins_with("fan-screw-") else "cooler-assembly"
				break
			ancestor = ancestor.get_parent()
		var bounds: AABB = mesh.get_aabb()
		var size := bounds.size.max(Vector3.ONE * 0.001)
		var coverage := PackedByteArray()
		coverage.resize(WIDTH * HEIGHT)
		for surface_index in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for triangle in range(count / 3):
				var offset: int = triangle * 3
				var a: Vector3 = vertices[indices[offset] if not indices.is_empty() else offset]
				var b: Vector3 = vertices[indices[offset + 1] if not indices.is_empty() else offset + 1]
				var c: Vector3 = vertices[indices[offset + 2] if not indices.is_empty() else offset + 2]
				var normal := surface_normal(a, b, c)
				var outward := (mesh.global_basis * normal).normalized()
				# The mounted fan encloses its underside and inner walls. Keep its dust on
				# the exposed top faces that the blower can actually reach.
				if owner == "fan-assembly" and outward.y < 0.6: continue
				if mesh.name == "board-top" and outward.y < 0.7: continue
				if mesh.name == "board-bottom" and outward.y > -0.7: continue
				if String(mesh.name).begins_with("heatsink-fin") and outward.y < 0.7: continue
				paint_triangle(coverage, a, b, c, face_for(normal), bounds.position, size)
		var weights: Array[float] = []
		for axes in AXES:
			weights.append(size[axes[0]] * size[axes[1]] / float((TILE - 2) * (TILE - 2)))
		var data := make_dust_mask(coverage, rng)
		var mass := 0.0
		for index in range(data.size()):
			if data[index] == 0: continue
			var x := index % WIDTH
			var y := index / WIDTH
			var face: int = (y / TILE) * 3 + x / TILE
			mass += data[index] * weights[face]
		if mass <= 0.0: continue
		var image := Image.create_from_data(WIDTH, HEIGHT, false, Image.FORMAT_L8, data)
		var texture := ImageTexture.create_from_image(image)
		var material := ShaderMaterial.new()
		material.shader = DUST_SHADER
		material.set_shader_parameter("dust_map", texture)
		material.set_shader_parameter("dust_min", bounds.position)
		material.set_shader_parameter("dust_size", size)
		mesh.material_overlay = material
		var highlight_mesh: MeshInstance3D
		if OS.is_debug_build():
			highlight_mesh = MeshInstance3D.new()
			highlight_mesh.name = "DustHighlight"
			highlight_mesh.mesh = mesh.mesh
			highlight_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var highlight_material := ShaderMaterial.new()
			highlight_material.shader = HIGHLIGHT_SHADER
			highlight_material.set_shader_parameter("dust_map", texture)
			highlight_material.set_shader_parameter("dust_min", bounds.position)
			highlight_material.set_shader_parameter("dust_size", size)
			highlight_mesh.material_override = highlight_material
			mesh.add_child(highlight_mesh)
			highlight_mesh.visible = false
		var surface := {"mesh": mesh, "owner": owner, "name": String(mesh.name), "bounds": bounds, "coverage": coverage,
			"size": size, "weights": weights, "data": data, "texture": texture, "highlight": highlight_mesh,
			"mass": mass, "remaining": mass}
		surfaces.append(surface)
		lookup[mesh] = surface
	jingle = AudioStreamPlayer.new()
	jingle.stream = preload("res://assets/sounds/clean_jingle.wav")
	jingle.volume_db = -4.0
	add_child(jingle)
	air = AudioStreamPlayer.new()
	var air_stream: AudioStreamWAV = preload("res://assets/sounds/compressed_air.wav").duplicate()
	air_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	air_stream.loop_begin = 72000 # 1.5 s at 48 kHz: skip the opening bursts on repeats.
	air_stream.loop_end = 278400 # 5.8 s: stop before the closing tail.
	air.stream = air_stream
	air.volume_db = -8.0
	add_child(air)
	changed.emit()

func _process(delta: float) -> void:
	if not OS.is_debug_build() or tools == null: return
	var held: bool = tools.equipped_tool == "dev-blower" and not tools.busy
	if held and not blower_held:
		blower_elapsed = 0.0
		auto_highlight_shown = false
	blower_held = held
	if blower_elapsed >= 0.0 and not auto_highlight_shown and not celebrated:
		blower_elapsed += delta
		if blower_elapsed >= 30.0:
			auto_highlight_shown = true
			set_highlight(true)
			notice.emit("Remaining dust highlighted. Rotate or remove parts to reach it.")

func set_highlight(value: bool) -> void:
	if not OS.is_debug_build(): return
	highlighted = value and not celebrated
	for surface in surfaces:
		var marker: MeshInstance3D = surface.highlight
		if marker != null: marker.visible = highlighted
	changed.emit()

func toggle_highlight() -> void:
	set_highlight(not highlighted)

func make_dust_mask(coverage: PackedByteArray, rng: RandomNumberGenerator) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(WIDTH * HEIGHT)
	for face in range(6):
		var tile_x: int = (face % 3) * TILE
		var tile_y: int = (face / 3) * TILE
		var center_a := Vector2(rng.randf_range(1.0, TILE - 2.0), rng.randf_range(1.0, TILE - 2.0))
		var center_b := Vector2(rng.randf_range(1.0, TILE - 2.0), rng.randf_range(1.0, TILE - 2.0))
		var candidates: Array[Dictionary] = []
		for y in range(tile_y, tile_y + TILE):
			for x in range(tile_x, tile_x + TILE):
				var index := y * WIDTH + x
				if coverage[index] == 0: continue
				var point := Vector2(x - tile_x, y - tile_y)
				var distance := minf(point.distance_squared_to(center_a), point.distance_squared_to(center_b))
				candidates.append({"index": index, "score": -distance + rng.randf_range(-4.0, 4.0)})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary): return a.score > b.score)
		for i in range(roundi(candidates.size() * DUST_COVERAGE)):
			data[candidates[i].index] = rng.randi_range(65, 104)
	return data

func face_for(normal: Vector3) -> int:
	var absolute := normal.abs()
	var axis := 0 if absolute.x > absolute.y and absolute.x > absolute.z else 1 if absolute.y > absolute.z else 2
	return axis * 2 + (1 if normal[axis] < 0.0 else 0)

func surface_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	# Imported triangle winding is opposite its rendered and picked normal.
	return -(b - a).cross(c - a).normalized()

func pixel(point: Vector3, face: int, minimum: Vector3, size: Vector3) -> Vector2:
	var axes: Array = AXES[face]
	return Vector2((point[axes[0]] - minimum[axes[0]]) / size[axes[0]] * (TILE - 2) + 1 + (face % 3) * TILE,
		(point[axes[1]] - minimum[axes[1]]) / size[axes[1]] * (TILE - 2) + 1 + (face / 3) * TILE)

func edge(a: Vector2, b: Vector2, p: Vector2) -> float:
	return (p.x - a.x) * (b.y - a.y) - (p.y - a.y) * (b.x - a.x)

func paint_triangle(coverage: PackedByteArray, a: Vector3, b: Vector3, c: Vector3, face: int, minimum: Vector3, size: Vector3) -> void:
	var p := pixel(a, face, minimum, size)
	var q := pixel(b, face, minimum, size)
	var r := pixel(c, face, minimum, size)
	var tile_x := (face % 3) * TILE
	var tile_y := (face / 3) * TILE
	var min_x := clampi(floori(minf(p.x, minf(q.x, r.x))), tile_x, tile_x + TILE - 1)
	var max_x := clampi(ceili(maxf(p.x, maxf(q.x, r.x))), tile_x, tile_x + TILE - 1)
	var min_y := clampi(floori(minf(p.y, minf(q.y, r.y))), tile_y, tile_y + TILE - 1)
	var max_y := clampi(ceili(maxf(p.y, maxf(q.y, r.y))), tile_y, tile_y + TILE - 1)
	var painted := false
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var sample := Vector2(x + 0.5, y + 0.5)
			var e0 := edge(p, q, sample)
			var e1 := edge(q, r, sample)
			var e2 := edge(r, p, sample)
			if (e0 >= 0.0 and e1 >= 0.0 and e2 >= 0.0) or (e0 <= 0.0 and e1 <= 0.0 and e2 <= 0.0):
				coverage[y * WIDTH + x] = 1
				painted = true
	if not painted:
		coverage[clampi(roundi((p.y + q.y + r.y) / 3.0), tile_y, tile_y + TILE - 1) * WIDTH +
			clampi(roundi((p.x + q.x + r.x) / 3.0), tile_x, tile_x + TILE - 1)] = 1

func part_progress(owner: String) -> float:
	var total := 0.0
	var left := 0.0
	for surface in surfaces:
		if surface.owner != owner: continue
		total += surface.mass
		left += surface.remaining
	return 1.0 - left / total if total > 0.0 else 1.0

func remaining_hint() -> String:
	var worst: Dictionary = {}
	for surface in surfaces:
		if worst.is_empty() or surface.remaining > worst.remaining: worst = surface
	return "No dust remains" if worst.is_empty() or worst.remaining <= 0.0 else "Most remaining: " + String(worst.name).replace("-", " ")

func begin() -> void:
	if tools.equipped_tool == "dev-blower" and not celebrated:
		blowing = true
		if not muted: air.play()

func end() -> void:
	blowing = false
	target_part = ""
	if air != null: air.stop()

func blow_at(screen: Vector2, delta: float, hit: Dictionary = {}) -> void:
	if not blowing or tools.equipped_tool != "dev-blower": return
	if hit.is_empty(): hit = picker.surface_hit_at(screen, true)
	var mesh: MeshInstance3D = hit.get("mesh")
	target_part = lookup[mesh].owner if lookup.has(mesh) and tools.blower_points_at(hit.point) else ""
	if target_part == "": return
	if clean_at(mesh, hit.point, hit.normal, minf(delta, 0.05) * 30.0, 1.1) > 0.0:
		finish_if_ready()

func clean_at(mesh: MeshInstance3D, world_point: Vector3, local_normal: Vector3, seconds: float, radius: float) -> float:
	if not lookup.has(mesh) or celebrated: return 0.0
	var surface: Dictionary = lookup[mesh]
	var face := face_for(local_normal)
	var axes: Array = AXES[face]
	var center := pixel(mesh.to_local(world_point), face, surface.bounds.position, surface.size)
	var scale_u: float = (mesh.global_basis * Vector3(1 if axes[0] == 0 else 0, 1 if axes[0] == 1 else 0, 1 if axes[0] == 2 else 0)).length()
	var scale_v: float = (mesh.global_basis * Vector3(1 if axes[1] == 0 else 0, 1 if axes[1] == 1 else 0, 1 if axes[1] == 2 else 0)).length()
	var rx: float = radius / maxf(scale_u * surface.size[axes[0]], 0.001) * (TILE - 2)
	var ry: float = radius / maxf(scale_v * surface.size[axes[1]], 0.001) * (TILE - 2)
	var tile_x := (face % 3) * TILE
	var tile_y := (face / 3) * TILE
	var data: PackedByteArray = surface.data
	var removed := 0.0
	for y in range(maxi(tile_y, floori(center.y - ry)), mini(tile_y + TILE - 1, ceili(center.y + ry)) + 1):
		for x in range(maxi(tile_x, floori(center.x - rx)), mini(tile_x + TILE - 1, ceili(center.x + rx)) + 1):
			var falloff := maxf(0.0, 1.0 - pow((x - center.x) / rx, 2.0) - pow((y - center.y) / ry, 2.0))
			var index := y * WIDTH + x
			var amount := mini(data[index], roundi(seconds * 360.0 * falloff))
			data[index] -= amount
			removed += amount * surface.weights[face]
	if removed > 0.0:
		surface.data = data
		surface.remaining = maxf(0.0, surface.remaining - removed)
		surface.texture.update(Image.create_from_data(WIDTH, HEIGHT, false, Image.FORMAT_L8, data))
		changed.emit()
	return removed

func clean_all() -> void:
	for surface in surfaces:
		var data: PackedByteArray = surface.data
		data.fill(0)
		surface.data = data
		surface.remaining = 0.0
		surface.texture.update(Image.create_from_data(WIDTH, HEIGHT, false, Image.FORMAT_L8, data))
	changed.emit()

func clean_part(owner: String) -> void:
	for surface in surfaces:
		if surface.owner != owner: continue
		var data: PackedByteArray = surface.data
		data.fill(0)
		surface.data = data
		surface.remaining = 0.0
		surface.texture.update(Image.create_from_data(WIDTH, HEIGHT, false, Image.FORMAT_L8, data))
	changed.emit()

func finish_if_ready() -> bool:
	if celebrated: return false
	var newly_clean: Array[String] = []
	for owner in ["board", "fan-assembly", "cooler-assembly"]:
		if not completed_parts.has(owner) and part_progress(owner) >= 0.98:
			clean_part(owner)
			completed_parts[owner] = true
			newly_clean.append(owner)
			completed_count += 1
			if not muted: jingle.play()
			notice.emit("%s clean!" % owner.replace("-assembly", "").capitalize())
	if completed_parts.size() == 3:
		celebrated = true
		end()
		set_highlight(false)
		notice.emit("Spotless! The GPU is 100% clean.")
	return not newly_clean.is_empty()

func set_muted(value: bool) -> void:
	muted = value
	if muted:
		jingle.stop()
		air.stop()
	elif blowing: air.play()

func _exit_tree() -> void:
	if jingle != null: jingle.stop()
	if air != null: air.stop()
	for surface in surfaces:
		if is_instance_valid(surface.mesh): surface.mesh.material_overlay = null
	lookup.clear()
	surfaces.clear()
