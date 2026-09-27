extends Node
## Thermal paste between the GPU die and the heatsink base.
## Each contact face owns a runtime grid layer parented to its part, so crust, film and
## fresh paste travel with the heatsink. Cell (i, j) on the die faces the heatsink cell
## returned by mirror(); the heatsink layer is flipped to face outward.
## Contact quality runs from 0 (air gap) to 1 (full fresh bond) and is evaluated when
## the heatsink seats, after the paste spreads under pressure.
signal changed
signal notice(text: String)

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
const SHADER = preload("res://shaders/paste_layer.gdshader")
const AudioMix = preload("res://scripts/audio_mix.gd")
const WORK := {"spudger": "scrape", "ipa-wipe": "wipe", "paste-syringe": "apply"}
const SURFACES := [
	{"id": "die", "exposedBy": "cooler-assembly", "applyPaste": true, "label": "GPU die"},
	{"id": "heatsink", "exposedBy": "cooler-assembly", "label": "heatsink base"}]

var bench: Node3D
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
	layer.material_override = material
	return layer

func new_face(layer: MeshInstance3D) -> Dictionary:
	var empty := PackedFloat32Array()
	empty.resize(N * N)
	var texture := ImageTexture.create_from_image(Image.create(N, N, false, Image.FORMAT_RGB8))
	(layer.material_override as ShaderMaterial).set_shader_parameter("paste_map", texture)
	return {"mesh": layer, "texture": texture, "crust": empty.duplicate(), "film": empty.duplicate(),
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

## Old compound: cracked crust over a film, with some squeezed onto the package and base.
func reset_dried() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 710
	for id in faces:
		var face: Dictionary = faces[id]
		var crust := PackedFloat32Array()
		var film := PackedFloat32Array()
		var paste := PackedFloat32Array()
		crust.resize(N * N)
		film.resize(N * N)
		paste.resize(N * N)
		for k in range(N * N):
			var i := k % N
			var j := k / N
			if is_inner(i, j):
				crust[k] = 0.0 if rng.randf() < (0.06 if id == "die" else 0.1) else rng.randf_range(0.65, 1.0)
				film[k] = rng.randf_range(0.7, 1.0)
			else:
				var edge := maxi(maxi(MARGIN - i, i - (N - MARGIN - 1)), maxi(MARGIN - j, j - (N - MARGIN - 1)))
				if edge <= 2 and rng.randf() < 0.45:
					crust[k] = rng.randf_range(0.5, 0.9)
					film[k] = rng.randf_range(0.4, 0.8)
		face.crust = crust
		face.film = film
		face.paste = paste
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
		total += face.crust[k] + face.film[k]
	return total

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
	bytes.resize(N * N * 3)
	for k in range(N * N):
		bytes[k * 3] = roundi(clampf(face.crust[k], 0.0, 1.0) * 255.0)
		bytes[k * 3 + 1] = roundi(clampf(face.film[k], 0.0, 1.0) * 255.0)
		bytes[k * 3 + 2] = roundi(clampf(face.paste[k] / DISPLAY_THICKNESS, 0.0, 1.0) * 255.0)
	face.texture.update(Image.create_from_data(N, N, false, Image.FORMAT_RGB8, bytes))

## Mean die contact through whatever sits between the die and the base.
func evaluate() -> float:
	var die: Dictionary = faces.die
	var sink: Dictionary = faces.heatsink
	var total := 0.0
	for k in range(N * N):
		if not is_inner(k % N, k / N): continue
		var h := mirror(k)
		var crust := maxf(die.crust[k], sink.crust[h])
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
	var changed_any := false
	match work_kind:
		"scrape": changed_any = scrape(id, cell, delta)
		"wipe": changed_any = wipe(id, cell, delta)
		"apply": changed_any = squeeze(id, cell, delta)
	if changed_any:
		dried = false
		refresh(id)
		finish_if_clean(id)
		changed.emit()
	return changed_any

func brush(cell: Vector2, radius: float) -> Array:
	var result: Array = []
	for j in range(maxi(0, floori(cell.y - radius)), mini(N - 1, ceili(cell.y + radius)) + 1):
		for i in range(maxi(0, floori(cell.x - radius)), mini(N - 1, ceili(cell.x + radius)) + 1):
			var falloff := 1.0 - Vector2(i + 0.5, j + 0.5).distance_to(cell) / radius
			if falloff > 0.0: result.append([j * N + i, minf(1.0, falloff * 1.6)])
	return result

## The plastic spudger lifts crust and any fresh paste but leaves the film behind.
func scrape(id: String, cell: Vector2, delta: float) -> bool:
	var face: Dictionary = faces[id]
	var crust: PackedFloat32Array = face.crust
	var paste: PackedFloat32Array = face.paste
	var removed := 0.0
	for entry in brush(cell, 2.4):
		var k: int = entry[0]
		var before: float = crust[k] + paste[k]
		crust[k] = maxf(0.0, crust[k] - 3.2 * delta * entry[1])
		paste[k] = maxf(0.0, paste[k] - 6.0 * delta * entry[1])
		removed += before - crust[k] - paste[k]
	face.crust = crust
	face.paste = paste
	return removed > 0.0

## Alcohol lifts film and fresh paste, but only smears over crust.
func wipe(id: String, cell: Vector2, delta: float) -> bool:
	var face: Dictionary = faces[id]
	var film: PackedFloat32Array = face.film
	var paste: PackedFloat32Array = face.paste
	var removed := 0.0
	var blocked := 0
	var cells := brush(cell, 3.2)
	for entry in cells:
		var k: int = entry[0]
		if face.crust[k] > 0.15:
			blocked += 1
			continue
		var before: float = film[k] + paste[k]
		film[k] = maxf(0.0, film[k] - 2.4 * delta * entry[1])
		paste[k] = maxf(0.0, paste[k] - 5.0 * delta * entry[1])
		removed += before - film[k] - paste[k]
	face.film = film
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
	return true

func finish_if_clean(id: String) -> void:
	var face: Dictionary = faces[id]
	if face.clean or face.initial <= 0.0 or residue(id) > CLEAN_THRESHOLD * face.initial: return
	var zero := PackedFloat32Array()
	zero.resize(N * N)
	face.crust = zero.duplicate()
	face.film = zero.duplicate()
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

func debug_dry() -> bool:
	if not OS.is_debug_build(): return false
	reset_dried()
	notice.emit("Debug: GPU die paste dried out.")
	return true

func debug_repaste() -> bool:
	if not OS.is_debug_build() or (is_fresh() and not dried): return false
	for id in faces:
		var face: Dictionary = faces[id]
		var zero := PackedFloat32Array()
		zero.resize(N * N)
		var paste := zero.duplicate()
		if id == "die":
			for k in range(N * N):
				if is_inner(k % N, k / N): paste[k] = BOND
		face.crust = zero.duplicate()
		face.film = zero.duplicate()
		face.paste = paste
		face.clean = true
		refresh(id)
	dried = false
	report = {"coverage": 1.0, "overflow": 0.0, "volume": IDEAL_VOLUME}
	quality = evaluate()
	notice.emit("Debug: GPU die repasted with full contact.")
	changed.emit()
	return true

func _exit_tree() -> void:
	if jingle != null: jingle.stop()
