extends Node3D
## A deterministic road-racing test feed. Its presentation cadence follows the card's core
## clock, so a throttling card shows a choppy, stuttering race; hot VRAM corrupts the image.
## The game's sound comes from the monitor speakers and suffers with it: engine and road
## parameters change only on presented frames (stepped pitch at low rates), a hitched frame
## loops the last audio block (the stutter buzz), and memory errors crackle.

signal changed
signal notice(text: String)

const IMAGE_WIDTH := 180
const IMAGE_HEIGHT := 108
## Road view on the left; the right strip is a dark panel behind the Stats label.
const VIEW_WIDTH := 124
const HORIZON := 34
## Pseudo-3D projection: a screen row's depth is CAMERA_HEIGHT * FOCAL / (row - HORIZON).
const CAMERA_HEIGHT := 4.8
const FOCAL := 100.0
const ROAD_HALF_WIDTH := 3.6
const LANE_OFFSET := 1.8
const CAR_WIDTH := 1.8
const STRIPE_LENGTH := 6.0
const PLAYER_DEPTH := 8.0
const LAP_LENGTH := 2600.0
const TOP_SPEED := 64.0
const CORNER_SPEED := 46.0
const RIVAL_COLORS := [Color(0.25, 0.5, 0.92), Color(0.95, 0.78, 0.2), Color(0.3, 0.78, 0.42), Color(0.92, 0.92, 0.9)]
const SKY_TOP := Color(0.16, 0.3, 0.52)
const SKY_HORIZON := Color(0.62, 0.72, 0.82)
const HAZE := Color(0.55, 0.64, 0.7)
const GARBAGE := [Color(1, 0, 1), Color(0, 1, 0.4), Color(1, 1, 1), Color(0.1, 0.9, 1), Color(0, 0, 0)]
const Thermal := preload("res://scripts/gpu_thermal.gd")
const AudioMix = preload("res://scripts/audio_mix.gd")
const AUDIO_RATE := 22050.0
## Length of the block a hitched game repeats until its next frame.
const STUTTER_BLOCK := 0.045
## A frame this many nominal intervals overdue (and at least STALL_MIN late) has hitched.
const STALL_INTERVALS := 1.7
const STALL_MIN := 0.09
## Chance per sample, at full memory errors, of a corrupted (crackling) sample.
const CRACKLE_RATE := 0.002
const GAME_TRIM_DB := -6.0

@onready var screen: MeshInstance3D = $Screen
@onready var button: MeshInstance3D = $PowerButton
@onready var led: MeshInstance3D = $PowerLED
@onready var readout: Label3D = $Readout
@onready var fps_readout: Label3D = $FpsReadout
@onready var stats: Label3D = $Stats
@onready var power_audio: AudioStreamPlayer = $PowerOnSound

var powered := false
var connected := false
var simulated_fps := 60
## The card's own sensors, as monitoring software would report them.
var core_c := 0
var clock_mhz := Thermal.BOOST_CLOCK
var throttle := 0.0
## 0-1 share of VRAM bit errors reaching the feed.
var memory_errors := 0.0
var presented_frames := 0
var frame_time := 0.0
var frame_interval := 0.125
var distance := 0.0
var speed := 0.0
var race_time := 0.0
var lap := 1
var lap_start_time := 0.0
var passed := 0
var player_x := -LANE_OFFSET
var target_lane := -1
var background_scroll := 0.0
var rivals: Array[Dictionary] = []
var lateral_rows := PackedFloat32Array()
var rng := RandomNumberGenerator.new()
var pace_rng := RandomNumberGenerator.new()
var artifact_rng := RandomNumberGenerator.new()
var image: Image
var texture: ImageTexture
var led_material: StandardMaterial3D
var game_audio: AudioStreamPlayer
var audio_playback: AudioStreamGeneratorPlayback
var muted := false
## Sound parameters as the game last submitted them, on its latest presented frame.
var audio_speed := 0.0
var audio_bend := 0.0
var whoosh := 0.0
var engine_phase := 0.0
var squeal_phase := 0.0
var road_fast := 0.0
var road_slow := 0.0
## Ring of the most recent synthesized samples; a stall replays it from the oldest.
var history := PackedFloat32Array()
var history_pos := 0
var loop_pos := 0
var stutter_samples := 0
var crackles := 0
var audio_rng := RandomNumberGenerator.new()

func _ready() -> void:
	button.set_meta("action", "monitor_power")
	power_audio.bus = AudioMix.MONITOR_POWER
	game_audio = AudioStreamPlayer.new()
	game_audio.name = "RacingGameSound"
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = AUDIO_RATE
	generator.buffer_length = 0.1
	game_audio.stream = generator
	game_audio.volume_db = GAME_TRIM_DB
	game_audio.bus = AudioMix.RACING_GAME
	add_child(game_audio)
	history.resize(roundi(STUTTER_BLOCK * AUDIO_RATE))
	image = Image.create(IMAGE_WIDTH, IMAGE_HEIGHT, false, Image.FORMAT_RGB8)
	image.fill(Color(0.075, 0.09, 0.105))
	texture = ImageTexture.create_from_image(image)
	var material: StandardMaterial3D = screen.mesh.surface_get_material(0).duplicate()
	material.albedo_texture = texture
	screen.material_override = material
	led_material = StandardMaterial3D.new()
	led.material_override = led_material
	lateral_rows.resize(IMAGE_HEIGHT)
	reset_simulation()
	update_face()

func set_muted(value: bool) -> void:
	muted = value
	power_audio.volume_db = -80.0 if value else 0.0
	game_audio.volume_db = -80.0 if value else GAME_TRIM_DB

func set_connection(value: bool) -> void:
	connected = value
	reset_simulation()
	update_face()
	changed.emit()

func set_sensors(core: float, clock: int, errors: float) -> void:
	memory_errors = errors
	if roundi(core) == core_c and clock == clock_mhz: return
	core_c = roundi(core)
	clock_mhz = clock
	throttle = clampf(float(Thermal.BOOST_CLOCK - clock) / (Thermal.BOOST_CLOCK - Thermal.THROTTLED_CLOCK), 0.0, 1.0)
	simulated_fps = roundi(lerpf(60.0, 8.0, 1.0 - pow(1.0 - throttle, 2.0)))
	if stats.visible: update_face()

func toggle_power() -> void:
	powered = not powered
	if powered and power_audio.stream != null: power_audio.play()
	reset_simulation()
	update_face()
	notice.emit("Monitor on. %s" % ("Racing test running." if connected else "No GPU signal.") if powered else "Monitor off.")
	changed.emit()

func reset_simulation() -> void:
	rng.seed = 2016
	pace_rng.seed = 1998
	artifact_rng.seed = 404
	presented_frames = 0
	frame_time = 0.0
	frame_interval = next_interval()
	distance = 0.0
	speed = cruise_speed(0.0)
	race_time = 0.0
	lap = 1
	lap_start_time = 0.0
	passed = 0
	player_x = -LANE_OFFSET
	target_lane = -1
	background_scroll = 0.0
	audio_rng.seed = 6502
	audio_speed = speed
	audio_bend = 0.0
	whoosh = 0.0
	history.fill(0.0)
	history_pos = 0
	loop_pos = 0
	stutter_samples = 0
	crackles = 0
	rivals.clear()
	for start in [[26.0, 1], [120.0, -1], [215.0, 1]]:
		rivals.append({"s": start[0], "lane": start[1], "pace": 0.8,
			"color": RIVAL_COLORS[rivals.size() % RIVAL_COLORS.size()]})
	render_image()

func curvature(s: float) -> float:
	# Periodic per lap. The cubed sweep flattens into straights between long bends.
	var sweep := sin(TAU * 3.0 * s / LAP_LENGTH)
	return 0.011 * sweep * sweep * sweep + 0.004 * sin(TAU * 7.0 * s / LAP_LENGTH + 1.3)

func cruise_speed(s: float) -> float:
	return lerpf(TOP_SPEED, CORNER_SPEED, clampf(absf(curvature(s)) / 0.012, 0.0, 1.0))

func next_interval() -> float:
	# A throttling card does not only drop its rate; frame pacing turns uneven, with hitches.
	var interval := 1.0 / float(simulated_fps) * (1.0 + throttle * pace_rng.randf_range(-0.3, 0.6))
	if pace_rng.randf() < 0.08 * throttle: interval *= 2.5
	return interval

func _process(delta: float) -> void:
	if powered and connected: present(delta)
	feed_audio()

func present(delta: float) -> void:
	frame_time = minf(frame_time + delta, 0.5)
	if frame_time < frame_interval: return
	# Each presented frame shows the race as it is now, so slow cadence reads as big jumps.
	advance_demo(frame_time)
	frame_time = 0.0
	frame_interval = next_interval()
	render_image()
	update_face()

## The game is stuck between frames for far longer than its normal cadence.
func is_stalled() -> bool:
	return powered and connected and frame_time > maxf(STALL_INTERVALS / float(simulated_fps), STALL_MIN)

## Keeps the monitor speakers' stream filled while the race runs.
func feed_audio() -> void:
	if not powered or not connected:
		if game_audio.playing: game_audio.stop()
		audio_playback = null
		return
	if not game_audio.playing or audio_playback == null:
		game_audio.play()
		audio_playback = game_audio.get_stream_playback()
	if audio_playback == null: return
	var frames := audio_playback.get_frames_available()
	if frames > 0: audio_playback.push_buffer(render_audio(frames))

func render_audio(count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(count)
	var stalled := is_stalled()
	for n in range(count):
		var sample: float
		if stalled:
			# A hitched game replays its last audio block until the next frame: the stutter buzz.
			sample = history[loop_pos]
			loop_pos = (loop_pos + 1) % history.size()
			stutter_samples += 1
		else:
			sample = synth_sample()
			history[history_pos] = sample
			history_pos = (history_pos + 1) % history.size()
			loop_pos = history_pos
		if memory_errors > 0.0 and audio_rng.randf() < memory_errors * CRACKLE_RATE:
			sample = audio_rng.randf_range(-0.9, 0.9)
			crackles += 1
		out[n] = Vector2(sample, sample)
	return out

## Engine (pitch follows speed), road roar, tyre squeal through tight bends and a whoosh when
## passing a rival. Every tone runs from the game's last submitted parameters.
func synth_sample() -> float:
	var pace := clampf((audio_speed - 30.0) / 40.0, 0.0, 1.0)
	engine_phase = fposmod(engine_phase + (70.0 + 95.0 * pace) / AUDIO_RATE, 1.0)
	var engine := 0.3 * (engine_phase * 2.0 - 1.0) + 0.16 * sin(TAU * engine_phase * 2.0)
	var noise := audio_rng.randf_range(-1.0, 1.0)
	road_fast += (noise - road_fast) * 0.25
	road_slow += (noise - road_slow) * 0.02
	var road := (road_fast - road_slow) * 0.35 * (0.4 + 0.6 * pace)
	squeal_phase = fposmod(squeal_phase + 1150.0 / AUDIO_RATE, 1.0)
	var squeal := sin(TAU * squeal_phase) * 0.1 * clampf((audio_bend - 0.007) / 0.005, 0.0, 1.0) * (0.7 + 0.3 * road_fast)
	whoosh = maxf(0.0, whoosh - 2.0 / AUDIO_RATE)
	var passing := road_fast * whoosh * whoosh * 0.7
	return (engine + road + squeal + passing) * 0.6

func advance_demo(interval: float) -> void:
	presented_frames += 1
	race_time += interval
	speed = cruise_speed(distance)
	var travel := speed * interval
	background_scroll += curvature(distance) * travel * FOCAL
	distance += travel
	if distance >= lap * LAP_LENGTH:
		lap += 1
		lap_start_time = race_time
	for rival in rivals:
		rival.s += cruise_speed(rival.s) * rival.pace * interval
		if rival.s - distance < -2.0:
			passed += 1
			whoosh = 1.0
			respawn(rival)
	# Pass the nearest car ahead on the other lane.
	var nearest := {}
	for rival in rivals:
		var ahead: float = rival.s - distance
		if ahead > PLAYER_DEPTH - 3.0 and ahead < 70.0 and (nearest.is_empty() or rival.s < nearest.s): nearest = rival
	if not nearest.is_empty() and nearest.lane == target_lane: target_lane = -target_lane
	player_x = move_toward(player_x, target_lane * LANE_OFFSET, 4.5 * interval)
	# The game submits new sound parameters only with each presented frame.
	audio_speed = speed
	audio_bend = absf(curvature(distance))

func respawn(rival: Dictionary) -> void:
	var furthest := distance
	for other in rivals: furthest = maxf(furthest, other.s)
	rival.s = furthest + rng.randf_range(70.0, 140.0)
	rival.lane = -1 if rng.randf() < 0.5 else 1
	rival.pace = rng.randf_range(0.74, 0.84)
	rival.color = RIVAL_COLORS[rng.randi_range(0, RIVAL_COLORS.size() - 1)]

func paint_rect(x: float, y: float, width: float, height: float, color: Color, limit: int = VIEW_WIDTH) -> void:
	var rect := Rect2i(roundi(x), roundi(y), maxi(1, roundi(width)), maxi(1, roundi(height)))
	rect = rect.intersection(Rect2i(0, 0, limit, IMAGE_HEIGHT))
	if rect.has_area(): image.fill_rect(rect, color)

func paint_car(centre: float, bottom: float, width: float, color: Color) -> void:
	var height := width * 0.5
	var left := centre - width * 0.5
	paint_rect(left - width * 0.05, bottom - 1.0, width * 1.1, maxf(1.0, height * 0.12), Color(0.05, 0.05, 0.05))
	paint_rect(left, bottom - height * 0.62, width, height * 0.52, color)
	if width < 5.0: return
	paint_rect(left + width * 0.18, bottom - height, width * 0.64, height * 0.4, color.darkened(0.35))
	paint_rect(left + width * 0.24, bottom - height * 0.92, width * 0.52, height * 0.24, Color(0.13, 0.16, 0.2))
	paint_rect(left + width * 0.06, bottom - height * 0.5, width * 0.2, height * 0.14, Color(1.0, 0.25, 0.18))
	paint_rect(left + width * 0.74, bottom - height * 0.5, width * 0.2, height * 0.14, Color(1.0, 0.25, 0.18))

func render_image() -> void:
	if image == null: return
	for y in range(HORIZON):
		paint_rect(0, y, VIEW_WIDTH, 1, SKY_TOP.lerp(SKY_HORIZON, float(y) / HORIZON))
	# Two ridge lines scroll with the track's turning for a sense of heading.
	for x in range(VIEW_WIDTH):
		var far := (x + background_scroll * 0.5) * 0.05
		var near := (x + background_scroll) * 0.09
		var far_height := 7.0 + 4.0 * sin(far) + 2.5 * sin(far * 2.7 + 2.0)
		var near_height := 3.0 + 2.0 * sin(near) + 1.2 * sin(near * 3.1)
		paint_rect(x, HORIZON - far_height, 1, far_height, Color(0.36, 0.44, 0.55))
		paint_rect(x, HORIZON - near_height, 1, near_height, Color(0.22, 0.36, 0.3))
	var heading := 0.0
	var lateral := 0.0
	var previous_depth := 0.0
	for y in range(IMAGE_HEIGHT - 1, HORIZON, -1):
		var depth := CAMERA_HEIGHT * FOCAL / float(y - HORIZON)
		var step := depth - previous_depth
		heading += curvature(distance + depth - step * 0.5) * step
		lateral += heading * step
		previous_depth = depth
		lateral_rows[y] = lateral
		var pixels_per_metre := FOCAL / depth
		var centre := VIEW_WIDTH * 0.5 + (lateral - player_x) * pixels_per_metre
		var half := ROAD_HALF_WIDTH * pixels_per_metre
		var rumble := maxf(1.0, half * 0.12)
		var light := int(floor((distance + depth) / STRIPE_LENGTH)) % 2 == 0
		var haze := clampf(depth / 240.0, 0.0, 0.7)
		paint_rect(0, y, VIEW_WIDTH, 1, (Color(0.26, 0.56, 0.24) if light else Color(0.22, 0.49, 0.2)).lerp(HAZE, haze))
		var kerb := (Color(0.9, 0.9, 0.88) if light else Color(0.78, 0.18, 0.16)).lerp(HAZE, haze)
		paint_rect(centre - half - rumble, y, half * 2.0 + rumble * 2.0, 1, kerb)
		paint_rect(centre - half, y, half * 2.0, 1, (Color(0.4, 0.41, 0.43) if light else Color(0.37, 0.38, 0.4)).lerp(HAZE, haze))
		if light: paint_rect(centre - maxf(0.5, half * 0.02), y, maxf(1.0, half * 0.04), 1, Color(0.92, 0.92, 0.86).lerp(HAZE, haze))
	var nearest_depth := CAMERA_HEIGHT * FOCAL / float(IMAGE_HEIGHT - 1 - HORIZON)
	var ordered := rivals.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary): return a.s > b.s)
	for rival in ordered:
		var ahead: float = rival.s - distance
		if ahead <= nearest_depth or ahead > 300.0: continue
		var row := HORIZON + CAMERA_HEIGHT * FOCAL / ahead
		var pixels_per_metre := FOCAL / ahead
		var road_offset: float = lateral_rows[clampi(int(row), HORIZON + 1, IMAGE_HEIGHT - 1)] + rival.lane * LANE_OFFSET - player_x
		paint_car(VIEW_WIDTH * 0.5 + road_offset * pixels_per_metre, row, CAR_WIDTH * pixels_per_metre, rival.color)
	# The chase camera follows the player; the car drifts slightly outward through bends.
	var drift := clampf(-curvature(distance) * 400.0, -4.0, 4.0)
	paint_car(VIEW_WIDTH * 0.5 + drift, HORIZON + CAMERA_HEIGHT * FOCAL / PLAYER_DEPTH,
		CAR_WIDTH * FOCAL / PLAYER_DEPTH, Color(0.86, 0.17, 0.15))
	if memory_errors > 0.0: paint_memory_errors()
	paint_rect(VIEW_WIDTH, 0, IMAGE_WIDTH - VIEW_WIDTH, IMAGE_HEIGHT, Color(0.44, 0.5, 0.54), IMAGE_WIDTH)
	paint_rect(VIEW_WIDTH + 2, 0, IMAGE_WIDTH - VIEW_WIDTH - 2, IMAGE_HEIGHT, Color(0.038, 0.067, 0.095), IMAGE_WIDTH)
	if texture != null: texture.update(image)

func paint_memory_errors() -> void:
	# Sparkling bit errors first; garbage blocks and torn rows join as VRAM gets hotter.
	for count in range(roundi(memory_errors * 60.0)):
		paint_rect(artifact_rng.randi_range(0, VIEW_WIDTH - 1), artifact_rng.randi_range(0, IMAGE_HEIGHT - 1), 1, 1,
			GARBAGE[artifact_rng.randi_range(0, GARBAGE.size() - 1)])
	if artifact_rng.randf() < memory_errors:
		for block in range(artifact_rng.randi_range(1, 1 + roundi(memory_errors * 4.0))):
			var x := artifact_rng.randi_range(0, VIEW_WIDTH - 12)
			var y := artifact_rng.randi_range(0, IMAGE_HEIGHT - 6)
			var width := artifact_rng.randi_range(2, 6)
			var height := artifact_rng.randi_range(1, 3)
			var first: Color = GARBAGE[artifact_rng.randi_range(0, GARBAGE.size() - 1)]
			var second: Color = GARBAGE[artifact_rng.randi_range(0, GARBAGE.size() - 1)]
			for row in range(height):
				for column in range(width):
					paint_rect(x + column * 2, y + row * 2, 2, 2, first if (row + column) % 2 == 0 else second)
	if artifact_rng.randf() < memory_errors * 0.5:
		var top := artifact_rng.randi_range(0, IMAGE_HEIGHT - 6)
		var band := image.get_region(Rect2i(0, top, VIEW_WIDTH, artifact_rng.randi_range(2, 6)))
		image.blit_rect(band, Rect2i(Vector2i.ZERO, band.get_size()), Vector2i(artifact_rng.randi_range(-20, 20), top))

func lap_clock() -> String:
	var seconds := race_time - lap_start_time
	return "%d:%s" % [int(seconds / 60.0), ("%.1f" % fmod(seconds, 60.0)).pad_zeros(2)]

func update_face() -> void:
	led_material.albedo_color = Color(0.18, 0.67, 0.32) if powered else Color(0.67, 0.32, 0.12)
	if not powered:
		image.fill(Color(0.075, 0.09, 0.105))
		readout.text = ""
	elif not connected:
		image.fill(Color(0.055, 0.105, 0.14))
		readout.text = "NO SIGNAL"
	else:
		readout.text = "RALLY"
	fps_readout.visible = powered and connected
	fps_readout.text = "SIM %02d FPS" % simulated_fps
	stats.visible = powered and connected
	stats.text = "LAP %d\n%s\nMHZ\n%d\nGPU\n%d°C" % [lap, lap_clock(), clock_mhz, core_c]
	if not powered or not connected: texture.update(image)
