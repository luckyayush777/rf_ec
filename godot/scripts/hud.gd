extends CanvasLayer
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

func _ready() -> void:
	var panel := PanelContainer.new()
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
	inspect_button = make_button("Inspect GPU", controls)
	inspect_button.pressed.connect(func(): inspect_requested.emit())
	flip_button = make_button("Flip GPU", controls)
	flip_button.pressed.connect(func(): flip_requested.emit())
	var service_controls := HFlowContainer.new()
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
	var assembly_controls := HFlowContainer.new()
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
	var cleaning_panel := PanelContainer.new()
	cleaning_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	cleaning_panel.offset_left = 18
	cleaning_panel.offset_right = 520
	cleaning_panel.offset_top = -158
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
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text = "Loading workbench..."
	column.add_child(status_label)

func make_button(text: String, parent: Control) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button

func set_status(text: String) -> void:
	status_label.text = text

func refresh(held: bool, moving: bool, tools: Node, service: Node, cleaning: Node) -> void:
	var busy: bool = moving or tools.busy or service.busy
	inspect_button.text = "Set GPU down" if held else "Inspect GPU"
	inspect_button.disabled = busy
	flip_button.visible = held
	flip_button.disabled = busy
	for button in view_buttons:
		button.disabled = held or busy
	toolbox_button.text = "Close toolbox" if tools.open else "Open toolbox"
	toolbox_button.disabled = busy
	equip_button.visible = tools.equipped_tool == ""
	equip_button.disabled = busy
	dev_blower_button.visible = OS.is_debug_build() and tools.equipped_tool == ""
	dev_blower_button.disabled = busy
	return_button.visible = tools.equipped_tool != ""
	return_button.text = "Return Dev blower" if tools.equipped_tool == "dev-blower" else "Return screwdriver"
	return_button.disabled = busy
	cable_button.text = "Reconnect cable" if not service.cable_connected else "Unplug cable"
	cable_button.disabled = busy or tools.equipped_tool != ""
	# A held refit button stays enabled until release so it still emits button_up.
	refit_button.visible = not service.removed.is_empty() or refit_button.button_pressed
	refit_button.disabled = (busy and service.active_screw == "") or tools.equipped_tool != "screwdriver"
	fan_button.text = "Pick up fan" if "fan-assembly" in service.removed else "Lift fan"
	cooler_button.text = "Pick up heatsink" if "cooler-assembly" in service.removed else "Lift heatsink"
	fan_button.disabled = busy or service.held_part != "" or tools.equipped_tool != ""
	cooler_button.disabled = fan_button.disabled
	assembly_refit_button.visible = service.held_part != "" or "fan-assembly" in service.removed or "cooler-assembly" in service.removed
	assembly_refit_button.disabled = busy or tools.equipped_tool != ""
	assembly_store_button.visible = service.held_part != ""
	assembly_store_button.disabled = busy
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

func refresh_cleaning(cleaning: Node) -> void:
	highlight_dust_button.set_pressed_no_signal(cleaning.highlighted)
	highlight_dust_button.disabled = cleaning.celebrated
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
