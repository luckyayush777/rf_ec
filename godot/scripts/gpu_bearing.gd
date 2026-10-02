extends Node
## The fan's sleeve bearing. The 710 starts with a dry bearing and a gummed-up shaft, so the
## fan grinds on the test board. Service happens in focus on the detached fan: peel the hub
## sticker, pull the rotor, wipe the shaft with IPA, oil the bearing and refit the rotor, which
## presses the sticker back on. The authored fan has no motor, so runtime meshes stand in for
## the bearing boss, its struts and the shaft; all stay hidden inside the hub until the rotor
## comes out.
signal changed
signal opened_changed
signal notice(text: String)

## Openings inside the detached fan, in order; service_rules.check_opening evaluates them.
## Small parts can be handled with bare hands or while holding a light tool.
const HANDLING_TOOLS := ["", "spudger", "ipa-wipe", "fan-oiler"]
const OPENINGS := [
	{"id": "hub-label", "insideOf": "fan-assembly", "label": "hub sticker", "tools": HANDLING_TOOLS},
	{"id": "fan-rotor", "insideOf": "fan-assembly", "requires": ["hub-label"], "label": "fan rotor", "tools": HANDLING_TOOLS}]
const SURFACES := [
	{"id": "shaft", "exposedBy": "fan-assembly", "needsOpen": ["fan-rotor"], "actions": ["wipe"],
		"label": "fan shaft", "hint": "Wipe the fan shaft with the IPA wipe; scraping would score it."},
	{"id": "bearing", "exposedBy": "fan-assembly", "needsOpen": ["fan-rotor"], "actions": ["oil"],
		"label": "fan bearing", "hint": "The bearing needs a drop of oil from the fan oiler."}]
const WORK := {"ipa-wipe": "wipe", "fan-oiler": "oil"}
## The authored hub cap, centre disc and brand print together form the sticker.
const STICKER := ["fan-hub-cap", "hub-center", "fan-brand-label"]
## Fan-local geometry: the fan faces +Y, the rotor sits at y 0.026 and its hub bottom at -0.014.
const HUB_BOTTOM := -0.04
const SHAFT_RADIUS := 0.035
const SHAFT_LENGTH := 0.11
const BOSS_RADIUS := 0.12
const BOSS_BOTTOM := -0.13
const BOSS_TOP := 0.09
const RING_RADIUS := 0.93
const STICKER_EDGE := Vector3(0, 0.1435, 0.237)
## A pulled rotor lifts clear, then rests face down beside the housing with its shaft up;
## its hub top meets the level of the fan's mounting posts.
const ROTOR_LIFT := 0.42
const ROTOR_ASIDE := Transform3D(Basis(Vector3.RIGHT, PI), Vector3(2.1, -0.0255, 0))
## Gunk rows run along the shaft; columns only vary the blotches around it.
const ROWS := 20
const COLUMNS := 16
## Residue at or below this fraction auto-clears, like paste and dust.
const CLEAN_THRESHOLD := 0.05
const DROP_INTERVAL := 0.4
const MOTION_TIME := 0.45
## The supplied peel recording is a quiet crackle; the slow peel lasts as long as it does.
const PEEL_SOUND = preload("res://assets/sounds/gpu_sounds/sticker_peel_gpu_use.wav")
const PEEL_GAIN_DB := 15.0
const SHADER = preload("res://shaders/shaft_gunk.gdshader")
const AudioMix = preload("res://scripts/audio_mix.gd")

var bench: Node3D
var debug_wipe_speed := 1.0
var fan: Node3D
var rotor: Node3D
var rotor_home := Transform3D.IDENTITY
var sticker_nodes: Array[Node3D] = []
var sticker_homes: Array[Transform3D] = []
var shaft: MeshInstance3D
var boss: MeshInstance3D
var sleeve: MeshInstance3D
var oil_bead: MeshInstance3D
var gunk_texture: ImageTexture
var gunk := PackedFloat32Array()
var pattern := PackedFloat32Array()
var initial_gunk := 0.0
var shaft_clean := false
var oil_drops := 0
## True while the fan runs on a dry, gummed bearing. Updated when the rotor seats.
var dry := true
var opened: Array = []
var moving := false
var working := false
var work_kind := ""
var drip_time := 0.0
var last_denial := ""
var denial_time := 0.0
var jingle: AudioStreamPlayer
var peel_audio: AudioStreamPlayer
var muted := false

func configure(world: Node3D) -> void:
	bench = world
	fan = bench.gpu.find_child("fan-assembly", true, false)
	rotor = fan.find_child("fan-rotor", true, false)
	rotor_home = rotor.transform
	for id in STICKER:
		var node: Node3D = fan.find_child(id, true, false)
		sticker_nodes.append(node)
		sticker_homes.append(node.transform)
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = Color(0.1, 0.105, 0.115)
	plastic.roughness = 0.7
	boss = add_cylinder("fan-bearing-boss", fan, BOSS_RADIUS, BOSS_TOP - BOSS_BOTTOM, (BOSS_TOP + BOSS_BOTTOM) * 0.5, plastic)
	for index in range(3):
		var strut := MeshInstance3D.new()
		strut.name = "fan-strut-%d" % (index + 1)
		var box := BoxMesh.new()
		box.size = Vector3(RING_RADIUS - BOSS_RADIUS + 0.04, 0.02, 0.05)
		box.material = plastic
		strut.mesh = box
		fan.add_child(strut)
		var angle := TAU * index / 3.0 + 0.3
		strut.position = Vector3(cos(angle), 0, -sin(angle)) * (BOSS_RADIUS + RING_RADIUS) * 0.5 + Vector3(0, 0.01, 0)
		strut.rotation.y = angle
	var bronze := StandardMaterial3D.new()
	bronze.albedo_color = Color(0.42, 0.3, 0.16)
	bronze.metallic = 0.8
	bronze.roughness = 0.35
	sleeve = add_cylinder("fan-bearing-sleeve", fan, 0.05, 0.004, BOSS_TOP + 0.002, bronze)
	var oil := StandardMaterial3D.new()
	oil.albedo_color = Color(0.85, 0.62, 0.12, 0.8)
	oil.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	oil.roughness = 0.05
	oil.metallic_specular = 1.0
	var bead := SphereMesh.new()
	bead.radius = 0.035
	bead.height = 0.03
	bead.material = oil
	oil_bead = MeshInstance3D.new()
	oil_bead.name = "fan-bearing-oil"
	oil_bead.mesh = bead
	oil_bead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fan.add_child(oil_bead)
	oil_bead.position = Vector3(0, BOSS_TOP + 0.006, 0)
	gunk_texture = ImageTexture.create_from_image(Image.create(COLUMNS, ROWS, false, Image.FORMAT_R8))
	var gunk_material := ShaderMaterial.new()
	gunk_material.shader = SHADER
	gunk_material.set_shader_parameter("gunk_map", gunk_texture)
	gunk_material.set_shader_parameter("half_length", SHAFT_LENGTH * 0.5)
	shaft = add_cylinder("fan-shaft", rotor, SHAFT_RADIUS, SHAFT_LENGTH, HUB_BOTTOM - SHAFT_LENGTH * 0.5, null)
	shaft.material_override = gunk_material
	jingle = AudioStreamPlayer.new()
	jingle.stream = preload("res://assets/sounds/clean_jingle.wav")
	jingle.volume_db = -4.0
	jingle.bus = AudioMix.JINGLE
	add_child(jingle)
	peel_audio = AudioStreamPlayer.new()
	peel_audio.stream = PEEL_SOUND
	peel_audio.volume_db = PEEL_GAIN_DB
	peel_audio.bus = AudioMix.STICKER_PEEL
	add_child(peel_audio)
	bench.service.assembly_seated.connect(func(id: String):
		# A fan mounted with only its sticker peeled gets the sticker pressed back on.
		if id == "fan-assembly" and "hub-label" in opened: close_all())
	reset_dry()

func add_cylinder(node_name: String, parent: Node3D, radius: float, height: float, y: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	mesh.rings = 1
	if material != null: mesh.material = material
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	parent.add_child(node)
	node.position = Vector3(0, y, 0)
	return node

## Old oil and dust gum up the shaft, heaviest where it runs in the sleeve.
func reset_dry() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7100
	gunk.resize(ROWS)
	pattern.resize(ROWS * COLUMNS)
	for j in range(ROWS):
		gunk[j] = clampf(rng.randf_range(0.6, 1.0) - 0.3 * absf(j - ROWS * 0.5) / (ROWS * 0.5), 0.0, 1.0)
		for i in range(COLUMNS):
			pattern[j * COLUMNS + i] = rng.randf_range(0.65, 1.0)
	initial_gunk = total_gunk()
	shaft_clean = false
	oil_drops = 0
	dry = true
	refresh()
	changed.emit()

func total_gunk() -> float:
	var total := 0.0
	for value in gunk: total += value
	return total

func refresh() -> void:
	var bytes := PackedByteArray()
	bytes.resize(ROWS * COLUMNS)
	for k in range(ROWS * COLUMNS):
		bytes[k] = roundi(clampf(gunk[k / COLUMNS] * pattern[k], 0.0, 1.0) * 255.0)
	gunk_texture.update(Image.create_from_data(COLUMNS, ROWS, false, Image.FORMAT_R8, bytes))
	oil_bead.visible = oil_drops > 0
	oil_bead.scale = Vector3.ONE * minf(0.6 + 0.4 * oil_drops, 1.8)

func progress(id: String) -> float:
	if id == "shaft": return 1.0 if initial_gunk <= 0.0 else clampf(1.0 - total_gunk() / initial_gunk, 0.0, 1.0)
	return minf(oil_drops / 2.0, 1.0)

func surface_of(mesh: Object) -> String:
	if mesh == shaft: return "shaft"
	if mesh in [boss, sleeve, oil_bead]: return "bearing"
	return ""

## The opening an empty-handed click on this mesh operates: the sticker while it is on, then the rotor.
func click_target(mesh: Object) -> String:
	if moving or not (mesh is Node3D) or not fan.is_ancestor_of(mesh) or "fan-assembly" not in bench.service.removed: return ""
	if mesh == shaft: return ""
	if mesh in sticker_nodes and "hub-label" not in opened: return "hub-label"
	if "hub-label" in opened and (mesh == rotor or rotor.is_ancestor_of(mesh)): return "fan-rotor"
	return ""

func operate(id: String) -> bool:
	if moving: return false
	# testing_station.gd owns the rotor's pose while the air blower's spin coasts down.
	if bench.testing_station.fan_speed > 0.0:
		deny("Let the fan stop spinning first.")
		return false
	var kind := "close" if id in opened else "open"
	var check: Dictionary = bench.service_rules.check_opening(kind, id, bench.service.removed, opened, bench.tools.equipped_tool)
	if not check.allowed:
		deny(check.reason)
		return false
	match [id, kind]:
		["hub-label", "open"]: peel()
		["fan-rotor", "open"]: pull()
		["fan-rotor", "close"]: seat_rotor()
		_: return false
	return true

func peel() -> void:
	opened.append("hub-label")
	moving = true
	if not muted: peel_audio.play()
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(peel_pose, 0.0, 1.0, peel_time())
	await tween.finished
	for node in sticker_nodes: node.visible = false
	moving = false
	opened_changed.emit()
	changed.emit()
	notice.emit("Hub sticker peeled off. Pull the rotor out to reach the shaft and bearing.")

func peel_time() -> float:
	return clampf(PEEL_SOUND.get_length(), MOTION_TIME, 2.5)

## Lifts the sticker away from its far edge, hinging on the edge nearest the viewer.
func peel_pose(amount: float) -> void:
	var angle := amount * 2.2
	for index in range(sticker_nodes.size()):
		var node := sticker_nodes[index]
		var pivot: Vector3 = STICKER_EDGE if node.get_parent() == fan else rotor_home.affine_inverse() * STICKER_EDGE
		var turn := Basis(Vector3.RIGHT, angle)
		node.transform = Transform3D(turn, pivot - turn * pivot + Vector3(0, 0.12, 0.08) * amount) * sticker_homes[index]

func pull() -> void:
	opened.append("fan-rotor")
	moving = true
	await move_rotor([lifted_pose(), ROTOR_ASIDE])
	moving = false
	opened_changed.emit()
	changed.emit()
	notice.emit("Rotor out. " + ("The shaft is clean; add a drop of oil to the bearing." if shaft_clean else
		"The shaft is caked in old grease and dust. Wipe it clean with IPA."))

func seat_rotor() -> void:
	moving = true
	await move_rotor([lifted_pose(), rotor_home])
	moving = false
	close_all()
	notice.emit("Rotor refitted and the hub sticker pressed back on. " + (
		"It spins freely and quietly now." if not dry else
		"The shaft is still gummed up; it will keep grinding." if not shaft_clean else
		"The bearing is still dry; it will keep grinding."))

func lifted_pose() -> Transform3D:
	return Transform3D(rotor_home.basis, rotor_home.origin + Vector3(0, ROTOR_LIFT, 0))

func move_rotor(destinations: Array) -> Signal:
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	for destination in destinations:
		tween.tween_property(rotor, "transform", destination, MOTION_TIME / destinations.size())
	return tween.finished

## Seats the rotor and sticker at once and settles whether the bearing now runs dry.
func close_all() -> void:
	rotor.transform = rotor_home
	for index in range(sticker_nodes.size()):
		sticker_nodes[index].transform = sticker_homes[index]
		sticker_nodes[index].visible = true
	opened.clear()
	dry = not (shaft_clean and oil_drops > 0)
	opened_changed.emit()
	changed.emit()

## Refit guard for gpu_service: the fan cannot be mounted with its rotor out.
func refit_block(id: String) -> String:
	if id == "fan-assembly" and moving: return "Wait for the fan bearing service to finish before mounting the fan."
	return "Refit the fan rotor before mounting the fan." if id == "fan-assembly" and "fan-rotor" in opened else ""

func begin() -> bool:
	var tool: String = bench.tools.equipped_tool
	if not WORK.has(tool): return false
	working = true
	work_kind = WORK[tool]
	# The first drop falls shortly after the press.
	drip_time = DROP_INTERVAL * 0.6
	return true

func end() -> void:
	working = false

func work_at(hit: Dictionary, delta: float) -> bool:
	if not working or moving or hit.is_empty(): return false
	var id := surface_of(hit.get("mesh"))
	if id == "": return false
	var check: Dictionary = bench.service_rules.check_surface(work_kind, id, bench.service.removed, bench.tools.equipped_tool, opened)
	if not check.allowed:
		deny(check.reason)
		return false
	var changed_any := wipe(shaft.to_local(hit.point), delta) if work_kind == "wipe" else drip(delta)
	if changed_any:
		refresh()
		changed.emit()
	return changed_any

## The wipe wraps around the thin shaft, so a stroke cleans every side of the rows it covers.
func wipe(local: Vector3, delta: float) -> bool:
	if OS.is_debug_build(): delta *= debug_wipe_speed
	if shaft_clean: return false
	var row := (SHAFT_LENGTH * 0.5 - local.y) / SHAFT_LENGTH * ROWS
	var removed := 0.0
	for j in range(maxi(0, floori(row - 2.4)), mini(ROWS - 1, ceili(row + 2.4)) + 1):
		var falloff := 1.0 - absf(j + 0.5 - row) / 2.4
		if falloff <= 0.0: continue
		var before := gunk[j]
		gunk[j] = maxf(0.0, gunk[j] - 2.2 * delta * minf(1.0, falloff * 1.6))
		removed += before - gunk[j]
	if total_gunk() <= CLEAN_THRESHOLD * initial_gunk:
		gunk.fill(0.0)
		shaft_clean = true
		if not muted: jingle.play()
		notice.emit("Shaft clean and shiny. " + ("Refit the rotor." if oil_drops > 0 else "Now add a drop of oil to the bearing."))
	return removed > 0.0

func drip(delta: float) -> bool:
	drip_time += delta
	if drip_time < DROP_INTERVAL: return false
	drip_time -= DROP_INTERVAL
	oil_drops += 1
	notice.emit("A drop of oil in the bearing." if oil_drops == 1 else
		"Two drops. That's enough; refit the rotor." if oil_drops == 2 else
		"Plenty already. Extra oil only flings onto the blades.")
	return true

func deny(reason: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if reason == last_denial and now - denial_time < 2.0: return
	last_denial = reason
	denial_time = now
	notice.emit(reason)

func set_muted(value: bool) -> void:
	muted = value
	if muted:
		jingle.stop()
		peel_audio.stop()

func debug_dry() -> bool:
	if not OS.is_debug_build() or moving: return false
	set_dry()
	notice.emit("Debug: fan bearing dried out and gummed up.")
	return true

func debug_oil() -> bool:
	if not OS.is_debug_build() or moving or not dry: return false
	set_oiled()
	notice.emit("Debug: fan shaft cleaned and bearing oiled.")
	return true

## A healthy fan: clean shaft, oiled sleeve, rotor and sticker in place.
func set_oiled() -> void:
	gunk.fill(0.0)
	shaft_clean = true
	oil_drops = 2
	refresh()
	close_all()

## A gummed, dry bearing with the fan closed up, as a faulty card arrives.
func set_dry() -> void:
	reset_dry()
	close_all()

func _exit_tree() -> void:
	for player in [jingle, peel_audio]:
		if player != null: player.stop()
