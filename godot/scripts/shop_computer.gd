extends Node3D
## The shop PC: a beige 486 cabinet, a deep mono-VGA CRT, a clacky keyboard and a ball mouse.
## Its tube shows the internal repair portal, a native Control page in a SubViewport drawn as
## green phosphor through crt_screen.gdshader. Using it eases the camera square onto the tube
## and frees the cursor; mouse events are cast onto the screen plane, bent through the same
## glass curvature as the shader, and pushed into the page. F1-F3 switch pages; Esc or Tab
## steps away.
signal used(active: bool)

const UI = preload("res://scripts/screen_ui.gd")
const CRT = preload("res://shaders/crt_screen.gdshader")
const AudioMix = preload("res://scripts/audio_mix.gd")
## Recorded keystrokes (unicaegames, CC0) and mouse buttons (Kenney, CC0); see ASSET_CREDITS.md.
const KEY_SOUNDS := 12
const KEY_SOUND_PATH := "res://assets/sounds/pc/keypress-%03d.wav"
## Sitting down types a quick login-like burst of keys, this many with gaps in this range.
const LOGIN_KEYS := 5
const KEY_GAP := Vector2(0.06, 0.13)
## A 4:3 tube; low resolution keeps the type chunky.
const PAGE_SIZE := Vector2i(800, 600)
## Glass bulge shared with crt_screen.gdshader: corners curve out of view.
const CURVATURE := 0.08
const USE_TIME := 0.35
## Share of the view height the tube fills while in use; the beige bezel stays in view.
const SCREEN_FILL := 0.8
const BG := Color("#030a05")
const PHOSPHOR := Color("#46f27e")
const BRIGHT := Color("#c6ffd8")
const DIM := Color("#23824a")
const FAINT := Color("#0e3a1e")
const PAGE_KEYS := {KEY_F1: "board", KEY_F2: "bench", KEY_F3: "ledger"}

@onready var screen: MeshInstance3D = $Screen
var viewport: SubViewport
var bench: Node3D
var jobs: Node
var in_use := false
var motion: Tween
var tab := "board"
var mono: Font
var mono_bold: Font
var credit_label: Label
var tab_buttons: Dictionary = {}
var content: VBoxContainer
var prompt_label: Label
var hidden_tool: Node3D
var blink := 0.0
var led_on := {}
var led_off: StandardMaterial3D
var disk_time := 0.0
var floppy_time := 0.0
var keys_audio: AudioStreamPlayer
var mouse_down_audio: AudioStreamPlayer
var mouse_up_audio: AudioStreamPlayer
var typing: Tween
## Counted for tests: every keystroke and mouse button the PC has sounded.
var keystrokes := 0
var mouse_clicks := 0

func _ready() -> void:
	for node in [screen, $Housing, $Keyboard, $Cabinet]:
		node.set_meta("action", "computer")
	mono = UI.mono_font()
	mono_bold = UI.mono_font(true)
	viewport = UI.attach_viewport(screen, PAGE_SIZE, CRT)
	(screen.material_override as ShaderMaterial).set_shader_parameter("curvature", CURVATURE)
	build_page()
	build_hardware()
	build_sounds()

func configure(world: Node3D, repair_jobs: Node) -> void:
	bench = world
	jobs = repair_jobs
	# Deferred: a page button's own click can change the jobs, and its page is rebuilt.
	jobs.changed.connect(func(): refresh.call_deferred())
	refresh()

# --- Keyboard and mouse sounds ------------------------------------------------------------

func build_sounds() -> void:
	# Each keystroke is a different recorded key, slightly re-pitched, overlapping when fast.
	var keys := AudioStreamRandomizer.new()
	for index in range(1, KEY_SOUNDS + 1):
		keys.add_stream(-1, load(KEY_SOUND_PATH % index))
	keys.random_pitch = 1.06
	keys.random_volume_offset_db = 2.0
	keys_audio = make_player("KeyboardClack", keys, -3.0)
	keys_audio.max_polyphony = 4
	mouse_down_audio = make_player("MouseClick", load("res://assets/sounds/pc/mouse_click.wav"), -6.0)
	mouse_up_audio = make_player("MouseRelease", load("res://assets/sounds/pc/mouse_release.wav"), -8.0)

func make_player(player_name: String, sound: AudioStream, trim_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = sound
	player.volume_db = trim_db
	player.set_meta("trim_db", trim_db)
	player.bus = AudioMix.PC_INPUT
	add_child(player)
	return player

func set_muted(value: bool) -> void:
	for player in [keys_audio, mouse_down_audio, mouse_up_audio]:
		player.volume_db = -80.0 if value else float(player.get_meta("trim_db"))

func clack() -> void:
	keystrokes += 1
	keys_audio.play()

## A short run of keys at an uneven human pace.
func type_burst(count: int) -> void:
	if typing != null: typing.kill()
	typing = create_tween()
	for index in range(count):
		typing.tween_callback(clack)
		typing.tween_interval(randf_range(KEY_GAP.x, KEY_GAP.y))

func mouse_button(pressed: bool) -> void:
	if pressed:
		mouse_clicks += 1
		mouse_down_audio.play()
	else:
		mouse_up_audio.play()

# --- Hardware details -------------------------------------------------------------------

func build_hardware() -> void:
	led_off = StandardMaterial3D.new()
	led_off.albedo_color = Color(0.12, 0.13, 0.12)
	for entry in [["green", Color(0.3, 1.0, 0.4)], ["amber", Color(1.0, 0.62, 0.12)]]:
		var lit := StandardMaterial3D.new()
		lit.albedo_color = entry[1]
		lit.emission_enabled = true
		lit.emission = entry[1]
		lit.emission_energy_multiplier = 1.6
		led_on[entry[0]] = lit
	$MonitorLED.material_override = led_on.green
	$PowerLight.material_override = led_on.green
	$DiskLight.material_override = led_off
	$FloppyLED.material_override = led_off
	var slot := StandardMaterial3D.new()
	slot.albedo_color = Color(0.06, 0.06, 0.06)
	# Cooling slots across the tube's shell and under the cabinet's power button.
	for index in range(7):
		add_box(self, Vector3(1.9, 0.012, 0.045), Vector3(0, 6.977, -0.16 - index * 0.085), slot)
	for index in range(5):
		add_box(self, Vector3(0.62, 0.022, 0.012), Vector3(2.45, 4.32 + index * 0.05, 0.506), slot)
	build_keys()
	var cord := StandardMaterial3D.new()
	cord.albedo_color = Color(0.5, 0.48, 0.43)
	cord.roughness = 0.7
	add_cord([Vector3(0.75, 4.3, 0.17), Vector3(0.95, 4.23, -0.05), Vector3(1.6, 4.23, -0.25), Vector3(1.95, 4.3, -1.3)], cord)
	add_cord([Vector3(1.48, 4.27, 0.67), Vector3(1.42, 4.225, 0.4), Vector3(1.6, 4.225, 0.1), Vector3(1.95, 4.26, -1.1)], cord)

func add_box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	parent.add_child(node)
	return node

## A full-travel board in the old layout: function row, main block and numeric pad, drawn as
## one MultiMesh of keycaps on the keyboard case.
func build_keys() -> void:
	var u := 0.105
	var caps: Array = []
	var x0 := -1.27
	var rows := [
		[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -2],
		[-1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.5],
		[-1.75, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -2.25],
		[-2.25, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -2.75],
		[-1.5, 0, -1.5, 7, -1.5, 0, -1.5]]
	# Escape and three groups of four function keys along the back.
	var gaps := {1: 0.5, 5: 0.25, 9: 0.25}
	var x := x0
	for index in range(13):
		x += gaps.get(index, 0.0) * u
		caps.append([x + u * 0.5, -0.36, u, true])
		x += u
	for row in range(rows.size()):
		x = x0
		var z := -0.21 + row * u
		for width in rows[row]:
			# Negative widths are the grey modifier keys; zero is an empty space.
			var span: float = absf(width) if width != 0 else 1.0
			if width != 0: caps.append([x + span * u * 0.5, z, span * u, width < 0])
			x += span * u
	var pad := x0 + 15.0 * u + 0.12
	for row in range(5):
		for column in range(4):
			caps.append([pad + (column + 0.5) * u, -0.21 + row * u, u, column == 3 or row == 0])
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	var cap := BoxMesh.new()
	cap.size = Vector3.ONE
	var plastic := StandardMaterial3D.new()
	plastic.vertex_color_use_as_albedo = true
	plastic.roughness = 0.6
	cap.material = plastic
	multimesh.mesh = cap
	multimesh.instance_count = caps.size()
	for index in range(caps.size()):
		var entry: Array = caps[index]
		var size := Vector3(entry[2] - 0.016, 0.055, u - 0.016)
		multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(size), Vector3(entry[0], 0.09, entry[1])))
		multimesh.set_instance_color(index, Color(0.58, 0.56, 0.51) if entry[3] else Color(0.86, 0.83, 0.74))
	var keys := MultiMeshInstance3D.new()
	keys.name = "Keycaps"
	keys.multimesh = multimesh
	$Keyboard.add_child(keys)

## A coiled-flat cord laid along the desk through the given points.
func add_cord(points: Array, material: Material) -> void:
	for index in range(points.size() - 1):
		var start: Vector3 = points[index]
		var finish: Vector3 = points[index + 1]
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.018
		mesh.bottom_radius = 0.018
		mesh.height = start.distance_to(finish)
		mesh.radial_segments = 8
		mesh.material = material
		var segment := MeshInstance3D.new()
		segment.mesh = mesh
		add_child(segment)
		segment.position = (start + finish) * 0.5
		segment.basis = Basis(Quaternion(Vector3.UP, (finish - start).normalized()))

func _process(delta: float) -> void:
	blink += delta
	if prompt_label != null:
		prompt_label.text = "C:\\BENCH\\JOBS>" + ("_" if fmod(blink, 1.06) < 0.53 else " ")
	# The hard disk chatters, busier while someone is at the keyboard.
	disk_time -= delta
	if disk_time <= 0.0:
		disk_time = randf_range(0.04, 0.12)
		$DiskLight.material_override = led_on.amber if randf() < (0.35 if in_use else 0.05) else led_off
	if floppy_time > 0.0:
		floppy_time -= delta
		if floppy_time <= 0.0: $FloppyLED.material_override = led_off

# --- Portal page --------------------------------------------------------------------------

func text(value: String, size: int, color: Color = PHOSPHOR, bold: bool = false) -> Label:
	var item := UI.label(value, size, color)
	item.add_theme_font_override("font", mono_bold if bold else mono)
	return item

func frame(fill: Color, border: Color, h: int = 10, v: int = 6) -> StyleBoxFlat:
	var box := UI.flat(fill, 0, border)
	box.content_margin_left = h
	box.content_margin_right = h
	box.content_margin_top = v
	box.content_margin_bottom = v
	return box

## Inverse video on hover, the way terminal menus highlight.
func term_button(label: String, size: int = 17) -> Button:
	var item := Button.new()
	item.text = label
	item.focus_mode = Control.FOCUS_NONE
	item.add_theme_font_override("font", mono_bold)
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_stylebox_override("normal", frame(BG, PHOSPHOR))
	item.add_theme_stylebox_override("hover", frame(PHOSPHOR, PHOSPHOR))
	item.add_theme_stylebox_override("pressed", frame(BRIGHT, BRIGHT))
	item.add_theme_stylebox_override("disabled", frame(BG, FAINT))
	item.add_theme_color_override("font_color", PHOSPHOR)
	item.add_theme_color_override("font_hover_color", BG)
	item.add_theme_color_override("font_pressed_color", BG)
	item.add_theme_color_override("font_disabled_color", DIM)
	return item

func rule(parent: Control, color: Color = PHOSPHOR, double: bool = false) -> void:
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 2)
	parent.add_child(lines)
	for index in range(2 if double else 1):
		var line := ColorRect.new()
		line.color = color
		line.custom_minimum_size.y = 2
		lines.add_child(line)

func build_page() -> void:
	var root := Panel.new()
	root.size = PAGE_SIZE
	root.add_theme_stylebox_override("panel", UI.flat(BG))
	viewport.add_child(root)
	var margin := MarginContainer.new()
	margin.size = PAGE_SIZE
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 34)
	for side in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 26)
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	header.add_child(text("BENCHWORKS REPAIR-NET", 24, BRIGHT, true))
	var version := text(" v2.1", 16, DIM)
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	version.size_flags_vertical = Control.SIZE_SHRINK_END
	header.add_child(version)
	var credit := PanelContainer.new()
	credit.add_theme_stylebox_override("panel", frame(PHOSPHOR, PHOSPHOR, 10, 2))
	header.add_child(credit)
	credit_label = text("", 20, BG, true)
	credit.add_child(credit_label)
	rule(column, PHOSPHOR, true)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 10)
	column.add_child(tab_row)
	for entry in [["board", "F1 JOB BOARD"], ["bench", "F2 MY BENCH"], ["ledger", "F3 LEDGER"]]:
		var button := term_button(entry[1])
		var id: String = entry[0]
		button.pressed.connect(func(): show_tab(id))
		tab_row.add_child(button)
		tab_buttons[id] = button
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	column.add_child(content)
	rule(column, DIM)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	prompt_label = text("C:\\BENCH\\JOBS>_", 16)
	prompt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(prompt_label)
	footer.add_child(text("ESC LEAVE   F1-F3 PAGES", 15, DIM))

func show_tab(id: String) -> void:
	tab = id
	floppy_time = 0.45
	$FloppyLED.material_override = led_on.green
	# Rebuild after the click finishes; the pressed button is replaced.
	refresh.call_deferred()

func refresh() -> void:
	if jobs == null or content == null: return
	credit_label.text = "CREDIT $%d" % jobs.balance
	tab_buttons.bench.text = "F2 MY BENCH %d/%d" % [jobs.queue.size(), jobs.MAX_QUEUE]
	for id in tab_buttons:
		var selected: bool = id == tab
		tab_buttons[id].add_theme_stylebox_override("normal", frame(PHOSPHOR if selected else BG, PHOSPHOR if selected else DIM))
		tab_buttons[id].add_theme_color_override("font_color", BG if selected else PHOSPHOR)
	UI.clear(content)
	match tab:
		"board": build_board()
		"bench": build_bench()
		"ledger": build_ledger()

func card(border: Color = DIM) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", frame(BG, border, 12, 8))
	content.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	panel.add_child(inner)
	return inner

func wrapped(value: String, size: int, width: float, color: Color = PHOSPHOR) -> Label:
	var item := text(value, size, color)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.custom_minimum_size.x = width
	return item

func build_board() -> void:
	content.add_child(text("OPEN REPAIR REQUESTS", 20, BRIGHT, true))
	content.add_child(text("BENCH HOLDS %d CARD - ACCEPTED CARDS ARRIVE BOXED AT THE REPAIR DESK" % jobs.MAX_QUEUE, 13, DIM))
	for offer in jobs.offers:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card().add_child(row)
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(details)
		details.add_child(text("#%d  %s  %s" % [offer.id, offer.customer.to_upper(), offer.model.to_upper()], 14, DIM))
		details.add_child(wrapped("> " + offer.complaint, 15, 520))
		var side := VBoxContainer.new()
		side.custom_minimum_size.x = 150
		side.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(side)
		var pay := text("$%d" % offer.pay, 26, BRIGHT, true)
		pay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		side.add_child(pay)
		var accept := term_button("BENCH FULL" if jobs.bench_full() else "ACCEPT", 16)
		accept.disabled = jobs.bench_full()
		accept.name = "Accept%d" % offer.id
		var id: int = offer.id
		accept.pressed.connect(func():
			if jobs.accept(id): tab = "bench")
		side.add_child(accept)

func build_bench() -> void:
	content.add_child(text("MY BENCH", 20, BRIGHT, true))
	if not jobs.last_result.is_empty():
		var result: Dictionary = jobs.last_result
		var banner := card(BRIGHT if result.paid else PHOSPHOR)
		banner.add_child(text(("** JOB #%d RETURNED TO %s - PAID $%d **" if result.paid else "!! JOB #%d RETURNED TO %s - NO PAYMENT !!") %
			([result.id, result.customer.to_upper(), result.amount] if result.paid else [result.id, result.customer.to_upper()]), 16, BRIGHT, true))
		banner.add_child(wrapped("> " + result.feedback, 15, 700))
	var job: Dictionary = jobs.active()
	if job.is_empty():
		content.add_child(text("BENCH EMPTY. ACCEPT A REQUEST ON THE JOB BOARD.", 16))
		var browse := term_button("F1 JOB BOARD", 16)
		browse.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		browse.pressed.connect(func(): show_tab("board"))
		content.add_child(browse)
		return
	var info := card()
	info.add_child(text("#%d  %s  %s" % [job.id, job.customer.to_upper(), job.model.to_upper()], 14, DIM))
	info.add_child(text("STATUS: IN THE BOX - OPEN IT ON THE REPAIR DESK" if job.state == "boxed" else "STATUS: ON THE BENCH - DIAGNOSE AND REPAIR", 16, BRIGHT, true))
	info.add_child(wrapped("CUSTOMER SAYS: \"%s\"" % job.complaint, 15, 700))
	info.add_child(text("PAYS $%d WHEN THE CARD COMES BACK WORKING" % job.pay, 14, DIM))
	var send := term_button("RETURN CARD TO CUSTOMER", 17)
	send.name = "ReturnCard"
	send.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	send.disabled = job.state != "bench" or jobs.busy
	send.pressed.connect(func(): jobs.return_card())
	content.add_child(send)
	content.add_child(wrapped("!! " + jobs.last_refusal.to_upper() if jobs.last_refusal != "" else
		"REASSEMBLE IT, RECONNECT THE FAN CABLE AND SET IT DOWN FIRST. THE CUSTOMER PAYS ONLY IF EVERY PROBLEM IS GONE.",
		14, 700, BRIGHT if jobs.last_refusal != "" else DIM))

func build_ledger() -> void:
	content.add_child(text("LEDGER", 20, BRIGHT, true))
	content.add_child(text("BALANCE  $%d" % jobs.balance, 22, BRIGHT, true))
	if jobs.ledger.is_empty():
		content.add_child(text("NO RETURNED JOBS YET.", 16, DIM))
		return
	content.add_child(ledger_row(["JOB", "CUSTOMER", "RESULT", "AMOUNT"], DIM))
	rule(content, FAINT)
	for entry in jobs.ledger.slice(0, 10):
		content.add_child(ledger_row(["#%d" % entry.id, entry.customer.to_upper(), "FIXED" if entry.paid else "UNFIXED",
			"+$%d" % entry.amount], PHOSPHOR if entry.paid else DIM))

func ledger_row(cells: Array, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	for index in range(cells.size()):
		var cell := text(cells[index], 16, color)
		cell.custom_minimum_size.x = [110, 260, 200, 120][index]
		row.add_child(cell)
	return row

# --- Sitting at the computer ---------------------------------------------------------------

## Sits down at the screen: the camera eases square onto it and the cursor is freed.
func use() -> void:
	if in_use: return
	in_use = true
	var rig: Node = bench.camera_rig
	rig.set_captured(false)
	var normal := screen.global_basis.y.normalized()
	var size: Vector2 = (screen.mesh as PlaneMesh).size
	var distance := size.y * 0.5 / tan(deg_to_rad(rig.camera.fov * 0.5)) / SCREEN_FILL
	rig.anchor = Transform3D(Basis.looking_at(-normal, Vector3.UP), screen.global_position + normal * distance)
	# A held tool would sit across the screen; it is put out of view until stepping away.
	var tool: String = bench.tools.equipped_tool
	hidden_tool = bench.tools.tool_node(tool) if tool != "" else null
	if hidden_tool != null: hidden_tool.visible = false
	blend_to(1.0)
	refresh()
	type_burst(LOGIN_KEYS)
	used.emit(true)

func leave() -> void:
	if not in_use: return
	in_use = false
	if typing != null: typing.kill()
	clack()
	push_pointer(Vector2(-1, -1), InputEventMouseMotion.new())
	if hidden_tool != null: hidden_tool.visible = true
	hidden_tool = null
	bench.camera_rig.set_captured(true)
	blend_to(0.0)
	used.emit(false)

func blend_to(weight: float) -> void:
	if motion != null: motion.kill()
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	motion.tween_property(bench.camera_rig, "anchor_weight", weight, USE_TIME)

## Routes input while in use. Mouse events land on the page where the ray meets the tube.
func handle_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_ESCAPE, KEY_TAB]: leave()
		elif PAGE_KEYS.has(event.physical_keycode):
			clack()
			show_tab(PAGE_KEYS[event.physical_keycode])
	elif event is InputEventMouse:
		if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			mouse_button(event.pressed)
		push_pointer(page_point(event.position), event)

## Screen UV to page UV through the glass bulge; identical to crt_screen.gdshader.
static func tube_to_page(uv: Vector2) -> Vector2:
	var p := uv * 2.0 - Vector2.ONE
	p *= (1.0 + CURVATURE * p.length_squared()) / (1.0 + CURVATURE)
	return p * 0.5 + Vector2(0.5, 0.5)

## Inverse of tube_to_page: solves the radial cubic with a few Newton steps.
static func page_to_tube(uv: Vector2) -> Vector2:
	var target := uv * 2.0 - Vector2.ONE
	var length := target.length()
	if length < 0.000001: return uv
	var goal := length * (1.0 + CURVATURE)
	var r := length
	for step in range(8):
		r -= (CURVATURE * r * r * r + r - goal) / (3.0 * CURVATURE * r * r + 1.0)
	return target / length * r * 0.5 + Vector2(0.5, 0.5)

## Page pixel under a viewport position, or (-1, -1) off the visible page.
func page_point(pointer: Vector2) -> Vector2:
	var camera: Camera3D = bench.camera_rig.camera
	var inverse := screen.global_transform.affine_inverse()
	var origin := inverse * camera.project_ray_origin(pointer)
	var direction := inverse.basis * camera.project_ray_normal(pointer)
	if absf(direction.y) < 0.00001: return Vector2(-1, -1)
	var t := -origin.y / direction.y
	if t < 0.0: return Vector2(-1, -1)
	var hit := origin + direction * t
	var size: Vector2 = (screen.mesh as PlaneMesh).size
	var uv := tube_to_page(Vector2(hit.x / size.x + 0.5, hit.z / size.y + 0.5))
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0: return Vector2(-1, -1)
	return uv * Vector2(PAGE_SIZE)

## The world point where a page pixel appears on the tube, for aiming at the page from the room.
func world_point(page: Vector2) -> Vector3:
	var size: Vector2 = (screen.mesh as PlaneMesh).size
	var uv := page_to_tube(page / Vector2(PAGE_SIZE))
	return screen.to_global(Vector3((uv.x - 0.5) * size.x, 0, (uv.y - 0.5) * size.y))

func push_pointer(point: Vector2, event: InputEvent) -> void:
	var local: InputEventMouse = event.duplicate()
	local.position = point
	local.global_position = point
	viewport.push_input(local, true)
