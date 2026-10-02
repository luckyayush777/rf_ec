extends CanvasLayer
const AudioMix = preload("res://scripts/audio_mix.gd")
const RepairStatus = preload("res://scripts/repair_status.gd")
const DEBUG_SETTINGS := "user://bench_debug.cfg"
signal tool_selected(id: String)
signal tool_menu_closed
signal view_requested(view: String)
signal inspect_requested
signal flip_requested
signal toolbox_requested
signal equip_requested
signal dev_blower_requested
signal return_requested
signal cable_requested
signal assembly_requested(id: String)
signal assembly_refit_requested
signal assembly_store_requested
signal refit_started
signal refit_ended
signal mute_requested
signal highlight_dust_requested
signal test_requested
signal debug_clean_requested
signal debug_disassemble_requested
signal debug_reassemble_requested
signal debug_dry_paste_requested
signal debug_repaste_requested
signal debug_dry_bearing_requested
signal debug_oil_bearing_requested
signal debug_connector_requested

var inspect_button: Button
var flip_button: Button
var status_label: Label
var view_buttons: Array[Button] = []
var toolbox_button: Button
var equip_button: Button
var dev_blower_button: Button
var return_button: Button
var cable_button: Button
var fan_button: Button
var cooler_button: Button
var assembly_refit_button: Button
var assembly_store_button: Button
var refit_button: Button
var mute_button: Button
var service_label: Label
var turn_progress: ProgressBar
var clean_label: Label
var part_clean_label: Label
var remaining_label: Label
var highlight_dust_button: Button
var debug_clean_button: Button
var debug_disassemble_button: Button
var debug_reassemble_button: Button
var debug_dry_paste_button: Button
var debug_repaste_button: Button
var debug_dry_bearing_button: Button
var debug_oil_bearing_button: Button
var test_button: Button
var service_controls: HFlowContainer
var assembly_controls: HFlowContainer
var main_panel: PanelContainer
var cleaning_panel: PanelContainer
var reticle: Label
var interaction_hint: Label
var notice_label: Label
var fps_mode := false
var tool_overlay: ColorRect
var tool_buttons: Dictionary = {}
var tool_close_button: Button
var audio_panel: PanelContainer
var audio_sliders: Dictionary = {}
var audio_values: Dictionary = {}
var audio_saved_label: Label
var audio_save_timer: Timer
var repair_toggle: CheckButton
var repair_layer: CanvasLayer
var repair_panel: PanelContainer
var repair_summary: Label
var repair_rows: VBoxContainer

func _ready() -> void:
	var panel := PanelContainer.new()
	main_panel = panel
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 18
	panel.offset_top = 18
	panel.offset_right = -18
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var title := Label.new()
	title.text = "BENCH  /  GPU REPAIR"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)
	var controls := HFlowContainer.new()
	column.add_child(controls)
	for entry in [["Both desks", "both"], ["Repair", "repair"], ["Testing", "testing"], ["Top", "top"]]:
		var button := make_button(entry[0], controls)
		button.pressed.connect(func(): view_requested.emit(entry[1]))
		view_buttons.append(button)
	test_button = make_button("Connect GPU to test board", controls)
	test_button.pressed.connect(func(): test_requested.emit())
	inspect_button = make_button("Inspect GPU", controls)
	inspect_button.pressed.connect(func(): inspect_requested.emit())
	flip_button = make_button("Flip GPU", controls)
	flip_button.pressed.connect(func(): flip_requested.emit())
	service_controls = HFlowContainer.new()
	column.add_child(service_controls)
	toolbox_button = make_button("Open toolbox", service_controls)
	toolbox_button.pressed.connect(func(): toolbox_requested.emit())
	equip_button = make_button("Equip screwdriver", service_controls)
	equip_button.pressed.connect(func(): equip_requested.emit())
	dev_blower_button = make_button("Equip Dev blower", service_controls)
	dev_blower_button.pressed.connect(func(): dev_blower_requested.emit())
	return_button = make_button("Return screwdriver", service_controls)
	return_button.pressed.connect(func(): return_requested.emit())
	cable_button = make_button("Unplug cable", service_controls)
	cable_button.pressed.connect(func(): cable_requested.emit())
	refit_button = make_button("Hold to refit screw", service_controls)
	refit_button.button_down.connect(func(): refit_started.emit())
	refit_button.button_up.connect(func(): refit_ended.emit())
	assembly_controls = HFlowContainer.new()
	column.add_child(assembly_controls)
	fan_button = make_button("Lift fan", assembly_controls)
	fan_button.pressed.connect(func(): assembly_requested.emit("fan-assembly"))
	cooler_button = make_button("Lift heatsink", assembly_controls)
	cooler_button.pressed.connect(func(): assembly_requested.emit("cooler-assembly"))
	assembly_refit_button = make_button("Refit assembly", assembly_controls)
	assembly_refit_button.pressed.connect(func(): assembly_refit_requested.emit())
	assembly_store_button = make_button("Store assembly", assembly_controls)
	assembly_store_button.pressed.connect(func(): assembly_store_requested.emit())
	mute_button = make_button("Sound on", service_controls)
	mute_button.pressed.connect(func(): mute_requested.emit())
	service_label = Label.new()
	service_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(service_label)
	turn_progress = ProgressBar.new()
	turn_progress.custom_minimum_size.y = 12
	turn_progress.show_percentage = false
	column.add_child(turn_progress)
	cleaning_panel = PanelContainer.new()
	cleaning_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	cleaning_panel.offset_left = 18
	cleaning_panel.offset_right = 520
	cleaning_panel.offset_top = -250
	cleaning_panel.offset_bottom = -18
	add_child(cleaning_panel)
	var cleaning_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		cleaning_margin.add_theme_constant_override("margin_" + side, 8)
	cleaning_panel.add_child(cleaning_margin)
	var cleaning_column := VBoxContainer.new()
	cleaning_margin.add_child(cleaning_column)
	clean_label = Label.new()
	cleaning_column.add_child(clean_label)
	part_clean_label = Label.new()
	part_clean_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cleaning_column.add_child(part_clean_label)
	remaining_label = Label.new()
	remaining_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cleaning_column.add_child(remaining_label)
	highlight_dust_button = make_button("highlight dust", cleaning_column)
	highlight_dust_button.toggle_mode = true
	highlight_dust_button.visible = OS.is_debug_build()
	highlight_dust_button.pressed.connect(func(): highlight_dust_requested.emit())
	var debug_controls := HFlowContainer.new()
	cleaning_column.add_child(debug_controls)
	debug_clean_button = make_button("Debug: Clean GPU", debug_controls)
	debug_clean_button.visible = OS.is_debug_build()
	debug_clean_button.pressed.connect(func(): debug_clean_requested.emit())
	debug_disassemble_button = make_button("Debug: Disassemble GPU", debug_controls)
	debug_disassemble_button.visible = OS.is_debug_build()
	debug_disassemble_button.pressed.connect(func(): debug_disassemble_requested.emit())
	debug_reassemble_button = make_button("Debug: Reassemble GPU", debug_controls)
	debug_reassemble_button.visible = OS.is_debug_build()
	debug_reassemble_button.pressed.connect(func(): debug_reassemble_requested.emit())
	# Paste quality stays hidden from normal play; the thermal camera is the diagnosis.
	debug_dry_paste_button = make_button("Debug: Dry paste", debug_controls)
	debug_dry_paste_button.visible = OS.is_debug_build()
	debug_dry_paste_button.pressed.connect(func(): debug_dry_paste_requested.emit())
	debug_repaste_button = make_button("Debug: Fresh paste", debug_controls)
	debug_repaste_button.visible = OS.is_debug_build()
	debug_repaste_button.pressed.connect(func(): debug_repaste_requested.emit())
	debug_dry_bearing_button = make_button("Debug: Dry bearing", debug_controls)
	debug_dry_bearing_button.visible = OS.is_debug_build()
	debug_dry_bearing_button.pressed.connect(func(): debug_dry_bearing_requested.emit())
	debug_oil_bearing_button = make_button("Debug: Oil bearing", debug_controls)
	debug_oil_bearing_button.visible = OS.is_debug_build()
	debug_oil_bearing_button.pressed.connect(func(): debug_oil_bearing_requested.emit())
	# Cycles the edge connector: clean, oxidised, lifted finger, torn finger.
	var debug_connector_button := make_button("Debug: Edge connector", debug_controls)
	debug_connector_button.visible = OS.is_debug_build()
	debug_connector_button.pressed.connect(func(): debug_connector_requested.emit())
	repair_toggle = CheckButton.new()
	repair_toggle.text = "Repair status overlay"
	repair_toggle.focus_mode = Control.FOCUS_NONE
	repair_toggle.visible = OS.is_debug_build()
	debug_controls.add_child(repair_toggle)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text = "Loading workbench..."
	column.add_child(status_label)
	build_audio_panel()
	build_repair_panel()

## Escape-menu mixer: one slider per sound channel plus Master. Changes apply live and save shortly after.
func build_audio_panel() -> void:
	audio_panel = PanelContainer.new()
	audio_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	audio_panel.offset_left = -430
	audio_panel.offset_right = -18
	audio_panel.offset_top = 18
	audio_panel.hide()
	add_child(audio_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	audio_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	var title := Label.new()
	title.text = "SOUND MIX"
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)
	for channel in AudioMix.CHANNELS:
		var bus: StringName = channel[0]
		var row := HBoxContainer.new()
		column.add_child(row)
		var name_label := Label.new()
		name_label.text = channel[1]
		name_label.custom_minimum_size.x = 170
		row.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = AudioMix.MAX_LEVEL * 100
		slider.step = 5
		slider.custom_minimum_size.x = 150
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# Mouse only: keyboard focus would swallow Tab/Escape and movement keys.
		slider.focus_mode = Control.FOCUS_NONE
		row.add_child(slider)
		var value_label := Label.new()
		value_label.custom_minimum_size.x = 56
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)
		audio_sliders[bus] = slider
		audio_values[bus] = value_label
		slider.value_changed.connect(func(value: float):
			AudioMix.set_level(bus, value / 100.0)
			value_label.text = "%d%%" % roundi(value)
			audio_save_timer.start())
	var actions := HFlowContainer.new()
	column.add_child(actions)
	make_button("Reset all to 100%", actions).pressed.connect(func():
		AudioMix.reset()
		refresh_audio_panel()
		save_audio_mix())
	audio_saved_label = Label.new()
	audio_saved_label.add_theme_font_size_override("font_size", 13)
	audio_saved_label.modulate = Color(1, 1, 1, 0.7)
	audio_saved_label.text = "Levels save to " + AudioMix.save_location()
	column.add_child(audio_saved_label)
	audio_save_timer = Timer.new()
	audio_save_timer.one_shot = true
	audio_save_timer.wait_time = 0.4
	audio_save_timer.timeout.connect(save_audio_mix)
	add_child(audio_save_timer)
	refresh_audio_panel()

## Developer overlay: what is wrong with the card and how far each fix has got. Debug builds only;
## toggled from the Escape menu and remembered between runs. Its own layer keeps it above focus views.
func build_repair_panel() -> void:
	repair_layer = CanvasLayer.new()
	repair_layer.layer = 20
	add_child(repair_layer)
	repair_panel = PanelContainer.new()
	repair_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	repair_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	repair_panel.offset_left = -560
	repair_panel.offset_right = -18
	repair_panel.offset_top = 420
	repair_layer.add_child(repair_panel)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	repair_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	var title := Label.new()
	title.text = "REPAIR STATUS  (debug)"
	title.add_theme_font_size_override("font_size", 16)
	column.add_child(title)
	repair_summary = Label.new()
	repair_summary.add_theme_font_size_override("font_size", 13)
	column.add_child(repair_summary)
	repair_rows = VBoxContainer.new()
	repair_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(repair_rows)
	var settings := ConfigFile.new()
	var enabled: bool = OS.is_debug_build() and settings.load(DEBUG_SETTINGS) == OK and settings.get_value("overlay", "repair_status", false)
	repair_toggle.set_pressed_no_signal(enabled)
	repair_panel.visible = enabled
	repair_toggle.toggled.connect(func(value: bool):
		repair_panel.visible = value
		settings.set_value("overlay", "repair_status", value)
		settings.save(DEBUG_SETTINGS))

func refresh_repair_status(rows: Array[Dictionary]) -> void:
	while repair_rows.get_child_count() < rows.size():
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(swatch)
		var name_label := Label.new()
		name_label.custom_minimum_size.x = 125
		line.add_child(name_label)
		var detail := Label.new()
		detail.add_theme_font_size_override("font_size", 13)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.custom_minimum_size.x = 380
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(detail)
		repair_rows.add_child(line)
	var counts := {RepairStatus.FAULT: 0, RepairStatus.PARTIAL: 0, RepairStatus.DONE: 0}
	for index in range(rows.size()):
		var entry: Dictionary = rows[index]
		var line: HBoxContainer = repair_rows.get_child(index)
		(line.get_child(0) as ColorRect).color = RepairStatus.color(entry.state)
		(line.get_child(1) as Label).text = entry.label
		(line.get_child(2) as Label).text = entry.detail
		if counts.has(entry.state): counts[entry.state] += 1
	repair_summary.text = "%d broken · %d in progress · %d done" % [counts[RepairStatus.FAULT], counts[RepairStatus.PARTIAL], counts[RepairStatus.DONE]]

func refresh_audio_panel() -> void:
	for bus in audio_sliders:
		var percent := AudioMix.level(bus) * 100.0
		audio_sliders[bus].set_value_no_signal(percent)
		audio_values[bus].text = "%d%%" % roundi(percent)

func save_audio_mix() -> void:
	var error := AudioMix.save()
	audio_saved_label.text = ("Saved to " + AudioMix.save_location()) if error == OK else "Could not save levels (error %d)" % error

func make_button(text: String, parent: Control) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button

func enable_first_person() -> void:
	fps_mode = true
	main_panel.hide()
	cleaning_panel.hide()
	reticle = Label.new()
	reticle.text = "+"
	reticle.add_theme_color_override("font_outline_color", Color.BLACK)
	reticle.add_theme_constant_override("outline_size", 4)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(reticle)
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.offset_left = -6
	reticle.offset_top = -12
	interaction_hint = Label.new()
	interaction_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	interaction_hint.add_theme_constant_override("outline_size", 3)
	interaction_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	interaction_hint.offset_top = -100
	interaction_hint.offset_bottom = -20
	add_child(interaction_hint)
	notice_label = Label.new()
	notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_label.add_theme_color_override("font_outline_color", Color.BLACK)
	notice_label.add_theme_constant_override("outline_size", 3)
	notice_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	notice_label.offset_left = 24
	notice_label.offset_top = 18
	notice_label.offset_right = -24
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.text = "BENCH / REPAIR SHOP"
	add_child(notice_label)

func set_menu_open(value: bool) -> void:
	if not fps_mode: return
	cleaning_panel.visible = value and (tool_overlay == null or not tool_overlay.visible)
	var mixer_opening: bool = value and not audio_panel.visible and cleaning_panel.visible
	audio_panel.visible = cleaning_panel.visible
	if mixer_opening: refresh_audio_panel()
	reticle.visible = not value

func update_reticle(hit: Dictionary, tools: Node, inspection: Node, service: Node, captured: bool, seated: bool = false) -> void:
	if not fps_mode: return
	set_menu_open(not captured)
	var action: String = hit.get("action", "")
	var prompt := ""
	if seated: action = "seated"
	match action:
		"seated": prompt = "Hold LMB + move mouse: rock the card in its slot   |   E: remove GPU"
		"computer": prompt = "E / Click: use the shop computer"
		"delivery_box": prompt = "E / Click: open the box"
		"sealed_box": prompt = "Thermal camera, still sealed"
		"screw", "screw_hole": prompt = "E: pick up GPU  |  Click: focus" if tools.equipped_tool != "" else "Screwdriver required"
		"gpu": prompt = "E: pick up GPU  |  Click: focus" if tools.focus_tool() else "E: pick up / remove GPU"
		"test_board": prompt = "E: connect / remove GPU"
		"monitor_power": prompt = "E: monitor power"
		"toolbox": prompt = "E / Click: unroll tool bag"
		"screwdriver", "air-blower", "dev-blower", "thermal-camera", "spudger", "ipa-wipe", "paste-syringe", "fan-oiler", "loupe": prompt = "E: pick up " + action.replace("-", " ")
		"cable": prompt = "E: connect / disconnect fan cable"
		"assembly": prompt = "E: inspect GPU / lift loosened assembly"
		"desk":
			if tools.equipped_tool != "" or service.held_part != "" or inspection.held: prompt = "E: place on desk"
	# Q empties the tool hand first; only then does it return or refit the held part.
	if inspection.held or service.held_part != "": prompt += "   |   RMB + mouse: rotate   F: flip   R: focus"
	if tools.equipped_tool != "": prompt += "   |   Q: return tool"
	elif inspection.held or service.held_part != "": prompt += "   |   Q: return/refit"
	if tools.equipped_tool == "thermal-camera": prompt += "   |   Hold RMB: thermal view"
	interaction_hint.text = (prompt + "\nWASD: move   Mouse: look   E: interact   Tab/Esc: release mouse") if captured else "Mouse released — Tab/Esc to resume"

## At the shop computer the cursor works the screen; the pause menu, reticle and hints stay
## away (the portal's own footer says how to step away).
func set_computer_mode(active: bool) -> void:
	if not fps_mode: return
	set_menu_open(false)
	reticle.visible = not active
	interaction_hint.text = ""

func set_status(text: String) -> void:
	status_label.text = text
	if notice_label != null: notice_label.text = text

func set_testing_mode(value: bool) -> void:
	service_controls.visible = not value
	assembly_controls.visible = not value
	service_label.visible = not value
	turn_progress.visible = not value

func refresh(held: bool, moving: bool, tools: Node, service: Node, cleaning: Node, station: Node) -> void:
	var busy: bool = moving or tools.busy or service.busy or station.moving
	test_button.text = "Remove GPU from test board" if station.installed else "Connect GPU to test board"
	test_button.disabled = busy or held or service.held_part != "" or tools.equipped_tool != ""
	inspect_button.text = "Set GPU down" if held else "Inspect GPU"
	inspect_button.disabled = busy or station.installed
	flip_button.visible = held
	flip_button.disabled = busy or station.installed
	for button in view_buttons:
		button.disabled = held or busy
	toolbox_button.text = "Close toolbox" if tools.open else "Open toolbox"
	toolbox_button.disabled = busy or station.installed
	equip_button.visible = tools.equipped_tool == ""
	equip_button.disabled = busy or station.installed
	dev_blower_button.visible = OS.is_debug_build() and tools.equipped_tool == ""
	dev_blower_button.disabled = busy or station.installed
	return_button.visible = tools.equipped_tool != ""
	return_button.text = "Return " + tools.NAMES.get(tools.equipped_tool, "screwdriver")
	return_button.disabled = busy or station.installed
	cable_button.text = "Reconnect cable" if not service.cable_connected else "Unplug cable"
	cable_button.disabled = busy or station.installed or tools.equipped_tool != ""
	# A held refit button stays enabled until release so it still emits button_up.
	refit_button.visible = not service.removed.is_empty() or refit_button.button_pressed
	refit_button.disabled = station.installed or (busy and service.active_screw == "") or tools.equipped_tool != "screwdriver"
	fan_button.text = "Pick up fan" if "fan-assembly" in service.removed else "Lift fan"
	cooler_button.text = "Pick up heatsink" if "cooler-assembly" in service.removed else "Lift heatsink"
	fan_button.disabled = busy or station.installed or service.held_part != "" or tools.equipped_tool != ""
	cooler_button.disabled = fan_button.disabled
	assembly_refit_button.visible = service.held_part != "" or "fan-assembly" in service.removed or "cooler-assembly" in service.removed
	assembly_refit_button.disabled = busy or station.installed or tools.equipped_tool != ""
	assembly_store_button.visible = service.held_part != ""
	assembly_store_button.disabled = busy or station.installed
	debug_disassemble_button.disabled = busy or held or station.installed
	debug_reassemble_button.disabled = busy or held or station.installed or (service.removed.is_empty() and service.cable_connected and service.turns.is_empty())
	mute_button.text = "Sound off" if service.muted else "Sound on"
	var fan_count := 0
	var cooler_count := 0
	for id in service.removed:
		if id in service.fan_screws: fan_count += 1
		if id in service.cooler_screws: cooler_count += 1
	service_label.text = "Equipped: %s  |  Cable: %s  |  Fan screws: %d/%d out  |  Cooler screws: %d/%d out  |  Fan: %s  |  Heatsink: %s" % [
		tools.equipped_tool if tools.equipped_tool != "" else "empty hands", "connected" if service.cable_connected else "unplugged",
		fan_count, service.fan_screws.size(), cooler_count, service.cooler_screws.size(),
		"off" if "fan-assembly" in service.removed else "mounted", "off" if "cooler-assembly" in service.removed else "mounted"]
	turn_progress.visible = service.active_screw != ""
	if turn_progress.visible:
		turn_progress.value = service.turns[service.active_screw].progress * 100
	refresh_cleaning(cleaning)

func refresh_bearing(bearing: Node) -> void:
	debug_dry_bearing_button.disabled = bearing.dry and bearing.opened.is_empty() and not bearing.shaft_clean
	debug_oil_bearing_button.disabled = not bearing.dry

func refresh_paste(paste: Node) -> void:
	debug_dry_paste_button.disabled = paste.dried
	debug_repaste_button.disabled = paste.is_fresh() and not paste.dried

func refresh_cleaning(cleaning: Node) -> void:
	highlight_dust_button.set_pressed_no_signal(cleaning.highlighted)
	highlight_dust_button.disabled = cleaning.celebrated
	debug_clean_button.disabled = cleaning.celebrated
	var percent: int = floori(cleaning.progress * 100.0)
	clean_label.text = "Dust cleaning: %d%%" % percent
	part_clean_label.text = "PCB %d%%  |  Fan %d%%  |  Heatsink %d%%" % [
		floori(cleaning.part_progress("board") * 100.0),
		floori(cleaning.part_progress("fan-assembly") * 100.0),
		floori(cleaning.part_progress("cooler-assembly") * 100.0)]
	if cleaning.highlighted:
		remaining_label.text = "Remaining dust highlighted through parts. " + cleaning.remaining_hint()
	elif cleaning.target_part == "":
		remaining_label.text = cleaning.remaining_hint()
	else:
		remaining_label.text = "Cleaning %s: %d%%" % [String(cleaning.target_part).replace("-assembly", "").capitalize(),
			floori(cleaning.part_progress(cleaning.target_part) * 100.0)]

func refresh_tool_menu(tools: Node, service: Node, selecting: bool) -> void:
	if tool_overlay == null or not tool_overlay.visible: return
	for id in tool_buttons:
		var button: Button = tool_buttons[id]
		button.text = button.get_meta("label") + ("  [Equipped]" if tools.equipped_tool == id else "")
		button.disabled = selecting or tools.busy or service.busy
	tool_close_button.disabled = selecting

func hide_tool_menu() -> void:
	if tool_overlay != null: tool_overlay.hide()
	set_menu_open(false)
