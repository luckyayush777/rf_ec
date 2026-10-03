extends Node
## Time of day from the shop clock (`repair_jobs.shop_minutes`): sun and moon, sky and haze
## colours for `outdoor_scenery.gd`, a sunbeam through the right-wall window, and a dimmer room
## at night. The workshop's key light only dims a little, so repairs remain readable. Leaving through
## the front door (`end_day`) fades out, skips to 09:00 the next day and stands the player back
## at the bench. Created by `workbench.gd` as `DayCycle` in first-person play only.
signal notice(text: String)

const Room = preload("res://scripts/shop_interior.gd")
const Jobs = preload("res://scripts/repair_jobs.gd")
## Sunrise and sunset, in hours. The window faces west (+X), so the sun comes in after noon.
const SUNRISE := 6.0
const SUNSET := 19.5
## Hour keys: zenith, horizon, haze, light colour, light strength, scenery ambient, night.
const KEYS := [
	[0.0, "0b1424", "1b2840", "1a2538", "8fa3d1", 0.22, "1e2a40", 1.0],
	[5.0, "0d1628", "1f2c45", "1d2a3e", "8fa3d1", 0.2, "202c42", 1.0],
	[6.0, "34507a", "e5a07e", "b89a92", "ffb27a", 0.5, "6a7088", 0.35],
	[7.5, "5c9cba", "f1dcbc", "d2d6c8", "ffe4bf", 0.85, "8fa8b0", 0.0],
	[12.0, "4c9bbe", "e8eee2", "cfdcd6", "fff5e3", 1.0, "9ab5bc", 0.0],
	[16.5, "5893b0", "f0d8ae", "dccfb2", "ffdca8", 0.95, "9aaab0", 0.0],
	[18.5, "4a6d92", "ee9a5c", "d39a78", "ff9a55", 0.75, "8a8a98", 0.0],
	[19.5, "2a3a60", "b2627c", "7d5c72", "d07a6a", 0.35, "4c4a66", 0.45],
	[20.5, "121c34", "2c3654", "273249", "8fa3d1", 0.22, "26324a", 0.9],
	[24.0, "0b1424", "1b2840", "1a2538", "8fa3d1", 0.22, "1e2a40", 1.0]]
## Room light by night (x) and by day (y); daytime values are the scene's authored ones. At
## night the key light is the shop's own lamps: a little dimmer and warmer, never off.
const AMBIENT_ENERGY := Vector2(0.3, 0.65)
const FILL_ENERGY := Vector2(0.04, 0.5)
const FILL_NIGHT := Color(0.42, 0.48, 0.72)
const KEY_ENERGY := Vector2(1.35, 1.8)
const KEY_NIGHT := Color(1.0, 0.86, 0.68)
## Strongest sunbeam through the window, and how far out the beam's source sits.
const SUN_BEAM_ENERGY := 14.0
const SUN_BEAM_DISTANCE := 70.0
const FADE_TIME := 0.7
const DARK_TIME := 1.2

var bench: Node3D
var jobs: Node
var scenery: Node3D
var environment: Environment
var fill: DirectionalLight3D
var fill_day: Color
var key_light: DirectionalLight3D
var key_day: Color
var sun_beam: SpotLight3D
var overlay: CanvasLayer
var curtain: ColorRect
var title: Label
## Shortened by tests.
var fade_time := FADE_TIME
var dark_time := DARK_TIME
var busy := false
## The last computed lighting, for tests and the debug status.
var state: Dictionary = {}
var last_minute := -1.0

func configure(world: Node3D, shop_jobs: Node, outdoor: Node3D) -> void:
	bench = world
	jobs = shop_jobs
	scenery = outdoor
	# A private copy: later workbench instances (tests) must not inherit this one's night.
	var world_environment: WorldEnvironment = bench.get_node("Environment")
	world_environment.environment = world_environment.environment.duplicate()
	environment = world_environment.environment
	fill = bench.get_node("FillLight")
	fill_day = fill.light_color
	key_light = bench.get_node("KeyLight")
	key_day = key_light.light_color
	sun_beam = SpotLight3D.new()
	sun_beam.name = "WindowSunbeam"
	sun_beam.spot_range = 150.0
	sun_beam.spot_angle = 11.0
	sun_beam.spot_attenuation = 0.4
	sun_beam.shadow_enabled = true
	bench.add_child(sun_beam)
	overlay = CanvasLayer.new()
	overlay.name = "DayTransition"
	overlay.layer = 20
	add_child(overlay)
	curtain = ColorRect.new()
	curtain.color = Color(0, 0, 0, 0)
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(curtain)
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.modulate = Color(1, 1, 1, 0)
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(title)
	overlay.visible = false
	update()

func _process(_delta: float) -> void:
	update()

func hour() -> float:
	return fmod(jobs.shop_minutes, 1440.0) / 60.0

## Direction toward the sun: up from the east (-X) at sunrise, across the south (+Z), down in
## the west (+X) at sunset, and below the horizon at night.
static func sun_direction(at_hour: float) -> Vector3:
	var angle := (at_hour - SUNRISE) / (SUNSET - SUNRISE) * PI
	return Vector3(-cos(angle), sin(angle) * 0.9, sin(angle) * 0.42 + 0.05).normalized()

static func sample(at_hour: float) -> Array:
	for index in range(KEYS.size() - 1):
		var a: Array = KEYS[index]
		var b: Array = KEYS[index + 1]
		if at_hour > b[0]: continue
		var t := smoothstep(0.0, 1.0, (at_hour - a[0]) / (b[0] - a[0]))
		var mixed := [at_hour]
		for slot in range(1, a.size()):
			if a[slot] is String: mixed.append(Color(a[slot]).lerp(Color(b[slot]), t))
			else: mixed.append(lerpf(a[slot], b[slot], t))
		return mixed
	return KEYS[0]

## Lighting for the current shop time, pushed to the sky, scenery and room.
func update() -> void:
	var now := hour()
	var key := sample(now)
	var sun := sun_direction(now)
	var moon := Vector3(-sun.x, -sun.y * 0.85 + 0.1, 0.35).normalized()
	var daylight := smoothstep(-0.1, 0.25, sun.y)
	var light: Color = key[4]
	var strength: float = key[5]
	state = {"hour": now, "sun_dir": sun, "moon_dir": moon, "light_dir": sun if sun.y > 0.0 else moon,
		"light_color": light * strength, "zenith_color": key[1], "horizon_color": key[2], "haze_color": key[3],
		"ambient_color": key[6], "night": key[7], "sun_visible": smoothstep(-0.03, 0.02, sun.y),
		"cloud_shift": jobs.shop_minutes * 0.004, "daylight": daylight}
	scenery.apply(state)
	environment.ambient_light_energy = lerpf(AMBIENT_ENERGY.x, AMBIENT_ENERGY.y, daylight)
	fill.light_energy = lerpf(FILL_ENERGY.x, FILL_ENERGY.y, daylight)
	fill.light_color = FILL_NIGHT.lerp(fill_day, daylight)
	key_light.light_energy = lerpf(KEY_ENERGY.x, KEY_ENERGY.y, daylight)
	key_light.light_color = KEY_NIGHT.lerp(key_day, daylight)
	# The sun only reaches in through the west window in the afternoon.
	var entry := clampf(sun.x * 3.0, 0.0, 1.0) * clampf(sun.y * 6.0, 0.0, 1.0)
	var window := Vector3((Room.WALL_X.x + Room.WALL_X.y) * 0.5, (Room.SILL_Y + Room.WINDOW_TOP) * 0.5,
		(Room.WINDOW_Z.x + Room.WINDOW_Z.y) * 0.5)
	sun_beam.visible = entry > 0.01
	sun_beam.light_energy = SUN_BEAM_ENERGY * entry * strength
	sun_beam.light_color = light
	state.sun_beam = sun_beam.light_energy if sun_beam.visible else 0.0
	if sun_beam.visible:
		sun_beam.global_position = window + sun * SUN_BEAM_DISTANCE
		sun_beam.look_at(window, Vector3.UP if absf(sun.y) < 0.98 else Vector3.FORWARD)
	# Closing time is a reminder, not a lock-out.
	var minute := fmod(jobs.shop_minutes, 1440.0)
	if last_minute >= 0.0 and last_minute < Jobs.CLOSING_MINUTE and minute >= Jobs.CLOSING_MINUTE:
		notice.emit("21:00, closing time. Leave through the front door to end the day.")
	last_minute = minute

## Fades out, opens the next day at 09:00 and stands the player back by the bench.
func end_day() -> void:
	if busy: return
	busy = true
	var closed_day: int = jobs.day()
	overlay.visible = true
	title.text = "Shop closed - end of day %d" % closed_day
	var fade := create_tween().set_parallel()
	fade.tween_property(curtain, "color:a", 1.0, fade_time)
	fade.tween_property(title, "modulate:a", 1.0, fade_time)
	await fade.finished
	jobs.start_next_day()
	bench.camera_rig.respawn()
	update()
	title.text = "DAY %d\n%s" % [jobs.day(), Jobs.clock_text(jobs.shop_minutes).get_slice("  ", 1)]
	await get_tree().create_timer(dark_time).timeout
	fade = create_tween().set_parallel()
	fade.tween_property(curtain, "color:a", 0.0, fade_time)
	fade.tween_property(title, "modulate:a", 0.0, fade_time)
	await fade.finished
	overlay.visible = false
	busy = false
