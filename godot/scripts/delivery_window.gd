extends Node3D
## The delivery hatch under the right-wall window. An accepted job's parcel arrives a moment
## later: the roller shutter rattles up, the parcel slides in onto the counter and the shutter
## comes back down. How it gets up the mountain is not modelled. The wall, frame and counter
## belong to `shop_interior.gd`; this node owns the moving shutter and the arrival.
signal arrived

const Room = preload("res://scripts/shop_interior.gd")
const AudioMix = preload("res://scripts/audio_mix.gd")
## Seconds from accepting the job until the shutter starts to open.
const ARRIVAL_DELAY := 2.5
const SHUTTER_TIME := 0.9
const SLIDE_TIME := 0.75
const SLAT_HEIGHT := 0.26
## The shutter runs just outside the wall face, the parcel starts on the outer ledge.
const SHUTTER_X := 34.08
const OUTSIDE_X := 37.0
const SHUTTER_RATE := 22050

## Shortened by tests that are not about the arrival itself.
var arrival_delay := ARRIVAL_DELAY
var box: Node3D
var bench: Node3D
## "", "waiting" (parcel on its way), "opening", "sliding", "closing".
var state := ""
var waited := 0.0
## 0 closed, 1 fully rolled up.
var opening := 0.0
var slats: Array[MeshInstance3D] = []
var audio: AudioStreamPlayer
var muted := false
var motion: Tween

func configure(world: Node3D, parcel: Node3D) -> void:
	bench = world
	box = parcel
	var steel := Room.flat(Color("8f9aa0"), 0.45, 0.6)
	var dark := Room.flat(Color("5d666b"), 0.5, 0.55)
	var middle := (Room.HATCH_Z.x + Room.HATCH_Z.y) * 0.5
	var width := Room.HATCH_Z.y - Room.HATCH_Z.x + 0.3
	var hatch := Room.HATCH_TOP - Room.SILL_Y
	for index in range(ceili(hatch / SLAT_HEIGHT)):
		var slat := MeshInstance3D.new()
		slat.name = "ShutterSlat"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.07, SLAT_HEIGHT - 0.025, width)
		mesh.material = steel if index % 2 == 0 else dark
		slat.mesh = mesh
		add_child(slat)
		slats.append(slat)
	var housing := MeshInstance3D.new()
	housing.name = "ShutterHousing"
	var shell := BoxMesh.new()
	# Tucked behind the transom, out of sight through the glass above it.
	shell.size = Vector3(1.1, 0.42, width + 0.2)
	shell.material = dark
	housing.mesh = shell
	housing.position = Vector3(SHUTTER_X + 0.5, Room.HATCH_TOP + 0.17, middle)
	add_child(housing)
	var ledge := MeshInstance3D.new()
	ledge.name = "OuterLedge"
	var plate := BoxMesh.new()
	plate.size = Vector3(OUTSIDE_X + 1.4 - Room.WALL_X.y, 0.3, width)
	plate.material = steel
	ledge.mesh = plate
	ledge.position = Vector3((Room.WALL_X.y + OUTSIDE_X + 1.4) * 0.5, Room.SILL_Y - 0.15, middle)
	add_child(ledge)
	audio = AudioStreamPlayer.new()
	audio.name = "ShutterSound"
	audio.stream = rattle()
	audio.volume_db = -6.0
	audio.bus = AudioMix.SHUTTER
	add_child(audio)
	set_opening(0.0)

## Where the parcel rests on the counter, front label toward the room.
func sill_transform() -> Transform3D:
	var middle := (Room.HATCH_Z.x + Room.HATCH_Z.y) * 0.5
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(Room.WALL_X.x - 1.35, Room.SILL_Y, middle))

## Rolls the slats up into the housing; a slat above the hatch is hidden inside it.
func set_opening(amount: float) -> void:
	opening = clampf(amount, 0.0, 1.0)
	var middle := (Room.HATCH_Z.x + Room.HATCH_Z.y) * 0.5
	var hatch := Room.HATCH_TOP - Room.SILL_Y
	for index in range(slats.size()):
		var y := Room.SILL_Y + (index + 0.5) * SLAT_HEIGHT + opening * hatch
		slats[index].position = Vector3(SHUTTER_X, y, middle)
		slats[index].visible = y - SLAT_HEIGHT * 0.5 < Room.HATCH_TOP - 0.02

## Called when a job is accepted: the parcel waits outside until the delay has passed.
func receive() -> void:
	if motion != null: motion.kill()
	var outside := sill_transform()
	outside.origin.x = OUTSIDE_X
	box.hold_outside(outside)
	set_opening(0.0)
	waited = 0.0
	state = "waiting"

func _process(delta: float) -> void:
	if state != "waiting": return
	waited += delta
	if waited >= arrival_delay: bring_in()

func bring_in() -> void:
	state = "opening"
	play_rattle()
	motion = create_tween()
	motion.tween_method(set_opening, 0.0, 1.0, SHUTTER_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	motion.tween_callback(func():
		state = "sliding"
		box.visible = true)
	motion.tween_property(box, "global_transform", sill_transform(), SLIDE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	motion.tween_callback(func():
		box.land_on_sill()
		if bench != null: bench.inspection.play_set_down()
		state = "closing"
		arrived.emit()
		play_rattle())
	motion.tween_method(set_opening, 1.0, 0.0, SHUTTER_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	motion.tween_callback(func(): state = "")

## True from accepting the job until the shutter is back down.
func busy() -> bool:
	return state != ""

func play_rattle() -> void:
	if not muted: audio.play()

func set_muted(value: bool) -> void:
	muted = value
	if muted: audio.stop()

func _exit_tree() -> void:
	if audio != null: audio.stop()

## A roller shutter: a quick train of slat clacks over a low sheet-metal rumble.
static func rattle() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4410
	var count := int(SHUTTER_TIME * SHUTTER_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	# Fifteen slat clacks a second.
	var clack_every := 1470
	var rumble := 0.0
	for index in range(count):
		var t := float(index) / SHUTTER_RATE
		var envelope := minf(t / 0.05, 1.0) * minf((SHUTTER_TIME - t) / 0.15, 1.0)
		rumble = rumble * 0.985 + rng.randf_range(-1.0, 1.0) * 0.015
		var since := float(index % clack_every) / SHUTTER_RATE
		var clack := rng.randf_range(-1.0, 1.0) * exp(-since * 140.0) * 0.55 + sin(since * TAU * 900.0) * exp(-since * 90.0) * 0.25
		var sample := clampf((rumble * 6.0 + clack) * envelope, -1.0, 1.0)
		data.encode_s16(index * 2, int(sample * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SHUTTER_RATE
	stream.stereo = false
	stream.data = data
	return stream
