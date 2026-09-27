extends SceneTree
var failures: Array[String] = []
func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var mix = load("res://scripts/audio_mix.gd")
	var bench = load("res://scenes/workbench.tscn").instantiate()
	root.add_child(bench)
	await process_frame
	var hud: CanvasLayer = bench.hud
	# Every sound in the scene has its own mixer channel under Master.
	var players: Array = bench.find_children("*", "AudioStreamPlayer", true, false)
	expect(players.size() >= 11, "Expected every sound player in the workbench, found %d" % players.size())
	var channels: Array = mix.CHANNELS.map(func(channel): return channel[0])
	for player in players:
		expect(player.bus != &"Master" and player.bus in channels and AudioServer.get_bus_index(player.bus) != -1,
			"%s is not routed to a mixer channel (%s)" % [player.get_path(), player.bus])
	for channel in mix.CHANNELS:
		var index := AudioServer.get_bus_index(channel[0])
		expect(index != -1, "Missing bus " + channel[0])
		if channel[0] != &"Master": expect(AudioServer.get_bus_send(index) == &"Master", channel[0] + " does not send to Master")
	# The Escape menu shows the mixer; capturing the mouse hides it.
	hud.set_menu_open(true)
	expect(hud.audio_panel.visible and hud.audio_sliders.size() == mix.CHANNELS.size(), "Escape menu did not show one slider per channel")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		bench.camera_rig.set_captured(false)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/audio-mix.png")
	var fan_loud: HSlider = hud.audio_sliders[&"FanLoud"]
	fan_loud.value = 50
	expect(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"FanLoud")) - linear_to_db(0.5)) < 0.01,
		"Fan slider did not set its bus to half gain")
	expect(hud.audio_values[&"FanLoud"].text == "50%", "Slider value label did not update")
	hud.audio_sliders[&"Master"].value = 0
	expect(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master")), "Master at 0% did not mute")
	# Levels are saved from the editor into the project layout; keep this test from writing it.
	expect(not hud.audio_save_timer.is_stopped(), "Slider changes did not schedule a save")
	hud.audio_save_timer.stop()
	mix.reset()
	hud.refresh_audio_panel()
	expect(is_equal_approx(mix.level(&"Master"), 1.0) and fan_loud.value == 100, "Reset did not restore 100%")
	hud.set_menu_open(false)
	expect(not hud.audio_panel.visible, "Mixer stayed open with the mouse captured")
	bench.queue_free()
	await process_frame
	print("PASS: per-sound mixer channels, Escape-menu sliders, master mute and reset" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
