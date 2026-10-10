extends Node
## Time of day from the shop clock (`repair_jobs.shop_minutes`): sun and moon, sky and haze
## colours for `outdoor_scenery.gd`. The view outside changes; the room does not. The workshop
## is lit evenly by its own lights at every hour, with no daylight coming in through the window;
## the lighting upgrade only brightens it a little. Leaving through the front door (`end_day`)
## fades out, skips to 09:00 the next day and stands the player back at the bench. Created by
## `workbench.gd` as `DayCycle` in first-person play only.
signal notice(text: String)

const Jobs = preload("res://scripts/repair_jobs.gd")
## Sunrise and sunset, in hours. The window faces west (+X), so the sun comes in after noon.
const SUNRISE := 6.0
const SUNSET := 19.5
## Hour keys: zenith, horizon, haze, light colour, light strength, scenery ambient, night.
const KEYS := [
	[0.0, "0b1424", "1b2840", "1a2538", "8fa3d1", 0.22, "1e2a40", 1.0],
	[5.0, "0d1628", "1f2c45", "1d2a3e", "8fa3d1", 0.2, "202c42", 1.0],
	[6.0, "34507a", "e5a07e", "b89a92", "ffb27a", 0.5, "6a7088", 0.35],
	[7.5, "4f94cc", "d6e6e8", "b8d0dc", "ffe6c4", 0.9, "8eabc0", 0.0],
	[12.0, "3a88d2", "c6e2f2", "a9cce2", "fff4e0", 1.0, "8fb2cc", 0.0],
	[16.5, "4a8ac6", "e8dcc0", "c4cdd4", "ffdca8", 0.95, "98a8bc", 0.0],
	[18.5, "4a6d92", "ee9a5c", "d39a78", "ff9a55", 0.75, "8a8a98", 0.0],
	[19.5, "2a3a60", "b2627c", "7d5c72", "d07a6a", 0.35, "4c4a66", 0.45],
	[20.5, "121c34", "2c3654", "273249", "8fa3d1", 0.22, "26324a", 0.9],
	[24.0, "0b1424", "1b2840", "1a2538", "8fa3d1", 0.22, "1e2a40", 1.0]]
## The purchased workshop lighting scales the scene's authored room light by this much.
const LIGHTING_UPGRADE := 1.2
## Whole-scene light level: the room's lights and the light on the outdoor view together. The
## authored rig washed the room out, so play starts toned down; the Escape menu's debug
## Lighting slider changes it (`set_light_scale`).
const DEFAULT_LIGHT := 0.75
const LIGHT_RANGE := Vector2(0.2, 1.6)
## Ambient light is cut a little further than the lamps, so surfaces keep their shading.
const AMBIENT_TRIM := 0.8
const FADE_TIME := 0.7
const DARK_TIME := 1.2

var bench: Node3D
var jobs: Node
var scenery: Node3D
var environment: Environment
var fill: DirectionalLight3D
var key_light: DirectionalLight3D
var bounce: DirectionalLight3D
## The scene's authored ambient, fill and key energies, and the bounce light's.
var base_energy := Vector3.ZERO
var base_bounce := 0.0
var light_scale := DEFAULT_LIGHT
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
	# A private copy: later workbench instances (tests) must not inherit this one's upgrade.
	var world_environment: WorldEnvironment = bench.get_node("Environment")
	world_environment.environment = world_environment.environment.duplicate()
	environment = world_environment.environment
	fill = bench.get_node("FillLight")
	key_light = bench.get_node("KeyLight")
	bounce = bench.get_node("BounceLight")
	base_energy = Vector3(environment.ambient_light_energy, fill.light_energy, key_light.light_energy)
	base_bounce = bounce.light_energy
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

func set_light_scale(value: float) -> void:
	light_scale = clampf(value, LIGHT_RANGE.x, LIGHT_RANGE.y)
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

## The outside for the current shop time, pushed to the sky and scenery, and the room's light.
func update() -> void:
	var now := hour()
	var key := sample(now)
	var sun := sun_direction(now)
	var moon := Vector3(-sun.x, -sun.y * 0.85 + 0.1, 0.35).normalized()
	var daylight := smoothstep(-0.1, 0.25, sun.y)
	var light: Color = key[4]
	var strength: float = key[5] * light_scale
	var ambient: Color = key[6]
	ambient = Color(ambient.r * light_scale, ambient.g * light_scale, ambient.b * light_scale)
	state = {"hour": now, "sun_dir": sun, "moon_dir": moon, "light_dir": sun if sun.y > 0.0 else moon,
		"light_color": light * strength, "zenith_color": key[1], "horizon_color": key[2], "haze_color": key[3],
		"ambient_color": ambient, "night": key[7], "sun_visible": smoothstep(-0.03, 0.02, sun.y),
		"cloud_shift": jobs.shop_minutes * 0.004, "daylight": daylight}
	scenery.apply(state)
	var level := light_scale * (LIGHTING_UPGRADE if bench.shop != null and bench.shop.owns("lighting") else 1.0)
	var room := base_energy * level
	environment.ambient_light_energy = room.x * AMBIENT_TRIM
	fill.light_energy = room.y
	key_light.light_energy = room.z
	bounce.light_energy = base_bounce * level
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
