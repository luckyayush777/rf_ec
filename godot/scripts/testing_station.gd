extends Node
## Moves the assembled GPU between the repair holder and the PCIe test fixture.

signal changed
signal notice(text: String)

var gpu: Node3D
var board: Node3D
var monitor: Node3D
var inspection: Node
var service: Node
var tools: Node
var cleaning: Node
var home := Transform3D.IDENTITY
var installed := false
var moving := false
var motion: Tween
var attach_audio: AudioStreamPlayer
var quiet_audio: AudioStreamPlayer
var loud_audio: AudioStreamPlayer
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
	board.add_child(attach_audio)
	rotor = gpu.find_child("fan-rotor", true, false)
	rotor_home = rotor.transform
	fan_label = gpu.find_child("fan-brand-label", true, false)
	label_home = fan_label.transform
	quiet_audio = make_fan_audio("QuietFan", preload("res://assets/sounds/ambient_gpu.wav"))
	loud_audio = make_fan_audio("LoudFan", preload("res://assets/sounds/loud_gpu.wav"))
	build_display_cable()

func make_fan_audio(node_name: String, source: AudioStreamWAV) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	var stream := source.duplicate() as AudioStreamWAV
	# Loop the sustained middle of each recording, excluding its start/end.
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = stream.mix_rate
	stream.loop_end = int((stream.get_length() - 1.0) * stream.mix_rate)
	player.stream = stream
	player.volume_db = -80.0
	add_child(player)
	return player

func _process(delta: float) -> void:
	if rotor == null: return
	var running := installed and not moving
	var target_demand := clampf(1.0 - float(cleaning.progress), 0.0, 1.0)
	fan_demand = lerpf(fan_demand, target_demand, 1.0 - exp(-delta * 3.0))
	var target_speed := lerpf(CLEAN_FAN_SPEED, DIRTY_FAN_SPEED, fan_demand) if running else 0.0
	fan_speed = move_toward(fan_speed, target_speed, delta * 10.0)
	fan_angle = fposmod(fan_angle + fan_speed * TAU * delta, TAU)
	# glTF converts Blender's rotor Z axis to Godot Y. Preserve imported bases.
	var spin := Transform3D(Basis(Vector3.UP, fan_angle), Vector3.ZERO)
	rotor.transform = rotor_home * spin
	# The authored hub label is a sibling of the rotor; orbit it about that pivot.
	fan_label.transform = rotor_home * spin * rotor_home.affine_inverse() * label_home
	if not running and fan_speed == 0.0:
		fan_angle = 0.0
		rotor.transform = rotor_home
		fan_label.transform = label_home
	update_fan_audio(running)

func update_fan_audio(running: bool) -> void:
	for player in [quiet_audio, loud_audio]:
		if running and not player.playing: player.play(1.0)
		elif not running: player.stop()
	var spin_gain := clampf(fan_speed / CLEAN_FAN_SPEED, 0.0, 1.0)
	# Preserve the recordings' character; add the stronger layer as dust rises.
	quiet_audio.volume_db = -80.0 if muted else linear_to_db(maxf(0.0001, spin_gain * lerpf(0.35, 0.15, fan_demand)))
	loud_audio.volume_db = -80.0 if muted else linear_to_db(maxf(0.0001, spin_gain * fan_demand))

func build_display_cable() -> void:
	var cable := Node3D.new()
	cable.name = "BoardToMonitorCable"
	monitor.get_parent().add_child(cable)
	var points := [
		Vector3(18.38, 0.7, -0.28),
		Vector3(18.65, 0.42, -1.35),
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
	if moving or inspection.held or inspection.moving or service.busy or tools.busy: return false
	if service.held_part != "" or tools.equipped_tool != "": return false
	if not service.removed.is_empty() or not service.cable_connected: return false
	return true

func toggle_gpu() -> bool:
	if installed: return detach()
	return attach()

func attach() -> bool:
	if installed or moving: return false
	if not can_attach():
		notice.emit("Reassemble the GPU, reconnect its cable, set it down, and free your hands before testing.")
		return false
	var bounds: AABB = preload("res://scripts/asset_contract.gd").bounds_in(gpu)
	var basis := Basis(Vector3.RIGHT, PI / 2.0).scaled(Vector3.ONE * 0.5)
	var slot_center := board.global_transform * Vector3.ZERO
	# Imported board origin is not guaranteed to be at the slot. Use the socket mesh.
	var socket: Node3D = board.find_child("pcie-x16-socket", true, false)
	if socket != null: slot_center = socket.global_position
	var destination := Transform3D(basis, slot_center + Vector3(0.25, 0.95, 0.33) - basis * bounds.get_center())
	moving = true
	changed.emit()
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	motion.tween_property(gpu, "global_transform", destination, 0.55)
	motion.finished.connect(func():
		installed = true
		moving = false
		monitor.set_connection(true, cleaning.progress)
		if attach_audio.stream != null:
			attach_audio.play()
		changed.emit()
		notice.emit("GPU seated in the test board. %s" % ("Tetris test running." if monitor.powered else "Press the monitor power button.")))
	return true

func detach() -> bool:
	if not installed or moving or service.busy or tools.busy: return false
	attach_audio.stop()
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
	for player in [quiet_audio, loud_audio]:
		if player != null:
			player.stop()
			player.stream = null
	if attach_audio != null:
		attach_audio.stop()
		attach_audio.stream = null
