extends Node
## Thermal paste between the GPU die and the heatsink base.
## Each contact face owns a runtime grid layer parented to its part, so old compound, film
## and fresh paste travel with the heatsink. Cell (i, j) on the die faces the heatsink cell
## returned by mirror(); the heatsink layer is flipped to face outward.
## Old compound is a stack per cell, top to bottom: a hard, brittle glaze; the chalky dried
## body (crust); a pasty, oily base (gum) that smears under a blade; then the residue film.
## Its thickness varies like real pumped-out paste: thin in the middle, a ridge toward the
## die edges, lumps and fissures, and torn peaks where the heatsink pulled it apart.
## Contact quality runs from 0 (air gap) to 1 (full fresh bond) and is evaluated when
## the heatsink seats, after the paste spreads under pressure.
signal changed
signal notice(text: String)
## Hard glaze broke off under the blade at this world point; the dust puffs throw chips.
signal chipped(point: Vector3, normal: Vector3, count: int)
## Scraped-off compound leaving the face: chalky crust crumbs pushed ahead of the blade, or
## a clump of gum and crust dropping off its loaded edge. The dust puffs draw them.
signal shed(point: Vector3, normal: Vector3, direction: Vector3, count: int, color: Color, size: float)
## Material used up, for the job's bill of materials (bill_of_materials.gd item ids).
signal consumed(item: String, quantity: float)

const INNER := 20
const MARGIN := 4
const N := INNER + MARGIN * 2
## Paste thickness per cell for a full, even bond line; the die holds INNER * INNER of it.
const BOND := 1.0
const IDEAL_VOLUME := BOND * INNER * INNER
## Per-cell contact through old dried compound.
const DRIED_CONTACT := 0.16
## Residue at or below this fraction auto-clears, like the blower's 98% rule.
const CLEAN_THRESHOLD := 0.05
## Thickness drawn at full bead height.
const DISPLAY_THICKNESS := 3.0
const SQUEEZE_RATE := 110.0
## Grams of compound in IDEAL_VOLUME: a pea-sized dot for a small die.
const IDEAL_GRAMS := 0.3
## Spudger removal per second at full brush strength. Glaze resists until the blade gets
## under an exposed edge, then chips away CHIP_BOOST times faster.
const GLAZE_RATE := 1.4
const CHIP_BOOST := 4.0
const CRUST_RATE := 3.0
## Gum is disturbed at GUM_RATE; SMEAR of it is pushed ahead of the blade instead of lifted.
const GUM_RATE := 1.8
const SMEAR := 0.45
## The IPA wipe dissolves exposed gum more slowly than it lifts film.
const WIPE_GUM_RATE := 1.2
## Dried thickness drawn at full relief; shared with paste_layer.gdshader's packing.
const STACK_DISPLAY := 2.0
## Thin glaze chips per chip particle.
const GLAZE_PER_CHIP := 0.06
## Crust removed per crumb pushed off ahead of the blade.
const CRUST_PER_CRUMB := 0.5
## Compound collects on the spudger's edge as it ploughs; at 1.0 a clump drops off.
const BLADE_PICKUP := 0.08
const CLUMP_SHED := 0.7
## Residue lifted until the IPA pad is fully grey.
const PAD_CAPACITY := 60.0
## Removal per second (stack units) that drives a tool's sound to full.
const FULL_SOUND := 6.0
const CRUMB_COLOR := Color(0.8, 0.79, 0.74)
const CLUMP_COLOR := Color(0.55, 0.55, 0.52)
const SHADER = preload("res://shaders/paste_layer.gdshader")
const AudioMix = preload("res://scripts/audio_mix.gd")
const ContactLoop = preload("res://scripts/contact_loop.gd")
## Supplied loops for the tools at work; each is silent until its file exists.
const SCRAPE_RECORDING := "res://assets/sounds/spudger_scrape.wav"
const WIPE_RECORDING := "res://assets/sounds/ipa_wipe.wav"
const SQUEEZE_RECORDING := "res://assets/sounds/paste_squeeze.wav"
## Movement within 90 degrees of the stroke's heading (cosine above STROKE_TURN) bends it by
## STROKE_FOLLOW per step; anything further back is ignored, so a stroke never turns around.
const STROKE_TURN := 0.0
const STROKE_FOLLOW := 0.3
## Until the pointer travels this many cells from where LMB went down, the stroke is still
## being aimed: circling the mouse turns the blade freely. Past it, the heading locks.
const AIM_RADIUS := 3.0
const WORK := {"spudger": "scrape", "ipa-wipe": "wipe", "paste-syringe": "apply"}
const SURFACES := [
	{"id": "die", "exposedBy": "cooler-assembly", "applyPaste": true, "label": "GPU die"},
	{"id": "heatsink", "exposedBy": "cooler-assembly", "label": "heatsink base"}]

var bench: Node3D
## Development tuning only; the brush footprint and service rules stay the same.
var debug_scrape_speed := 1.0
var debug_wipe_speed := 1.0
var faces: Dictionary = {}
var quality := 0.0
var dried := true
var seated := true
var working := false
var work_kind := ""
## Result of the last spread: coverage, overflow and volume.
var report: Dictionary = {}
var neighbors: Array = []
var last_denial := ""
var denial_time := 0.0
var jingle: AudioStreamPlayer
var muted := false
## The previous brush cell of the current stroke, so gum is pushed the way the blade moves.
var last_cell := Vector2.ZERO
var last_face := ""
var chip_budget := 0.0
var crumb_budget := 0.0
## What the last scrape or wipe step removed, per layer (stack units).
var takes: Dictionary = {}
## Compound riding on the spudger's edge (0-1) and grime on the IPA pad (0-1); both stay with
## the tool until a different paste tool is used.
var blade_load := 0.0
var pad_soil := 0.0
var loaded_tool := ""
var scrape_sound: AudioStreamPlayer
var wipe_sound: AudioStreamPlayer
var squeeze_sound: AudioStreamPlayer
## The current stroke's heading in cell space, set by its first real movement and kept until
## release. It can bend through a curve but ignores motion back against it.
var stroke_dir := Vector2.ZERO
## Where this press touched down, and whether its heading is still free to turn.
var press_cell := Vector2.ZERO
var aiming := true

func configure(world: Node3D) -> void:
	bench = world
	var die: MeshInstance3D = bench.gpu.find_child("gpu-die", true, false)
	var base: MeshInstance3D = bench.gpu.find_child("heatsink-base", true, false)
	var bounds := die.get_aabb()
	var span := float(N) / INNER
	var size := Vector2(bounds.size.x * span, bounds.size.z * span)
	var die_layer := make_layer("paste-die", size, bounds.size.y)
	die.add_child(die_layer)
	var top := Vector3(bounds.get_center().x, bounds.end.y, bounds.get_center().z)
	die_layer.position = top + Vector3(0, 0.002, 0)
	# The same footprint on the base underside, measured while the heatsink is seated.
	var ratio: float = die.global_basis.get_scale().x / base.global_basis.get_scale().x
	var sink_layer := make_layer("paste-heatsink", size * ratio, 0.0)
	base.add_child(sink_layer)
	var center := base.to_local(die.to_global(top))
	sink_layer.position = Vector3(center.x, base.get_aabb().position.y - 0.002, center.z)
	sink_layer.rotation = Vector3(PI, 0, 0)
	faces = {"die": new_face(die_layer), "heatsink": new_face(sink_layer)}
	for k in range(N * N):
		var list: Array = []
		var i := k % N
		var j := k / N
		if is_inner(i, j):
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				list.append([(j + offset.y) * N + i + offset.x, 0.17])
			for offset in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
				list.append([(j + offset.y) * N + i + offset.x, 0.08])
		neighbors.append(list)
	jingle = AudioStreamPlayer.new()
	jingle.stream = preload("res://assets/sounds/clean_jingle.wav")
	jingle.volume_db = -4.0
	jingle.bus = AudioMix.JINGLE
	add_child(jingle)
	scrape_sound = ContactLoop.new("SpudgerScrape", SCRAPE_RECORDING, AudioMix.SPUDGER)
	add_child(scrape_sound)
	wipe_sound = ContactLoop.new("IpaWipeSound", WIPE_RECORDING, AudioMix.IPA_WIPE)
	add_child(wipe_sound)
	squeeze_sound = ContactLoop.new("PasteSqueezeSound", SQUEEZE_RECORDING, AudioMix.PASTE_SQUEEZE)
	add_child(squeeze_sound)
	reset_dried()

func make_layer(layer_name: String, size: Vector2, drop: float) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.subdivide_width = N * 2 - 1
	mesh.subdivide_depth = N * 2 - 1
	var layer := MeshInstance3D.new()
	layer.name = layer_name
	layer.mesh = mesh
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("margin_fraction", float(MARGIN) / N)
	material.set_shader_parameter("margin_drop", drop)
	material.set_shader_parameter("bead_height", 0.05)
	# Exaggerated well beyond a real bond line so ridges and scraped terraces read on screen.
	material.set_shader_parameter("stack_height", 0.055)
	material.set_shader_parameter("layer_size", size)
	material.set_shader_parameter("cells", float(N))
	layer.material_override = material
	return layer

func new_face(layer: MeshInstance3D) -> Dictionary:
	var empty := PackedFloat32Array()
	empty.resize(N * N)
	var texture := ImageTexture.create_from_image(Image.create(N, N, false, Image.FORMAT_RGBA8))
	var gum_texture := ImageTexture.create_from_image(Image.create(N, N, false, Image.FORMAT_R8))
	var material := layer.material_override as ShaderMaterial
	material.set_shader_parameter("paste_map", texture)
	material.set_shader_parameter("gum_map", gum_texture)
	return {"mesh": layer, "texture": texture, "gum_texture": gum_texture, "glaze": empty.duplicate(),
		"crust": empty.duplicate(), "gum": empty.duplicate(), "film": empty.duplicate(),
		"paste": empty.duplicate(), "initial": 0.0, "clean": false}

func is_inner(i: int, j: int) -> bool:
	return i >= MARGIN and i < N - MARGIN and j >= MARGIN and j < N - MARGIN

func mirror(k: int) -> int:
	return (N - 1 - k / N) * N + k % N

## A ray can slip through the subdivided layer at a shared vertex and strike the part
## beneath; that part's own contact face counts as the layer.
func face_of(mesh: Object) -> String:
	for id in faces:
		if faces[id].mesh == mesh or faces[id].mesh.get_parent() == mesh: return id
	return ""

func contact_quality() -> float:
	return quality

func is_fresh() -> bool:
	return quality >= 0.99

## Old compound, years in. Heat cycles pumped it outward, leaving the middle thin and a ridge
## toward the die edges. The air-exposed rim dried hardest (more glaze, less gum) while the
## middle stayed pasty. Fissures run through it, and lifting the heatsink tore the stack
## between the two faces, leaving complementary peaks. Some squeezed out onto the package.
func reset_dried() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 710
	var lumps := FastNoiseLite.new()
	lumps.seed = 710
	lumps.frequency = 0.16
	lumps.fractal_octaves = 3
	var tear := FastNoiseLite.new()
	tear.seed = 711
	tear.frequency = 0.3
	var fissures := FastNoiseLite.new()
	fissures.seed = 712
	fissures.frequency = 0.09
	var peaks := FastNoiseLite.new()
	peaks.frequency = 0.55
	for id in faces:
		var face: Dictionary = faces[id]
		peaks.seed = 713 if id == "die" else 714
		var layers := {}
		for layer in ["glaze", "crust", "gum", "film", "paste"]:
			var values := PackedFloat32Array()
			values.resize(N * N)
			layers[layer] = values
		for k in range(N * N):
			# Both faces are generated in die cell coordinates so the torn halves match up.
			var d := k if id == "die" else mirror(k)
			var i := d % N
			var j := d / N
			if is_inner(i, j):
				if rng.randf() < (0.06 if id == "die" else 0.1):
					layers.film[k] = rng.randf_range(0.7, 1.0)
					continue
				var rim := maxf(absf((i - MARGIN + 0.5) / INNER * 2.0 - 1.0), absf((j - MARGIN + 0.5) / INNER * 2.0 - 1.0))
				var stack := maxf(0.2, 1.0 + 1.7 * exp(-pow((rim - 0.82) / 0.16, 2.0)) + 0.8 * lumps.get_noise_2d(i, j))
				var share := clampf(0.5 + 0.55 * tear.get_noise_2d(i, j), 0.12, 0.88)
				stack *= (share if id == "die" else 1.0 - share) * (0.8 + 0.45 * absf(peaks.get_noise_2d(i, j)))
				var glaze := stack * lerpf(0.06, 0.28, rim)
				var gum := stack * lerpf(0.5, 0.12, rim)
				var crust := stack - glaze - gum
				if absf(fissures.get_noise_2d(i, j)) < 0.06:
					glaze = 0.0
					crust *= 0.4
				layers.glaze[k] = glaze
				layers.crust[k] = crust
				layers.gum[k] = gum
				layers.film[k] = rng.randf_range(0.7, 1.0)
			else:
				var edge := maxi(maxi(MARGIN - i, i - (N - MARGIN - 1)), maxi(MARGIN - j, j - (N - MARGIN - 1)))
				if edge <= 2 and rng.randf() < 0.45:
					layers.glaze[k] = rng.randf_range(0.02, 0.1)
					layers.crust[k] = rng.randf_range(0.4, 0.8)
					layers.film[k] = rng.randf_range(0.4, 0.8)
		for layer in layers:
			face[layer] = layers[layer]
		face.initial = residue(id)
		face.clean = false
		refresh(id)
	dried = true
	seated = "cooler-assembly" not in bench.service.removed
	report = {}
	quality = evaluate()
	changed.emit()

func residue(id: String) -> float:
	var face: Dictionary = faces[id]
	var total := 0.0
	for k in range(N * N):
		total += face.glaze[k] + face.crust[k] + face.gum[k] + face.film[k]
	return total

## Old dried compound thickness in a cell, every layer above the film.
func dried_stack(face: Dictionary, k: int) -> float:
	return face.glaze[k] + face.crust[k] + face.gum[k]

func face_progress(id: String) -> float:
	var face: Dictionary = faces[id]
	return 1.0 if face.initial <= 0.0 else clampf(1.0 - residue(id) / face.initial, 0.0, 1.0)

func paste_volume() -> float:
	var total := 0.0
	for id in faces:
		for value in faces[id].paste: total += value
	return total

func refresh(id: String) -> void:
	var face: Dictionary = faces[id]
	var bytes := PackedByteArray()
	var gum_bytes := PackedByteArray()
	bytes.resize(N * N * 4)
	gum_bytes.resize(N * N)
	# RGBA: crust, film, fresh paste, glaze; gum alone. Dried layers share STACK_DISPLAY.
	for k in range(N * N):
		bytes[k * 4] = roundi(clampf(face.crust[k] / STACK_DISPLAY, 0.0, 1.0) * 255.0)
		bytes[k * 4 + 1] = roundi(clampf(face.film[k], 0.0, 1.0) * 255.0)
		bytes[k * 4 + 2] = roundi(clampf(face.paste[k] / DISPLAY_THICKNESS, 0.0, 1.0) * 255.0)
		bytes[k * 4 + 3] = roundi(clampf(face.glaze[k] / STACK_DISPLAY, 0.0, 1.0) * 255.0)
		gum_bytes[k] = roundi(clampf(face.gum[k] / STACK_DISPLAY, 0.0, 1.0) * 255.0)
	face.texture.update(Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, bytes))
	face.gum_texture.update(Image.create_from_data(N, N, false, Image.FORMAT_R8, gum_bytes))

## Mean die contact through whatever sits between the die and the base.
func evaluate() -> float:
	var die: Dictionary = faces.die
	var sink: Dictionary = faces.heatsink
	var total := 0.0
	for k in range(N * N):
		if not is_inner(k % N, k / N): continue
		var h := mirror(k)
		# Pasty gum still conducts a little better than dry compound.
		var crust := clampf(maxf(die.glaze[k] + die.crust[k] + 0.6 * die.gum[k], sink.glaze[h] + sink.crust[h] + 0.6 * sink.gum[h]), 0.0, 1.0)
		var film := maxf(die.film[k], sink.film[h])
		var fresh := clampf((die.paste[k] + sink.paste[h]) / (0.5 * BOND), 0.0, 1.0)
		var old := DRIED_CONTACT if crust > 0.05 else 0.0
		total += lerpf(old, clampf(1.0 - 0.85 * crust - 0.3 * film, 0.0, 1.0), fresh)
	return total / float(INNER * INNER)

func begin() -> bool:
	var tool: String = bench.tools.equipped_tool
	if not WORK.has(tool): return false
	working = true
	work_kind = WORK[tool]
	last_face = ""
	stroke_dir = Vector2.ZERO
	aiming = true
	if tool != loaded_tool:
		# A clean blade, a fresh pad.
		loaded_tool = tool
		blade_load = 0.0
		pad_soil = 0.0
	return true

func end() -> void:
	working = false

## Applies the equipped paste tool where the pointer ray meets a paste layer.
func work_at(hit: Dictionary, delta: float) -> bool:
	if not working or hit.is_empty(): return false
	var id := face_of(hit.get("mesh"))
	if id == "": return false
	var check: Dictionary = bench.service_rules.check_surface(work_kind, id, bench.service.removed, bench.tools.equipped_tool)
	if not check.allowed:
		deny(check.reason)
		return false
	var layer: MeshInstance3D = faces[id].mesh
	var local := layer.to_local(hit.point)
	var size: Vector2 = layer.mesh.size
	var cell := Vector2((local.x / size.x + 0.5) * N, (local.z / size.y + 0.5) * N)
	if last_face == "": press_cell = cell
	var stroke := cell - last_cell if last_face == id else Vector2.ZERO
	last_cell = cell
	last_face = id
	steer(cell, stroke)
	var changed_any := false
	takes = {}
	match work_kind:
		"scrape":
			var chips_before := chip_budget
			# Gum is pushed along the locked heading, never back the way the blade came.
			changed_any = scrape(id, cell, delta, stroke_dir)
			if chip_budget > chips_before and chip_budget >= 1.0:
				chipped.emit(hit.point, layer.global_basis.y.normalized(), floori(chip_budget))
				chip_budget -= floorf(chip_budget)
		"wipe": changed_any = wipe(id, cell, delta)
		"apply":
			changed_any = squeeze(id, cell, delta)
			# A steady press squeezes at a steady rate, so the squelch plays at full level.
			squeeze_sound.set_contact(1.0)
	if work_kind != "apply": report_contact(layer, hit.point, stroke, delta)
	if changed_any:
		dried = false
		refresh(id)
		finish_if_clean(id)
		changed.emit()
	return changed_any

## Aims, then locks, the stroke's heading. Near the press point the blade points from it to
## the pointer, so circling the mouse turns it. Once the pointer leaves AIM_RADIUS the heading
## locks: later movement may bend it gradually through a curve, but motion back is ignored.
func steer(cell: Vector2, stroke: Vector2) -> void:
	if aiming:
		var offset := cell - press_cell
		if offset.length() > 0.3: stroke_dir = offset.normalized()
		if offset.length() > AIM_RADIUS: aiming = false
		return
	if stroke.length() < 0.3: return
	var heading := stroke.normalized()
	if heading.dot(stroke_dir) > STROKE_TURN: stroke_dir = stroke_dir.lerp(heading, STROKE_FOLLOW).normalized()

## The tool is on the face: drive its sound from stroke speed and what it removed, load the
## spudger's edge or soil the pad, and shed crumbs and clumps off the face.
func report_contact(layer: MeshInstance3D, point: Vector3, stroke: Vector2, delta: float) -> void:
	var total := 0.0
	for layer_name in takes: total += takes[layer_name]
	var speed := stroke.length() / maxf(delta, 0.001)
	var loudness := 0.35 * clampf(speed / 20.0, 0.0, 1.0) + clampf(total / maxf(delta, 0.001) / FULL_SOUND, 0.0, 1.0)
	var normal := layer.global_basis.y.normalized()
	var ahead := (layer.global_basis * Vector3(stroke_dir.x, 0.0, stroke_dir.y)).normalized() if stroke_dir != Vector2.ZERO else normal
	if work_kind == "scrape":
		scrape_sound.set_contact(loudness)
		blade_load += (takes.get("crust", 0.0) * 0.5 + takes.get("gum", 0.0) + takes.get("paste", 0.0) * 0.6) * BLADE_PICKUP
		crumb_budget += takes.get("crust", 0.0) / CRUST_PER_CRUMB
		var size := cell_size(layer)
		if crumb_budget >= 1.0:
			shed.emit(point, normal, ahead, floori(crumb_budget), CRUMB_COLOR, size * 0.45)
			crumb_budget -= floorf(crumb_budget)
		if blade_load >= 1.0:
			shed.emit(point + ahead * size * 2.0, normal, ahead, 1, CLUMP_COLOR, size * 1.4)
			blade_load -= CLUMP_SHED
	else:
		wipe_sound.set_contact(loudness)
		# A fresh pad is used up once it first lifts residue.
		if pad_soil <= 0.0 and total > 0.0: consumed.emit("ipa-pad", 1.0)
		pad_soil = minf(1.0, pad_soil + total / PAD_CAPACITY)

## World size of one paste cell on a face layer.
func cell_size(layer: MeshInstance3D) -> float:
	return (layer.mesh as PlaneMesh).size.x * layer.global_basis.get_scale().x / N

func brush(cell: Vector2, radius: float) -> Array:
	var result: Array = []
	for j in range(maxi(0, floori(cell.y - radius)), mini(N - 1, ceili(cell.y + radius)) + 1):
		for i in range(maxi(0, floori(cell.x - radius)), mini(N - 1, ceili(cell.x + radius)) + 1):
			var falloff := 1.0 - Vector2(i + 0.5, j + 0.5).distance_to(cell) / radius
			if falloff > 0.0: result.append([j * N + i, minf(1.0, falloff * 1.6)])
	return result

## Grid index of a cell-space point, or -1 off the face.
func cell_index(point: Vector2) -> int:
	var i := floori(point.x)
	var j := floori(point.y)
	return j * N + i if i >= 0 and i < N and j >= 0 and j < N else -1

## Glaze breaks fastest where the blade can get under it: beside a gap, fissure or edge.
func glaze_exposed(glaze: PackedFloat32Array, k: int) -> bool:
	var at := Vector2(k % N + 0.5, k / N + 0.5)
	for offset in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var other := cell_index(at + offset)
		if other < 0 or glaze[other] <= 0.0: return true
	return false

## The plastic spudger works down the stack: it chips the brittle glaze, pares the chalky
## crust, then ploughs the pasty gum, lifting some and pushing the rest ahead of the blade
## (outward from the brush when held still). Gum pushed off the face is gone. Fresh paste
## lifts too; the film stays behind for the IPA wipe.
func scrape(id: String, cell: Vector2, delta: float, stroke := Vector2.ZERO) -> bool:
	if OS.is_debug_build(): delta *= debug_scrape_speed
	var face: Dictionary = faces[id]
	var glaze: PackedFloat32Array = face.glaze
	var crust: PackedFloat32Array = face.crust
	var gum: PackedFloat32Array = face.gum
	var paste: PackedFloat32Array = face.paste
	var pushed := PackedFloat32Array()
	pushed.resize(N * N)
	var ahead := stroke.normalized() if stroke.length() > 0.05 else Vector2.ZERO
	var removed := 0.0
	var taken := {"glaze": 0.0, "crust": 0.0, "gum": 0.0, "paste": 0.0}
	for entry in brush(cell, 2.4):
		var k: int = entry[0]
		var reach: float = entry[1] * delta
		var before: float = glaze[k] + crust[k] + gum[k] + paste[k]
		var fresh := minf(paste[k], 6.0 * reach)
		paste[k] -= fresh
		taken.paste += fresh
		if glaze[k] > 0.0:
			var take := minf(glaze[k], GLAZE_RATE * reach * (CHIP_BOOST if glaze_exposed(glaze, k) else 1.0))
			glaze[k] -= take
			taken.glaze += take
			chip_budget += take / GLAZE_PER_CHIP
		elif crust[k] > 0.0:
			var pared := minf(crust[k], CRUST_RATE * reach)
			crust[k] -= pared
			taken.crust += pared
		elif gum[k] > 0.0:
			var moved := minf(gum[k], GUM_RATE * reach)
			gum[k] -= moved
			taken.gum += moved
			var at := Vector2(k % N + 0.5, k / N + 0.5)
			var push := ahead if ahead != Vector2.ZERO else (at - cell).normalized()
			var target := cell_index(at + push)
			if target >= 0 and target != k: pushed[target] += moved * SMEAR
		removed += before - glaze[k] - crust[k] - gum[k] - paste[k]
	takes = taken
	for k in range(N * N):
		gum[k] += pushed[k]
	face.glaze = glaze
	face.crust = crust
	face.gum = gum
	face.paste = paste
	return removed > 0.0

## Alcohol lifts film and fresh paste and slowly dissolves exposed gum, but only smears over
## dried glaze or crust.
func wipe(id: String, cell: Vector2, delta: float) -> bool:
	if OS.is_debug_build(): delta *= debug_wipe_speed
	var face: Dictionary = faces[id]
	var film: PackedFloat32Array = face.film
	var gum: PackedFloat32Array = face.gum
	var paste: PackedFloat32Array = face.paste
	var removed := 0.0
	var blocked := 0
	var cells := brush(cell, 3.2)
	var taken := {"film": 0.0, "gum": 0.0, "paste": 0.0}
	for entry in cells:
		var k: int = entry[0]
		if face.glaze[k] + face.crust[k] > 0.15:
			blocked += 1
			continue
		var before: float = film[k] + gum[k] + paste[k]
		var lifted := {"film": minf(film[k], 2.4 * delta * entry[1]), "gum": minf(gum[k], WIPE_GUM_RATE * delta * entry[1]),
			"paste": minf(paste[k], 5.0 * delta * entry[1])}
		film[k] -= lifted.film
		gum[k] -= lifted.gum
		paste[k] -= lifted.paste
		for layer_name in lifted: taken[layer_name] += lifted[layer_name]
		removed += before - film[k] - gum[k] - paste[k]
	takes = taken
	face.film = film
	face.gum = gum
	face.paste = paste
	if blocked * 2 > cells.size():
		deny("The wipe only smears the crusty old paste. Scrape it off with the spudger first.")
	return removed > 0.0

## Holding the plunger grows a bead that widens as it piles up.
func squeeze(id: String, cell: Vector2, delta: float) -> bool:
	var face: Dictionary = faces[id]
	var paste: PackedFloat32Array = face.paste
	var center := clampi(floori(cell.y), 0, N - 1) * N + clampi(floori(cell.x), 0, N - 1)
	var sigma := 0.7 + 0.22 * sqrt(paste[center])
	var cells := brush(cell, sigma * 3.0)
	var weights: Array[float] = []
	var sum := 0.0
	for entry in cells:
		var k: int = entry[0]
		var distance := Vector2(k % N + 0.5, k / N + 0.5).distance_to(cell)
		var weight := exp(-distance * distance / (2.0 * sigma * sigma))
		weights.append(weight)
		sum += weight
	if sum <= 0.0: return false
	var amount := SQUEEZE_RATE * delta
	for index in range(cells.size()):
		paste[cells[index][0]] += amount * weights[index] / sum
	face.paste = paste
	consumed.emit("thermal-paste", amount / IDEAL_VOLUME * IDEAL_GRAMS)
	return true

func finish_if_clean(id: String) -> void:
	var face: Dictionary = faces[id]
	if face.clean or face.initial <= 0.0 or residue(id) > CLEAN_THRESHOLD * face.initial: return
	var zero := PackedFloat32Array()
	zero.resize(N * N)
	for layer in ["glaze", "crust", "gum", "film"]:
		face[layer] = zero.duplicate()
	face.clean = true
	refresh(id)
	if not muted: jingle.play()
	notice.emit("GPU die clean. Ready for fresh paste." if id == "die" else "Heatsink base clean. Bare metal, ready to mount.")

## Pressure caps the bond line over the die; excess flows outward and squeezes onto the package.
func spread() -> void:
	var die: Dictionary = faces.die
	var sink: Dictionary = faces.heatsink
	var grid: PackedFloat32Array = die.paste
	var sink_paste: PackedFloat32Array = sink.paste
	var volume := 0.0
	var margin_before := 0.0
	for k in range(N * N):
		# Paste left on the base by a lift test rejoins the die's.
		grid[k] += sink_paste[mirror(k)]
		volume += grid[k]
		if not is_inner(k % N, k / N): margin_before += grid[k]
	sink_paste.fill(0.0)
	for iteration in range(800):
		var moved := 0.0
		for k in range(N * N):
			var excess: float = grid[k] - BOND
			if excess <= 0.002 or neighbors[k].is_empty(): continue
			grid[k] = BOND
			for pair in neighbors[k]:
				grid[pair[0]] += excess * pair[1]
			moved += excess
		if moved < 0.01: break
	var covered := 0
	var margin_after := 0.0
	for k in range(N * N):
		if is_inner(k % N, k / N):
			if grid[k] >= 0.5 * BOND: covered += 1
		else: margin_after += grid[k]
	die.paste = grid
	sink.paste = sink_paste
	report = {"coverage": covered / float(INNER * INNER), "overflow": margin_after - margin_before, "volume": volume}
	refresh("die")
	refresh("heatsink")

func seat() -> void:
	if seated: return
	seated = true
	var had_paste := paste_volume() > 0.05 * IDEAL_VOLUME
	spread()
	quality = evaluate()
	if had_paste:
		notice.emit("Heatsink seated. Paste pressed across %d%% of the die." % roundi(report.coverage * 100.0))
	elif quality < DRIED_CONTACT * 0.5:
		notice.emit("Heatsink seated on a bare die with no thermal paste. It will overheat.")
	changed.emit()

## Lifting splits the pressed paste between die and base, revealing the imprint.
func lift() -> void:
	if not seated: return
	seated = false
	var die: Dictionary = faces.die
	var sink: Dictionary = faces.heatsink
	var die_paste: PackedFloat32Array = die.paste
	var sink_paste: PackedFloat32Array = sink.paste
	for k in range(N * N):
		if not is_inner(k % N, k / N): continue
		var half: float = die_paste[k] * 0.5
		die_paste[k] -= half
		sink_paste[mirror(k)] += half
	die.paste = die_paste
	sink.paste = sink_paste
	refresh("die")
	refresh("heatsink")
	if not report.is_empty() and report.volume > 0.05 * IDEAL_VOLUME:
		var notes: Array[String] = []
		if report.coverage < 0.9: notes.append("dry patches where the paste never reached")
		if report.overflow > 0.12 * IDEAL_VOLUME: notes.append("excess squeezed onto the package; wipe it off")
		notice.emit("Heatsink lifted. The imprint shows %d%% contact%s." % [roundi(quality * 100.0),
			" with " + " and ".join(notes) if not notes.is_empty() else ", an even, full spread"])
	changed.emit()

func deny(reason: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if reason == last_denial and now - denial_time < 2.0: return
	last_denial = reason
	denial_time = now
	notice.emit(reason)

func set_muted(value: bool) -> void:
	muted = value
	if muted and jingle != null: jingle.stop()
	for voice in [scrape_sound, wipe_sound, squeeze_sound]:
		if voice != null: voice.set_muted(value)

func debug_dry() -> bool:
	if not OS.is_debug_build(): return false
	reset_dried()
	notice.emit("Debug: GPU die paste dried out.")
	return true

func debug_repaste() -> bool:
	if not OS.is_debug_build() or (is_fresh() and not dried): return false
	set_fresh()
	notice.emit("Debug: GPU die repasted with full contact.")
	return true

## A healthy card: a full, even bond line under the seated heatsink.
func set_fresh() -> void:
	for id in faces:
		var face: Dictionary = faces[id]
		var zero := PackedFloat32Array()
		zero.resize(N * N)
		var paste := zero.duplicate()
		if id == "die":
			for k in range(N * N):
				if is_inner(k % N, k / N): paste[k] = BOND
		for layer in ["glaze", "crust", "gum", "film"]:
			face[layer] = zero.duplicate()
		face.paste = paste
		face.clean = true
		refresh(id)
	dried = false
	seated = "cooler-assembly" not in bench.service.removed
	report = {"coverage": 1.0, "overflow": 0.0, "volume": IDEAL_VOLUME}
	quality = evaluate()
	changed.emit()

func _exit_tree() -> void:
	if jingle != null: jingle.stop()
