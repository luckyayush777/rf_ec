extends Node
## Moves the assembled GPU between the repair holder and the PCIe test fixture.
const AudioMix = preload("res://scripts/audio_mix.gd")

signal changed
signal notice(text: String)

var gpu: Node3D
var board: Node3D
var monitor: Node3D
var inspection: Node
var service: Node
var tools: Node
var cleaning: Node
## Set by workbench.gd; a dry fan bearing grinds while the fan spins.
var bearing: Node
var home := Transform3D.IDENTITY
var installed := false
var moving := false
var motion: Tween
var attach_audio: AudioStreamPlayer
var quiet_audio: AudioStreamPlayer
var loud_audio: AudioStreamPlayer
var grind_audio: AudioStreamPlayer
var muted := false
var rotor: Node3D
var rotor_home := Transform3D.IDENTITY
var fan_label: Node3D
var label_home := Transform3D.IDENTITY
var fan_angle := 0.0
var fan_speed := 0.0
var fan_demand := 0.0
# Visual turns/second are deliberately below real RPM to limit frame aliasing.
const CLEAN_FAN_SPEED := 2.0
const DIRTY_FAN_SPEED := 7.0
## An idle fan in the shop blower's jet freewheels faster than it runs, then coasts down.
const AIR_FAN_SPEED := 9.0
const AIR_SPIN_UP := 6.0
const AIR_COAST := 2.5
## The jet keeps driving the rotor this long after the last frame it hit it.
const AIR_HOLD_MSEC := 150
var air_until := 0
var air_spun := false
## Rocking the seated card in its slot (the wiggle test). The card tilts about its connector
## line on a damped spring; gpu_connector.gd reads the angle to open a lifted finger.
const ROCK_LIMIT := 0.06
const ROCK_PUSH := 0.012
const ROCK_STIFFNESS := 140.0
const ROCK_DAMPING := 9.0
var seated_pose := Transform3D.IDENTITY
var rock_angle := 0.0
var rock_velocity := 0.0
var wiggling := false
## A supplied recording replaces the synthesized placeholder grind.
const GRIND_RECORDING := "res://assets/sounds/fan_grind.wav"
## The edge connector's centre line in card space (imported connector meshes sit at z 1.43).
const CONNECTOR_LINE := 1.43

func configure(card: Node3D, test_board: Node3D, display: Node3D, inspect: Node,
		gpu_service: Node, workbench_tools: Node, gpu_cleaning: Node) -> void:
	gpu = card
	board = test_board
	monitor = display
	inspection = inspect
	service = gpu_service
	tools = workbench_tools
	cleaning = gpu_cleaning
	home = gpu.global_transform
	board.set_meta("action", "test_board")
	attach_audio = AudioStreamPlayer.new()
	attach_audio.name = "GPUAttachSound"
	attach_audio.stream = preload("res://assets/sounds/gpu_sounds/gpu_attach_short.wav")
	attach_audio.bus = AudioMix.GPU_ATTACH
	board.add_child(attach_audio)
	rotor = gpu.find_child("fan-rotor", true, false)
	rotor_home = rotor.transform
	fan_label = gpu.find_child("fan-brand-label", true, false)
	label_home = fan_label.transform
	quiet_audio = make_fan_audio("QuietFan", preload("res://assets/sounds/ambient_gpu.wav"), AudioMix.FAN_QUIET)
	loud_audio = make_fan_audio("LoudFan", preload("res://assets/sounds/loud_gpu.wav"), AudioMix.FAN_LOUD)
	grind_audio = AudioStreamPlayer.new()
	grind_audio.name = "BearingGrind"
	grind_audio.stream = load(GRIND_RECORDING) if ResourceLoader.exists(GRIND_RECORDING) else make_grind_stream()
	grind_audio.volume_db = -80.0
	grind_audio.bus = AudioMix.FAN_GRIND
	add_child(grind_audio)
	build_display_cable()

func make_fan_audio(node_name: String, source: AudioStreamWAV, bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = bus
	var stream := source.duplicate() as AudioStreamWAV
	# Loop the sustained middle of each recording, excluding its start/end.
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = stream.mix_rate
	stream.loop_end = int((stream.get_length() - 1.0) * stream.mix_rate)
	player.stream = stream
	player.volume_db = -80.0
	add_child(player)
	return player

func begin_wiggle() -> bool:
	if not installed or moving: return false
	wiggling = true
	return true

func end_wiggle() -> void:
	wiggling = false

## Mouse travel while holding the seated card pushes it side to side.
func rock(pixels: float) -> void:
	if wiggling: rock_velocity += pixels * ROCK_PUSH

func update_rock(delta: float) -> void:
	if not installed or moving:
		rock_angle = 0.0
		rock_velocity = 0.0
		return
	rock_velocity += (-ROCK_STIFFNESS * rock_angle - ROCK_DAMPING * rock_velocity) * delta
	rock_angle += rock_velocity * delta
	if absf(rock_angle) > ROCK_LIMIT:
		rock_angle = clampf(rock_angle, -ROCK_LIMIT, ROCK_LIMIT)
		rock_velocity = 0.0
	if not wiggling and absf(rock_angle) < 0.0005 and absf(rock_velocity) < 0.01:
		rock_angle = 0.0
		rock_velocity = 0.0
	# Tilt about the connector line, which runs along the card's length in the slot.
	var pivot: Vector3 = seated_pose * Vector3(0, 0, CONNECTOR_LINE)
	var axis: Vector3 = seated_pose.basis.x.normalized()
	gpu.global_transform = Transform3D(Basis(axis, rock_angle), pivot) * Transform3D(Basis.IDENTITY, -pivot) * seated_pose

func _process(delta: float) -> void:
	update_rock(delta)
	if rotor == null: return
	var running := installed and not moving
	var blown := not running and Time.get_ticks_msec() < air_until
	if running: air_spun = false
	elif blown: air_spun = true
	var target_demand := clampf(1.0 - float(cleaning.progress), 0.0, 1.0)
	fan_demand = lerpf(fan_demand, target_demand, 1.0 - exp(-delta * 3.0))
	var target_speed := lerpf(CLEAN_FAN_SPEED, DIRTY_FAN_SPEED, fan_demand) if running else AIR_FAN_SPEED if blown else 0.0
	fan_speed = move_toward(fan_speed, target_speed, delta * (AIR_SPIN_UP if blown else AIR_COAST if air_spun else 10.0))
	if fan_speed == 0.0: air_spun = false
	update_fan_audio(running)
	# A stopped fan belongs to the bench: restore the authored pose once, then leave the
	# rotor and sticker free for service (gpu_bearing.gd pulls and peels them).
	if not running and fan_speed == 0.0:
		if fan_angle != 0.0:
			fan_angle = 0.0
			rotor.transform = rotor_home
			fan_label.transform = label_home
		return
	fan_angle = fposmod(fan_angle + fan_speed * TAU * delta, TAU)
	# glTF converts Blender's rotor Z axis to Godot Y. Preserve imported bases.
	var spin := Transform3D(Basis(Vector3.UP, fan_angle), Vector3.ZERO)
	rotor.transform = rotor_home * spin
	# The authored hub label is a sibling of the rotor; orbit it about that pivot.
	fan_label.transform = rotor_home * spin * rotor_home.affine_inverse() * label_home

## Placeholder: gritty scraping pulses once per rotor turn over a rough low drone. Loops seamlessly.
func make_grind_stream() -> AudioStreamWAV:
	var rate := 22050
	var length := rate * 2
	var data := PackedByteArray()
	data.resize(length * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 710
	var fast := 0.0
	var slow := 0.0
	var tick := 0.0
	for n in range(length):
		var t := float(n) / rate
		var scrape := pow(0.5 + 0.5 * sin(TAU * 14.0 * t), 6.0)
		var noise := rng.randf_range(-1.0, 1.0)
		# Difference of two one-pole low-passes: a crude band-pass for grit.
		fast += (noise - fast) * 0.35
		slow += (noise - slow) * 0.06
		tick = 1.0 if rng.randf() < 0.0012 else tick * 0.985
		var drone := sin(TAU * 95.0 * t + 2.0 * sin(TAU * 7.0 * t)) * (0.4 + 0.6 * scrape)
		var sample := (fast - slow) * (0.35 + 0.9 * scrape) + 0.22 * drone + 0.35 * tick * noise
		data.encode_s16(n * 2, clampi(roundi(sample * 0.6 * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = length
	return stream

func update_fan_audio(running: bool) -> void:
	for player in [quiet_audio, loud_audio]:
		if running and not player.playing: player.play(1.0)
		elif not running: player.stop()
	var spin_gain := clampf(fan_speed / CLEAN_FAN_SPEED, 0.0, 1.0)
	# Preserve the recordings' character; add the stronger layer as dust rises.
	quiet_audio.volume_db = -80.0 if muted else linear_to_db(maxf(0.0001, spin_gain * lerpf(0.35, 0.15, fan_demand)))
	loud_audio.volume_db = -80.0 if muted else linear_to_db(maxf(0.0001, spin_gain * fan_demand))
	# A rotor spun by the air blower grinds on a dry bearing too: a bench-side diagnosis.
	var grinding: bool = (running or air_spun) and bearing != null and bearing.dry
	if grinding and not grind_audio.playing: grind_audio.play()
	elif not grinding and fan_speed == 0.0: grind_audio.stop()
	grind_audio.volume_db = -80.0 if muted or bearing == null or not bearing.dry else linear_to_db(maxf(0.0001, spin_gain * 0.6))

## Called each frame the air blower's jet hits the rotor. A pulled rotor or peeled sticker is
## left alone, and a powered fan is already driven by its motor.
func blow_fan() -> void:
	if installed or moving or (bearing != null and not bearing.opened.is_empty()): return
	air_until = Time.get_ticks_msec() + AIR_HOLD_MSEC

func build_display_cable() -> void:
	var cable := Node3D.new()
	cable.name = "BoardToMonitorCable"
	monitor.get_parent().add_child(cable)
	var points := [
		board.global_position + Vector3(0.7, 0.3, 0),
		board.global_position + Vector3(0.9, 0.15, -1.0),
		Vector3(20.78, 0.42, -1.35),
		Vector3(20.78, 2.1, 0.06)]
	var jacket := StandardMaterial3D.new()
	jacket.albedo_color = Color(0.045, 0.05, 0.055)
	jacket.roughness = 0.85
	for index in range(points.size() - 1):
		var start: Vector3 = points[index]
		var finish: Vector3 = points[index + 1]
		var length := start.distance_to(finish)
		var segment := MeshInstance3D.new()
		segment.name = "CableSegment%d" % index
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.035
		mesh.bottom_radius = 0.035
		mesh.height = length
		mesh.material = jacket
		segment.mesh = mesh
		cable.add_child(segment)
		segment.global_position = (start + finish) * 0.5
		segment.global_basis = Basis(Quaternion(Vector3.UP, (finish - start).normalized()))

func set_muted(value: bool) -> void:
	muted = value
	attach_audio.volume_db = -80.0 if value else 0.0
	update_fan_audio(installed and not moving)

func can_attach() -> bool:
	if moving or inspection.moving or service.busy or tools.busy: return false
	if service.held_part != "" or tools.equipped_tool != "": return false
	if not service.removed.is_empty() or not service.cable_connected: return false
	return true

func toggle_gpu() -> bool:
	if installed: return detach()
	return attach()

func attach() -> bool:
	if installed or moving: return false
	if not gpu.visible:
		notice.emit("No card on the bench. Accept a job on the shop computer.")
		return false
	if not can_attach():
		notice.emit("Reassemble the GPU, reconnect its cable, set it down, and free your hands before testing.")
		return false
	var bounds: AABB = preload("res://scripts/asset_contract.gd").bounds_in(gpu)
	inspection.held = false
	var basis := Basis(Vector3.RIGHT, PI / 2.0).scaled(home.basis.get_scale())
	var slot_center := board.global_transform * Vector3.ZERO
	# Imported board origin is not guaranteed to be at the slot. Use the socket mesh.
	var socket: Node3D = board.find_child("pcie-x16-socket", true, false)
	if socket != null: slot_center = socket.global_position
	var destination := Transform3D(basis, slot_center + Vector3(0.125, 0.475, 0.165) - basis * bounds.get_center())
	moving = true
	changed.emit()
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	motion.tween_property(gpu, "global_transform", destination, 0.55)
	motion.finished.connect(func():
		seated_pose = destination
		installed = true
		moving = false
		monitor.set_connection(true)
		if attach_audio.stream != null:
			attach_audio.play()
		changed.emit()
		notice.emit("GPU seated in the test board. %s" % ("Racing test running." if monitor.powered else "Press the monitor power button.")))
	return true

func detach() -> bool:
	if not installed or moving or service.busy or tools.busy: return false
	attach_audio.stop()
	wiggling = false
	moving = true
	monitor.set_connection(false)
	update_fan_audio(false)
	changed.emit()
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	motion.tween_property(gpu, "global_transform", home, 0.55)
	motion.finished.connect(func():
		gpu.global_transform = home
		installed = false
		moving = false
		changed.emit()
		notice.emit("GPU returned to the repair holder."))
	return true

func _exit_tree() -> void:
	for player in [quiet_audio, loud_audio, grind_audio]:
		if player != null:
			player.stop()
			player.stream = null
	if attach_audio != null:
		attach_audio.stop()
		attach_audio.stream = null
