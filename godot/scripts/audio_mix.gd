extends RefCounted
## Named mixer channels: every sound player routes to one bus, and Master scales them all.
## Run from the editor, levels save into the project bus layout, so the mix can be committed
## and also edited in the editor's Audio panel. Exported builds keep levels in user settings.
const MASTER := &"Master"
const SCREWDRIVER := &"Screwdriver"
const BLOWER := &"Blower"
const JINGLE := &"Jingle"
const GPU_ATTACH := &"GpuAttach"
const FAN_QUIET := &"FanQuiet"
const FAN_LOUD := &"FanLoud"
const FAN_GRIND := &"FanGrind"
const MONITOR_POWER := &"MonitorPower"
const STICKER_PEEL := &"StickerPeel"
const AIR_BLOWER := &"AirBlower"
const RACING_GAME := &"RacingGame"
const SPUDGER := &"SpudgerScrape"
const IPA_WIPE := &"IpaWipe"
const PC_INPUT := &"PcInput"
const UNBOX := &"Unbox"
const SET_DOWN := &"SetDown"
const OIL_DROP := &"OilDrop"
const PASTE_SQUEEZE := &"PasteSqueeze"
const CHANNELS := [
	[MASTER, "Master"],
	[FAN_QUIET, "Fan, quiet loop"],
	[FAN_LOUD, "Fan, loud loop"],
	[FAN_GRIND, "Dry bearing grind"],
	[AIR_BLOWER, "Air blower motor"],
	[BLOWER, "Dev blower air"],
	[SCREWDRIVER, "Screwdriver"],
	[JINGLE, "Clean jingle"],
	[GPU_ATTACH, "GPU seating"],
	[MONITOR_POWER, "Monitor power button"],
	[RACING_GAME, "Racing test game"],
	[STICKER_PEEL, "Sticker peel"],
	[SPUDGER, "Spudger scrape"],
	[IPA_WIPE, "IPA wipe"],
	[PASTE_SQUEEZE, "Paste squeeze"],
	[OIL_DROP, "Bearing oil drop"],
	[UNBOX, "Unboxing"],
	[SET_DOWN, "Card set down"],
	[PC_INPUT, "Shop PC keys and mouse"]]
const LAYOUT_PATH := "res://default_bus_layout.tres"
const USER_PATH := "user://audio_mix.cfg"
## Sliders run from silent to double loudness (+6 dB).
const MAX_LEVEL := 2.0

## Creates any channel missing from the loaded bus layout, then applies saved user levels.
static func ensure_buses() -> void:
	for channel in CHANNELS:
		if AudioServer.get_bus_index(channel[0]) != -1: continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, channel[0])
		AudioServer.set_bus_send(index, MASTER)
	if not OS.has_feature("editor"):
		var config := ConfigFile.new()
		if config.load(USER_PATH) == OK:
			for channel in CHANNELS:
				set_level(channel[0], config.get_value("levels", String(channel[0]), level(channel[0])))

## Linear gain of a channel: 1.0 is unchanged, 0.0 is silent.
static func level(bus: StringName) -> float:
	var index := AudioServer.get_bus_index(bus)
	if index == -1 or AudioServer.is_bus_mute(index): return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(index))

static func set_level(bus: StringName, value: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index == -1: return
	value = clampf(value, 0.0, MAX_LEVEL)
	AudioServer.set_bus_mute(index, value <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.001)))

static func reset() -> void:
	for channel in CHANNELS: set_level(channel[0], 1.0)

static func save() -> Error:
	if OS.has_feature("editor"):
		return ResourceSaver.save(AudioServer.generate_bus_layout(), LAYOUT_PATH)
	var config := ConfigFile.new()
	for channel in CHANNELS: config.set_value("levels", String(channel[0]), level(channel[0]))
	return config.save(USER_PATH)

static func save_location() -> String:
	return LAYOUT_PATH if OS.has_feature("editor") else "your settings"
