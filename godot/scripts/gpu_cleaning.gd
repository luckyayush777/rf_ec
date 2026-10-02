extends Node
## Independent local-space dust masks stay with each mesh during removal and refit.
## Mask bytes are dust thickness: thin film near FILM, the thickest felt near FELT.
const AudioMix = preload("res://scripts/audio_mix.gd")
const Contract = preload("res://scripts/asset_contract.gd")
const DustPuffs = preload("res://scripts/dust_puffs.gd")
signal changed
signal notice(text: String)
## The shop blower's jet is on the fan rotor this frame; testing_station.gd spins it.
signal fan_blown

const TILE := 64
const WIDTH := TILE * 3
const HEIGHT := TILE * 2
## Dust is a near-continuous haze with a few bare gaps, not separate blotches.
const DUST_COVERAGE := 0.85
const FILM := 40
const FELT := 245
## World size of the settled clumps the mask is built from, whatever the part's size.
const CLUMP := 0.04
const AXES := [[2, 1], [2, 1], [0, 2], [0, 2], [0, 1], [0, 1]]
const DUST_SHADER = preload("res://shaders/dust_overlay.gdshader")
const HIGHLIGHT_SHADER = preload("res://shaders/dust_highlight.gdshader")
## The Dev blower clears a wide footprint on the one surface it points at.
const DEV_RADIUS := 1.1
## The shop blower is a narrow jet: full strength on the aimed surface, a share of it on
## faces the air carries into just behind (fin gaps, blades under the hub).
const AIR_RADIUS := 0.13
const AIR_DEPTH := 0.12
const AIR_STRENGTH := 5.0
const AIR_SPLASH := 0.35
## A supplied recording replaces the synthesized placeholder motor.
const MOTOR_RECORDING := "res://assets/sounds/air_blower.wav"
const MOTOR_TRIM_DB := -7.0

var surfaces: Array[Dictionary] = []
var lookup: Dictionary = {}
var picker: RefCounted
var tools: Node
var rotor: Node3D
var puffs: MultiMeshInstance3D
var motor: AudioStreamPlayer
var motor_level := 0.0
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
## Kept so each new job can lay fresh dust (reset_dust) with the same airflow weighting.
var dust_rng := RandomNumberGenerator.new()

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
	rotor = card.find_child("fan-rotor", true, false)
	var rng := dust_rng
	rng.randomize()
	var noise_texture := make_noise_texture(rng)
	var context := airflow_context(card)
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
		var affinity := PackedFloat32Array()
		affinity.resize(WIDTH * HEIGHT)
		var deposit := {"transform": mesh.global_transform, "owner": owner, "outward": Vector3.UP, "context": context}
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
				deposit.outward = outward
				paint_triangle(coverage, a, b, c, face_for(normal), bounds.position, size, affinity, deposit)
		var weights: Array[float] = []
		var texels: Array[float] = []
		var axis_scale := Vector3(mesh.global_basis.x.length(), mesh.global_basis.y.length(), mesh.global_basis.z.length())
		for axes in AXES:
			weights.append(size[axes[0]] * size[axes[1]] / float((TILE - 2) * (TILE - 2)))
			texels.append((axis_scale[axes[0]] * size[axes[0]] + axis_scale[axes[1]] * size[axes[1]]) * 0.5 / float(TILE - 2))
		var data := make_dust_mask(coverage, rng, affinity, texels)
		# Faces with any mask pixels; the air blower's spread skips the rest.
		var faces: Array[int] = []
		for face in range(6):
			for y in range((face / 3) * TILE, (face / 3 + 1) * TILE):
				if coverage.slice(y * WIDTH + (face % 3) * TILE, y * WIDTH + (face % 3 + 1) * TILE).has(1):
					faces.append(face)
					break
		var mass := mask_mass(data, weights)
		if mass <= 0.0: continue
		var image := Image.create_from_data(WIDTH, HEIGHT, false, Image.FORMAT_L8, data)
		var texture := ImageTexture.create_from_image(image)
		var material := ShaderMaterial.new()
		material.shader = DUST_SHADER
		material.set_shader_parameter("dust_map", texture)
		material.set_shader_parameter("dust_noise", noise_texture)
		material.set_shader_parameter("dust_min", bounds.position)
		material.set_shader_parameter("dust_size", size)
		material.set_shader_parameter("unit_scale", (axis_scale.x + axis_scale.y + axis_scale.z) / 3.0)
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
		var surface := {"mesh": mesh, "owner": owner, "name": String(mesh.name), "bounds": bounds, "coverage": coverage, "faces": faces,
			"size": size, "weights": weights, "data": data, "texture": texture, "highlight": highlight_mesh,
			"mass": mass, "remaining": mass, "affinity": affinity, "texels": texels}
		surfaces.append(surface)
		lookup[mesh] = surface
	jingle = AudioStreamPlayer.new()
	jingle.stream = preload("res://assets/sounds/clean_jingle.wav")
	jingle.volume_db = -4.0
	jingle.bus = AudioMix.JINGLE
	add_child(jingle)
	air = AudioStreamPlayer.new()
	var air_stream: AudioStreamWAV = preload("res://assets/sounds/compressed_air.wav").duplicate()
	air_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	air_stream.loop_begin = 72000 # 1.5 s at 48 kHz: skip the opening bursts on repeats.
	air_stream.loop_end = 278400 # 5.8 s: stop before the closing tail.
	air.stream = air_stream
	air.volume_db = -8.0
	air.bus = AudioMix.BLOWER
	add_child(air)
	motor = AudioStreamPlayer.new()
	motor.name = "AirBlowerMotor"
	motor.stream = load(MOTOR_RECORDING) if ResourceLoader.exists(MOTOR_RECORDING) else make_motor_stream()
	motor.volume_db = -80.0
	motor.bus = AudioMix.AIR_BLOWER
	add_child(motor)
	puffs = DustPuffs.new()
	add_child(puffs)
	changed.emit()

func _process(delta: float) -> void:
	update_motor(delta)
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

## Picks the dustiest DUST_COVERAGE of each face: where air and gravity deposit it (affinity)
## times clumpy noise. Thickness grows toward each patch's heaviest spot.
func make_dust_mask(coverage: PackedByteArray, rng: RandomNumberGenerator, affinity := PackedFloat32Array(), texels: Array[float] = []) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(WIDTH * HEIGHT)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 3
	noise.seed = rng.randi()
	for face in range(6):
		var tile_x: int = (face % 3) * TILE
		var tile_y: int = (face / 3) * TILE
		var indices := PackedInt32Array()
		for y in range(tile_y, tile_y + TILE):
			for x in range(tile_x, tile_x + TILE):
				if coverage[y * WIDTH + x] != 0: indices.append(y * WIDTH + x)
		if indices.is_empty(): continue
		noise.frequency = (texels[face] if face < texels.size() else 0.02) / CLUMP
		noise.offset = Vector3(rng.randf_range(0.0, 4096.0), rng.randf_range(0.0, 4096.0), 0.0)
		var image := noise.get_image(TILE, TILE)
		image.convert(Image.FORMAT_L8)
		var clumps := image.get_data()
		# Clumpy noise mostly decides where dust lies; airflow and gravity decide how thick it
		# builds, so exposed faces keep a film while the inlet and exhaust zones pack into felt.
		var scores := PackedFloat32Array()
		var loads := PackedFloat32Array()
		scores.resize(indices.size())
		loads.resize(indices.size())
		for i in range(indices.size()):
			var index := indices[i]
			var weight: float = affinity[index] if not affinity.is_empty() else 1.0
			var local := (index / WIDTH - tile_y) * TILE + index % WIDTH - tile_x
			var clump := clumps[local] / 255.0
			scores[i] = clump * (0.6 + 0.4 * clampf(weight, 0.0, 1.5)) + rng.randf() * 0.01
			loads[i] = smoothstep(0.75, 1.5, weight) * (0.55 + 0.45 * clump)
		var ranked := scores.duplicate()
		ranked.sort()
		var keep := roundi(indices.size() * DUST_COVERAGE)
		if keep == 0: continue
		var threshold: float = ranked[indices.size() - keep]
		var span := maxf(ranked[indices.size() - 1] - threshold, 0.0001)
		for i in range(indices.size()):
			if scores[i] < threshold: continue
			# Each patch also thickens toward its middle.
			var depth := clampf(0.35 * (scores[i] - threshold) / span + 0.65 * loads[i], 0.0, 1.0)
			data[indices[i]] = roundi(lerpf(FILM, FELT, depth))
	return data

func mask_mass(data: PackedByteArray, weights: Array[float]) -> float:
	var mass := 0.0
	for index in range(data.size()):
		if data[index] == 0: continue
		var face: int = (index / WIDTH / TILE) * 3 + (index % WIDTH) / TILE
		mass += data[index] * weights[face]
	return mass

## A new card on the bench: lay a fresh randomized coat of dust, or start it clean. A clean
## card counts every part as done without the jingle.
func reset_dust(dusty: bool) -> void:
	end()
	set_highlight(false)
	celebrated = false
	completed_parts.clear()
	completed_count = 0
	blower_elapsed = -1.0
	auto_highlight_shown = false
	for surface in surfaces:
		var data: PackedByteArray = make_dust_mask(surface.coverage, dust_rng, surface.affinity, surface.texels) if dusty else PackedByteArray()
		if not dusty: data.resize(WIDTH * HEIGHT)
		surface.data = data
		if dusty: surface.mass = mask_mass(data, surface.weights)
		surface.remaining = surface.mass if dusty else 0.0
		surface.texture.update(Image.create_from_data(WIDTH, HEIGHT, false, Image.FORMAT_L8, data))
	if not dusty:
		for owner in ["board", "fan-assembly", "cooler-assembly"]: completed_parts[owner] = true
		completed_count = 3
		celebrated = true
	changed.emit()

## Seamless clump/fibre noise shared by every dust overlay.
func make_noise_texture(rng: RandomNumberGenerator) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 4
	noise.frequency = 0.05
	noise.seed = rng.randi()
	var image := noise.get_seamless_image(128, 128)
	image.convert(Image.FORMAT_L8)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

## Where the card's air moves: the fan's axis, centre and blade radius, and the cooler footprint
## whose fin exhaust spills dust over the board. Taken once, with the card in its holder.
func airflow_context(card: Node3D) -> Dictionary:
	var housing := card.find_child("fan-housing", true, false) as MeshInstance3D
	if rotor == null or housing == null: return {}
	var ring: AABB = housing.global_transform * housing.get_aabb()
	var context := {"center": rotor.global_position, "axis": rotor.get_parent().global_basis.y.normalized(),
		"radius": maxf(maxf(ring.size.x, ring.size.z) * 0.5, 0.001)}
	var cooler := card.find_child("cooler-assembly", true, false) as Node3D
	if cooler != null: context.cooler = cooler.global_transform * Contract.bounds_in(cooler)
	return context

## How readily dust settles at a mesh-local point: upward faces collect it, fin tops under the
## blade sweep catch the intake felt, fan blades load up toward the hub, and the board gathers
## what the fin exhaust spills around the cooler.
func deposit_weight(deposit: Dictionary, local_point: Vector3) -> float:
	if deposit.is_empty(): return 1.0
	var outward: Vector3 = deposit.outward
	var settle := clampf(outward.y, 0.0, 1.0)
	var context: Dictionary = deposit.context
	if context.is_empty(): return 0.5 + 0.5 * settle
	var point: Vector3 = deposit.transform * local_point
	var offset: Vector3 = point - context.center
	var axis: Vector3 = context.axis
	var radial: float = (offset - axis * offset.dot(axis)).length() / context.radius
	match deposit.owner:
		"fan-assembly":
			return 0.45 + 0.35 * settle + 0.5 * clampf(1.0 - radial, 0.0, 1.0)
		"cooler-assembly":
			# The hub shadows the centre; the blade sweep packs the fin inlet.
			var sweep := smoothstep(0.2, 0.45, radial) * (1.0 - smoothstep(0.95, 1.3, radial))
			return 0.3 + 0.25 * settle + sweep * clampf(outward.dot(axis), 0.0, 1.0)
	var spill := 0.35
	if context.has("cooler"):
		var box: AABB = context.cooler
		var outside := Vector2(maxf(maxf(box.position.x - point.x, point.x - box.end.x), 0.0),
			maxf(maxf(box.position.z - point.z, point.z - box.end.z), 0.0)).length()
		if outside > 0.0: spill = exp(-outside / 0.12)
	return 0.3 + 0.4 * settle + 0.7 * spill

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

## Marks the triangle's mask pixels and, when given, keeps the strongest deposit weight of the
## triangles covering each pixel, evaluated at that pixel's point on the triangle.
func paint_triangle(coverage: PackedByteArray, a: Vector3, b: Vector3, c: Vector3, face: int, minimum: Vector3, size: Vector3,
		affinity := PackedFloat32Array(), deposit: Dictionary = {}) -> void:
	var p := pixel(a, face, minimum, size)
	var q := pixel(b, face, minimum, size)
	var r := pixel(c, face, minimum, size)
	var tile_x := (face % 3) * TILE
	var tile_y := (face / 3) * TILE
	var min_x := clampi(floori(minf(p.x, minf(q.x, r.x))), tile_x, tile_x + TILE - 1)
	var max_x := clampi(ceili(maxf(p.x, maxf(q.x, r.x))), tile_x, tile_x + TILE - 1)
	var min_y := clampi(floori(minf(p.y, minf(q.y, r.y))), tile_y, tile_y + TILE - 1)
	var max_y := clampi(ceili(maxf(p.y, maxf(q.y, r.y))), tile_y, tile_y + TILE - 1)
	var area := edge(p, q, r)
	var painted := false
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var sample := Vector2(x + 0.5, y + 0.5)
			var e0 := edge(p, q, sample)
			var e1 := edge(q, r, sample)
			var e2 := edge(r, p, sample)
			if (e0 >= 0.0 and e1 >= 0.0 and e2 >= 0.0) or (e0 <= 0.0 and e1 <= 0.0 and e2 <= 0.0):
				var index := y * WIDTH + x
				coverage[index] = 1
				painted = true
				# The first triangle over a pixel sets its weight; faces sharing a pixel lie close together.
				if not affinity.is_empty() and affinity[index] == 0.0:
					var point := (a + b + c) / 3.0 if absf(area) < 0.0001 else (a * e1 + b * e2 + c * e0) / area
					affinity[index] = deposit_weight(deposit, point)
	if not painted:
		var index := clampi(roundi((p.y + q.y + r.y) / 3.0), tile_y, tile_y + TILE - 1) * WIDTH + clampi(roundi((p.x + q.x + r.x) / 3.0), tile_x, tile_x + TILE - 1)
		coverage[index] = 1
		if not affinity.is_empty() and affinity[index] == 0.0:
			affinity[index] = deposit_weight(deposit, (a + b + c) / 3.0)

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

## The Dev blower plays its air recording during a hold. The shop blower's motor runs even on a
## clean card, so it can still spin the fan; update_motor() winds it up and down.
func begin() -> void:
	if tools.equipped_tool == "dev-blower" and not celebrated:
		blowing = true
		if not muted: air.play()
	elif tools.equipped_tool == "air-blower":
		blowing = true

func end() -> void:
	blowing = false
	target_part = ""
	if air != null: air.stop()

## jet: air direction; defaults to the held nozzle axis. subject limits the shop blower's
## spread to the part in a close-up.
func blow_at(screen: Vector2, delta: float, hit: Dictionary = {}, jet := Vector3.ZERO, subject: Node3D = null) -> void:
	if not blowing or not tools.blower_equipped(): return
	if hit.is_empty(): hit = picker.surface_hit_at(screen, true)
	var mesh: MeshInstance3D = hit.get("mesh")
	if mesh == null or not tools.blower_points_at(hit.point):
		target_part = ""
		return
	target_part = lookup[mesh].owner if lookup.has(mesh) else ""
	if tools.equipped_tool == "dev-blower":
		if target_part != "" and clean_at(mesh, hit.point, hit.normal, minf(delta, 0.05) * 30.0, DEV_RADIUS) > 0.0:
			finish_if_ready()
		return
	if rotor != null and rotor.is_ancestor_of(mesh): fan_blown.emit()
	if blast(hit, (jet if jet != Vector3.ZERO else tools.blower_axis()).normalized(), minf(delta, 0.05) * AIR_STRENGTH, subject) > 0.0:
		finish_if_ready()

## The shop blower's jet. Air carries past the aimed surface into faces that turn toward it
## within AIR_DEPTH, so blowing down a fin stack or through the fan cleans what lies under it.
func blast(hit: Dictionary, jet: Vector3, seconds: float, subject: Node3D = null) -> float:
	var center: Vector3 = hit.point
	var primary: MeshInstance3D = hit.mesh
	var removed := clean_at(primary, center, hit.normal, seconds, AIR_RADIUS, jet)
	for surface in surfaces:
		var mesh: MeshInstance3D = surface.mesh
		if mesh == primary or surface.remaining <= 0.0 or not mesh.is_visible_in_tree(): continue
		if subject != null and mesh != subject and not subject.is_ancestor_of(mesh): continue
		var box: AABB = mesh.global_transform * surface.bounds
		var offset: Vector3 = center.clamp(box.position, box.end) - center
		var depth := offset.dot(jet)
		if offset.length() > AIR_RADIUS or depth < -AIR_RADIUS * 0.5 or depth > AIR_DEPTH: continue
		for face in surface.faces:
			var local_normal := Vector3.ZERO
			local_normal[face / 2] = -1.0 if face % 2 == 1 else 1.0
			var facing := -(mesh.global_basis * local_normal).normalized().dot(jet)
			if facing > 0.2:
				removed += clean_at(mesh, center, local_normal, seconds * AIR_SPLASH * facing, AIR_RADIUS, jet)
	return removed

## Thick felt lifts in clumps; the last thin film clings and needs steady air. Lifted dust
## leaves as a cloud from the cleaned spot.
func clean_at(mesh: MeshInstance3D, world_point: Vector3, local_normal: Vector3, seconds: float, radius: float, jet := Vector3.ZERO) -> float:
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
	var lifted := 0
	var felt := 0
	for y in range(maxi(tile_y, floori(center.y - ry)), mini(tile_y + TILE - 1, ceili(center.y + ry)) + 1):
		for x in range(maxi(tile_x, floori(center.x - rx)), mini(tile_x + TILE - 1, ceili(center.x + rx)) + 1):
			var index := y * WIDTH + x
			var value: int = data[index]
			if value == 0: continue
			var falloff := 1.0 - pow((x - center.x) / rx, 2.0) - pow((y - center.y) / ry, 2.0)
			if falloff <= 0.0: continue
			var amount := mini(value, roundi(seconds * falloff * (360.0 + value * 1.2)))
			data[index] = value - amount
			removed += amount * surface.weights[face]
			lifted += amount
			if value > 150: felt += amount
	if removed > 0.0:
		surface.data = data
		surface.remaining = maxf(0.0, surface.remaining - removed)
		surface.texture.update(Image.create_from_data(WIDTH, HEIGHT, false, Image.FORMAT_L8, data))
		var normal := (mesh.global_basis * local_normal).normalized()
		puffs.burst(world_point, normal, jet if jet != Vector3.ZERO else -normal, lifted, felt)
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

func debug_clean() -> bool:
	if not OS.is_debug_build() or celebrated: return false
	end()
	clean_all()
	finish_if_ready(false)
	return true

func clean_part(owner: String) -> void:
	for surface in surfaces:
		if surface.owner != owner: continue
		var data: PackedByteArray = surface.data
		data.fill(0)
		surface.data = data
		surface.remaining = 0.0
		surface.texture.update(Image.create_from_data(WIDTH, HEIGHT, false, Image.FORMAT_L8, data))
	changed.emit()

func finish_if_ready(play_audio: bool = true) -> bool:
	if celebrated: return false
	var newly_clean: Array[String] = []
	for owner in ["board", "fan-assembly", "cooler-assembly"]:
		if not completed_parts.has(owner) and part_progress(owner) >= 0.98:
			clean_part(owner)
			completed_parts[owner] = true
			newly_clean.append(owner)
			completed_count += 1
			if play_audio and not muted: jingle.play()
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
	elif blowing and tools.equipped_tool == "dev-blower": air.play()

func update_motor(delta: float) -> void:
	if motor == null or tools == null: return
	var target := 1.0 if blowing and tools.equipped_tool == "air-blower" else 0.0
	# The motor winds up fast and coasts down after the trigger is released.
	motor_level = move_toward(motor_level, target, delta * (3.5 if target > motor_level else 1.6))
	if motor_level <= 0.0:
		if motor.playing: motor.stop()
		return
	if not motor.playing: motor.play()
	motor.pitch_scale = lerpf(0.4, 1.0, motor_level)
	motor.volume_db = -80.0 if muted else linear_to_db(motor_level) + MOTOR_TRIM_DB

## Placeholder until a recording is supplied: a motor hum and whine over broadband air rush.
## Every tone completes whole cycles in the one-second buffer, so it loops seamlessly.
func make_motor_stream() -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	data.resize(rate * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4410
	var fast := 0.0
	var slow := 0.0
	for n in range(rate):
		var t := float(n) / rate
		var noise := rng.randf_range(-1.0, 1.0)
		fast += (noise - fast) * 0.6
		slow += (noise - slow) * 0.05
		var hum := 0.16 * sin(TAU * 150.0 * t) + 0.07 * sin(TAU * 300.0 * t) + 0.03 * sin(TAU * 450.0 * t)
		var whine := 0.05 * sin(TAU * 1500.0 * t + 0.4 * sin(TAU * 6.0 * t))
		var rush := (fast - slow) * (0.55 + 0.08 * sin(TAU * 3.0 * t))
		data.encode_s16(n * 2, clampi(roundi((hum + whine + rush) * 0.6 * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = rate
	return stream

func _exit_tree() -> void:
	if jingle != null: jingle.stop()
	if air != null: air.stop()
	if motor != null:
		motor.stop()
		motor.stream = null
	for surface in surfaces:
		if is_instance_valid(surface.mesh): surface.mesh.material_overlay = null
	lookup.clear()
	surfaces.clear()
