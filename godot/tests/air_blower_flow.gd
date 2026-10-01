extends SceneTree
var failures: Array[String] = []
func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/" + name + ".png")
func settle(bench: Node3D) -> void:
	for step in range(120):
		await process_frame
		if not bench.tool_selection_busy and not bench.tools.busy and not bench.inspection.moving: return
## Headless frames run uncapped, so hold actions for real time rather than a frame count.
func hold(view: Node, pointer: Vector2, msec: int) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < msec:
		view.cleaning_pointer = pointer
		view.clean_under_pointer(1.0 / 60.0)
		await process_frame
func wait_for(condition: Callable, msec: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < msec:
		if condition.call(): return true
		await process_frame
	return condition.call()
func run() -> void:
	var bench = load("res://scenes/workbench.tscn").instantiate()
	root.add_child(bench)
	await process_frame
	bench.camera_rig.set_physics_process(false)
	bench.camera_rig.body.position = Vector3(0, -4.35, 6.2)
	bench.camera_rig.update_camera()
	var dust = bench.cleaning
	# Deposition: fin inlet felt follows the blade sweep; the board collects the fin exhaust.
	var context: Dictionary = dust.airflow_context(bench.gpu)
	expect(not context.is_empty() and context.has("cooler"), "Airflow context is missing the fan or cooler")
	if context.has("cooler"):
		var center: Vector3 = context.center - Vector3(0, 0.05, 0)
		var radius: float = context.radius
		var inlet := {"transform": Transform3D.IDENTITY, "owner": "cooler-assembly", "outward": Vector3.UP, "context": context}
		var under_blades: float = dust.deposit_weight(inlet, center + Vector3(radius * 0.7, 0, 0))
		expect(under_blades > dust.deposit_weight(inlet, center) and under_blades > dust.deposit_weight(inlet, center + Vector3(radius * 2.0, 0, 0)),
			"Fin inlet felt does not follow the blade sweep")
		var box: AABB = context.cooler
		var board := {"transform": Transform3D.IDENTITY, "owner": "board", "outward": Vector3.UP, "context": context}
		expect(dust.deposit_weight(board, Vector3(box.end.x + 0.03, box.position.y, box.get_center().z)) >
			dust.deposit_weight(board, Vector3(box.end.x + 0.6, box.position.y, box.get_center().z)), "Board dust does not gather at the fin exhaust")
	var film := 0
	var felt := 0
	for surface in dust.surfaces:
		for value in surface.data:
			if value > 0 and value < 100: film += 1
			elif value >= 180: felt += 1
		var material: ShaderMaterial = surface.mesh.material_overlay
		expect(material.get_shader_parameter("dust_noise") != null, "Dust overlay has no clump noise: " + surface.name)
	expect(film > 0 and felt > 0, "Dust has no thickness range from film to felt")
	# The shop blower comes from the tool bag like any other tool.
	bench.open_tool_menu(true)
	await settle(bench)
	await capture("air-blower-roll")
	await bench.select_tool("air-blower")
	await settle(bench)
	expect(bench.tools.equipped_tool == "air-blower" and bench.tools.blower_equipped(), "Air blower could not be equipped from the bag")
	expect(bench.tools.tool_node("air-blower").visible, "Air blower is hidden")
	var card: Vector3 = bench.gpu.global_transform * preload("res://scripts/asset_contract.gd").bounds_in(bench.gpu).get_center()
	bench.camera_rig.camera.look_at(card)
	bench.camera_rig.look_pitch = bench.camera_rig.camera.rotation.x
	bench.camera_rig.look_yaw = bench.camera_rig.camera.rotation.y
	for step in range(3): await process_frame
	await capture("air-blower-held")
	var view = bench.closeup
	view.show_view("service", bench.gpu)
	view.direction = Vector3(0, 1, 0.05).normalized()
	view.update_camera()
	await process_frame
	await capture("air-blower-focus-before")
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = view.surface.size * 0.5
	view.view_input(down)
	expect(dust.blowing, "Focus press did not start the air blower")
	# Air on the idle fan's rotor spins it; the dry bearing grinds.
	var station = bench.testing_station
	var blade: MeshInstance3D = bench.gpu.find_child("fan-blade-1", true, false)
	var blade_screen: Vector2 = view.camera.unproject_position(blade.global_transform * blade.get_aabb().get_center())
	var before: float = view.subject_cleaning_progress()
	await hold(view, blade_screen, 700)
	expect(station.fan_speed > 1.0 and not station.rotor.transform.is_equal_approx(station.rotor_home), "Air on the rotor did not spin the idle fan")
	expect(station.grind_audio.playing, "A dry bearing did not grind while the air spun it")
	expect(dust.motor.playing and dust.motor_level > 0.9 and dust.motor.bus == &"AirBlower", "Air blower motor did not wind up on its channel")
	expect(not bench.bearing.operate("hub-label") and bench.bearing.last_denial.contains("stop spinning"), "Bearing service ignored the spinning rotor")
	# A narrow jet: one spot cleans a little; a sweep cleans much more.
	var spot: float = view.subject_cleaning_progress()
	expect(spot > before and spot < before + 0.1, "Air jet on one spot was not narrow (%.3f -> %.3f)" % [before, spot])
	# Frames render between rows, so the cloud is mid-flight when captured halfway through.
	var rows := range(30, int(view.surface.size.y) - 30, 14)
	for row in range(rows.size()):
		for x in range(30, int(view.surface.size.x) - 30, 14):
			view.cleaning_pointer = Vector2(x, rows[row])
			view.clean_under_pointer(0.05)
		await process_frame
		if row == rows.size() / 2:
			expect(not dust.puffs.particles.is_empty() and dust.puffs.visible and view.puff_view.visible, "Lifted dust did not leave as a cloud")
			expect(dust.puffs.particles.size() <= dust.puffs.CAPACITY, "Dust cloud exceeded its pool")
			await capture("air-blower-focus-cleaning")
	expect(view.subject_cleaning_progress() > spot + 0.05, "Sweeping the air blower did not clean the card")
	down.pressed = false
	view.view_input(down)
	expect(not dust.blowing, "Release did not stop the air blower")
	await process_frame
	expect(dust.motor.playing, "Motor stopped dead instead of coasting down")
	expect(await wait_for(func(): return not dust.motor.playing, 2500), "Motor did not wind down after release")
	expect(await wait_for(func(): return dust.puffs.particles.is_empty() and not dust.puffs.visible, 3000), "Dust cloud did not settle")
	expect(await wait_for(func(): return station.fan_speed == 0.0, 6000), "Air-spun fan did not coast to a stop")
	await process_frame
	expect(station.rotor.transform.is_equal_approx(station.rotor_home) and not station.grind_audio.playing,
		"Coasted fan did not restore its rotor or stop grinding")
	await capture("air-blower-focus-cleaned")
	view.close()
	bench.queue_free()
	await process_frame
	# Let the audio server release the grind playback stopped moments ago.
	await create_timer(0.3).timeout
	print("PASS: dust deposition and thickness, air blower equip, narrow jet, sweep cleaning, dust cloud, motor wind-up/coast and air-spun fan grind" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
