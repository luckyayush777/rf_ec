extends Node
## Megacorp warranty glue: a megacorp card (neighbourhood.gd MEGACORP) can arrive with blobs of
## hard glue over its screws, so the screwdriver cannot reach them. In focus, the heat gun warms
## every blob on the side of the part it is pointed at until they turn soft and wet, and the
## suction pen then sucks the soft glue off one blob at a time. Glue cools and hardens again if
## it is left too long. Each blob hangs under its screw's seat marker (gpu_service.gd), so it
## travels with the cooler when that comes off.
signal changed
signal notice(text: String)

const AudioMix = preload("res://scripts/audio_mix.gd")
const ContactLoop = preload("res://scripts/contact_loop.gd")
const Contract = preload("res://scripts/asset_contract.gd")
const Neighbourhood = preload("res://scripts/neighbourhood.gd")
const WORK := {"heat-gun": "heat", "suction-pen": "suck"}
## Seconds of steady heat that soften a cold blob facing the gun.
const HEAT_TIME := 2.5
## Heat (0..1) at or above which the glue is soft enough for the suction pen.
const SOFT_AT := 0.7
## Seconds a fully heated blob stays soft once the gun is off it (`soft_time`, tunable in the
## debug Repair speeds section); it cools from full heat to SOFT_AT over that time.
const DEFAULT_SOFT_TIME := 60.0
## Seconds of suction that clear a soft blob at 1x (`debug_suck_speed` scales it).
const SUCK_TIME := 1.6
## The pen works the blob it is on, or one whose centre is within this many radii of it.
const SUCK_REACH := 1.3
## How squarely a blob must face the gun to heat at the full rate (cosine), and below which
## it gets no heat at all (the far side of the card).
const FACING_FULL := 0.5
const FACING_NONE := -0.1
const GLUE_COLOR := Color("#7a2a40")
const HOT_GLOW := Color(1.0, 0.42, 0.12)
## The recorded loops; each plays its whole length seamlessly.
const HEAT_RECORDING := "res://assets/sounds/heat_gun.wav"
const SUCTION_RECORDING := "res://assets/sounds/suction_pen.wav"
const HEAT_GAIN_DB := -6.0
const SUCTION_GAIN_DB := -2.0
## How fast the heat gun's motor winds up on the trigger and coasts down after it.
const SPIN_UP := 3.0
const SPIN_DOWN := 1.6

var bench: Node3D
var soft_time := DEFAULT_SOFT_TIME
var debug_suck_speed := 1.0
## Screw id -> {root, material, centre (seat space), radius (seat space), heat, amount}.
var seals := {}
## Screws still under glue, in screw order.
var sealed: Array = []
var initial := 0
var working := false
var work_kind := ""
var heat_audio: AudioStreamPlayer
var suction_sound: AudioStreamPlayer
var jingle: AudioStreamPlayer
var motor := 0.0
var slurping := false
var heated: Dictionary = {}
var muted := false
var last_denial := ""
var denial_time := 0.0

func configure(world: Node3D) -> void:
	bench = world
	for id in bench.service.fan_screws + bench.service.cooler_screws:
		build_seal(id)
	heat_audio = AudioStreamPlayer.new()
	heat_audio.name = "HeatGunSound"
	heat_audio.bus = AudioMix.HEAT_GUN
	heat_audio.stream = looped(HEAT_RECORDING)
	heat_audio.volume_db = -80.0
	add_child(heat_audio)
	suction_sound = ContactLoop.new("SuctionPenSound", SUCTION_RECORDING, AudioMix.SUCTION_PEN, SUCTION_GAIN_DB)
	add_child(suction_sound)
	jingle = AudioStreamPlayer.new()
	jingle.stream = preload("res://assets/sounds/clean_jingle.wav")
	jingle.volume_db = -4.0
	jingle.bus = AudioMix.JINGLE
	add_child(jingle)
	set_sealed([])

static func looped(path: String) -> AudioStreamWAV:
	if not ResourceLoader.exists(path): return null
	var source := load(path) as AudioStreamWAV
	if source == null: return null
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream

## A lopsided puddle of glue smeared over the screw head and spilling past its seat rim, sized
## from the head in the seat's space (the seat shares the screw's home transform; +Y points out
## of the screw head).
func build_seal(id: String) -> void:
	var seat: Node3D = bench.service.screw_seats[id]
	var head: AABB = Contract.bounds_in(bench.asset_contract.objects[id])
	var radius: float = maxf(head.size.x, head.size.z) * 0.5 * 2.0
	var top: float = maxf(head.end.y, 0.05)
	var shape := RandomNumberGenerator.new()
	shape.seed = hash(id)
	var material := StandardMaterial3D.new()
	material.albedo_color = GLUE_COLOR
	material.roughness = 0.38
	material.clearcoat_enabled = true
	material.clearcoat = 0.6
	material.emission_enabled = true
	material.emission = HOT_GLOW
	material.emission_energy_multiplier = 0.0
	var root := Node3D.new()
	root.name = "glue-seal"
	seat.add_child(root)
	var dome := SphereMesh.new()
	dome.radius = radius
	# A hemisphere rises `height` from its flat base: a low mound over the head and the seat
	# rim, which must not poke through even when hot glue slumps.
	dome.height = top + radius * 0.3
	dome.is_hemisphere = true
	dome.radial_segments = 24
	dome.rings = 8
	var blob := add_piece(root, "glue-blob", dome, Vector3.ZERO, material)
	blob.scale = Vector3(1.0, 1.0, shape.randf_range(0.78, 0.9))
	blob.rotation.y = shape.randf_range(0.0, TAU)
	# Squashed runs spill out past the rim, so it reads as glue squeezed on rather than a cap.
	for index in range(3):
		var drip := SphereMesh.new()
		drip.radius = radius * shape.randf_range(0.22, 0.3)
		drip.height = drip.radius * 2.0
		drip.radial_segments = 14
		drip.rings = 6
		var angle := TAU * index / 3.0 + shape.randf_range(-0.5, 0.5)
		# Long along the run, flat, and half sunk into the mound's base.
		var run := add_piece(root, "glue-drip-%d" % (index + 1), drip, Vector3(cos(angle), 0, sin(angle)) * radius * shape.randf_range(0.82, 0.95), material)
		run.scale = Vector3(1.9, 0.3, 0.85)
		run.rotation.y = -angle
	seals[id] = {"root": root, "material": material, "centre": Vector3(0, top * 0.6, 0), "radius": radius, "heat": 0.0, "amount": 0.0}

func add_piece(root: Node3D, piece_name: String, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = piece_name
	node.mesh = mesh
	node.material_override = material
	node.position = at
	root.add_child(node)
	return node

## A new card: glue over exactly these screws (none for a card nobody sealed).
func set_sealed(ids: Array) -> void:
	sealed.clear()
	for id in seals:
		var seal: Dictionary = seals[id]
		seal.heat = 0.0
		seal.amount = 1.0 if id in ids else 0.0
		if id in ids: sealed.append(id)
		refresh(id)
	initial = sealed.size()
	working = false
	changed.emit()

func is_sealed(id: String) -> bool:
	return id in sealed

func is_soft(id: String) -> bool:
	return seals.has(id) and seals[id].heat >= SOFT_AT

## gpu_service.gd guard: a glued screw cannot be turned out.
func screw_block(id: String) -> String:
	if not is_sealed(id): return ""
	return "%s is sealed under %s warranty glue. Soften it with the heat gun, then suck it off with the suction pen." % [
		id.replace("-", " ").capitalize(), Neighbourhood.MEGACORP]

func progress() -> float:
	if initial == 0: return 1.0
	var left := 0.0
	for id in sealed: left += seals[id].amount
	return clampf(1.0 - left / initial, 0.0, 1.0)

## The seal a mesh belongs to, or "".
func seal_of(mesh: Object) -> String:
	if not (mesh is Node): return ""
	for id in sealed:
		var root: Node3D = seals[id].root
		if root == mesh or root.is_ancestor_of(mesh): return id
	return ""

func world_centre(id: String) -> Vector3:
	return seals[id].root.global_transform * seals[id].centre

func world_radius(id: String) -> float:
	return seals[id].radius * seals[id].root.global_basis.get_scale().x

func begin() -> bool:
	var tool: String = bench.tools.equipped_tool
	if not WORK.has(tool): return false
	working = true
	work_kind = WORK[tool]
	return true

func end() -> void:
	working = false

## Heat lost per second off the gun, so a fully heated blob stays soft for `soft_time`.
func cool_rate() -> float:
	return (1.0 - SOFT_AT) / maxf(soft_time, 0.1)

## One frame of the heat gun blowing along `direction` (from the gun toward the part): every
## glued blob facing it warms, the squarer the faster; blobs on the far side stay cold.
func heat_from(direction: Vector3, delta: float) -> bool:
	if not working or work_kind != "heat" or sealed.is_empty(): return false
	var softened := 0
	var any := false
	for id in sealed:
		var facing: float = seals[id].root.global_basis.y.normalized().dot(-direction.normalized())
		var weight := smoothstep(FACING_NONE, FACING_FULL, facing)
		if weight <= 0.0: continue
		var was_soft := is_soft(id)
		seals[id].heat = minf(1.0, seals[id].heat + delta / HEAT_TIME * weight)
		heated[id] = true
		refresh(id)
		any = true
		if not was_soft and is_soft(id): softened += 1
	if softened > 0:
		notice.emit("The glue goes soft and glossy on %d screw%s. Suck it off with the suction pen before it cools." % [softened, "" if softened == 1 else "s"])
	return any

## One frame of the suction pen on the aimed surface `hit` (from the focus view's picker).
func work_at(hit: Dictionary, delta: float) -> bool:
	if not working or work_kind != "suck" or hit.is_empty() or sealed.is_empty(): return false
	var point: Vector3 = hit.point
	var aimed := seal_of(hit.get("mesh"))
	if aimed == "":
		for id in sealed:
			if world_centre(id).distance_to(point) <= world_radius(id) * SUCK_REACH: aimed = id
	if aimed == "": return false
	if not is_soft(aimed):
		deny("This glue is rock hard. Warm it with the heat gun until it goes soft and glossy.")
		return false
	slurping = true
	var speed: float = debug_suck_speed if OS.is_debug_build() else 1.0
	seals[aimed].amount = maxf(0.0, seals[aimed].amount - delta * speed / SUCK_TIME)
	if seals[aimed].amount <= 0.0: clear_seal(aimed)
	else: refresh(aimed)
	changed.emit()
	return true

func clear_seal(id: String) -> void:
	sealed.erase(id)
	seals[id].amount = 0.0
	seals[id].heat = 0.0
	refresh(id)
	if sealed.is_empty():
		if not muted: jingle.play()
		notice.emit("All the glue is off. The screwdriver can reach every screw now.")
	else:
		notice.emit("Glue sucked off %s. %d glued screw%s left." % [id.replace("-", " "), sealed.size(), "" if sealed.size() == 1 else "s"])

## Size, slump and glow follow how much glue is left and how hot it is.
func refresh(id: String) -> void:
	var seal: Dictionary = seals[id]
	var root: Node3D = seal.root
	root.visible = seal.amount > 0.0
	if not root.visible: return
	var heat: float = seal.heat
	var soft := smoothstep(0.35, SOFT_AT, heat)
	var size: float = 0.35 + 0.65 * float(seal.amount)
	root.scale = Vector3(size * (1.0 + 0.06 * soft), size * (1.0 - 0.12 * soft), size * (1.0 + 0.06 * soft))
	var material: StandardMaterial3D = seal.material
	material.emission_energy_multiplier = 1.1 * heat * heat
	material.roughness = lerpf(0.38, 0.06, soft)
	material.albedo_color = GLUE_COLOR.lerp(Color("#b2405a"), soft)

func deny(reason: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if reason == last_denial and now - denial_time < 2.0: return
	last_denial = reason
	denial_time = now
	notice.emit(reason)

func _process(delta: float) -> void:
	# Blobs the gun is not on cool and harden again.
	for id in sealed:
		if not heated.has(id) and seals[id].heat > 0.0:
			seals[id].heat = maxf(0.0, seals[id].heat - cool_rate() * delta)
		refresh(id)
	heated.clear()
	var running: bool = working and work_kind == "heat" and bench.tools.equipped_tool == "heat-gun"
	motor = move_toward(motor, 1.0 if running else 0.0, delta * (SPIN_UP if running else SPIN_DOWN))
	if heat_audio.stream != null:
		if motor > 0.001 and not heat_audio.playing and not muted: heat_audio.play()
		elif (motor <= 0.001 or muted) and heat_audio.playing: heat_audio.stop()
		heat_audio.pitch_scale = lerpf(0.72, 1.0, motor)
		heat_audio.volume_db = HEAT_GAIN_DB + linear_to_db(maxf(motor, 0.0001))
	if working and work_kind == "suck" and bench.tools.equipped_tool == "suction-pen":
		suction_sound.set_contact(1.0 if slurping else 0.45)
	slurping = false

func set_muted(value: bool) -> void:
	muted = value
	suction_sound.set_muted(value)
	if muted:
		heat_audio.stop()
		jingle.stop()

## Debug: glue every seated screw shut, as a megacorp card would arrive at the biggest zone.
func debug_seal() -> bool:
	if not OS.is_debug_build(): return false
	var ids: Array = []
	for id in bench.service.fan_screws + bench.service.cooler_screws:
		if id not in bench.service.removed: ids.append(id)
	set_sealed(ids)
	notice.emit("Debug: %d screws glued shut." % ids.size())
	return true

func _exit_tree() -> void:
	for player in [heat_audio, suction_sound, jingle]:
		if player != null: player.stop()
