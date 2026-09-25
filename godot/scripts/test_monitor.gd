extends Node3D
## A deterministic falling-block test feed. Its presentation cadence simulates GPU performance.

signal changed
signal notice(text: String)

const BOARD_WIDTH := 10
const BOARD_HEIGHT := 16
const CELL_PIXELS := 6
const IMAGE_WIDTH := 180
const IMAGE_HEIGHT := 108
const BOARD_LEFT := 60
const BOARD_TOP := 6
const SHAPES := [
	[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)], # I
	[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)], # O
	[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)], # T
	[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)], # S
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)], # Z
	[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)], # J
	[Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]  # L
]
const START_STACK := [
	[0, 0, 0, 0, 0, 0, 7, 0, 0, 0],
	[0, 0, 0, 3, 0, 0, 7, 0, 0, 0],
	[0, 2, 2, 3, 0, 0, 4, 0, 6, 6],
	[1, 1, 2, 2, 0, 0, 4, 6, 6, 7]
]

@onready var screen: MeshInstance3D = $Screen
@onready var button: MeshInstance3D = $PowerButton
@onready var led: MeshInstance3D = $PowerLED
@onready var readout: Label3D = $Readout
@onready var fps_readout: Label3D = $FpsReadout
@onready var stats: Label3D = $Stats
@onready var next_label: Label3D = $NextLabel
@onready var power_audio: AudioStreamPlayer = $PowerOnSound

var powered := false
var connected := false
var cleanliness := 0.0
var simulated_fps := 8
var presented_frames := 0
var frame_time := 0.0
var fall_fraction := 0.0
var steer_time := 0.0
var score := 0
var lines_cleared := 0
var board := PackedInt32Array()
var piece_kind := 1
var next_kind := 1
var piece_cells: Array[Vector2i] = []
var piece_x := 3
var piece_y := -2
var target_x := 3
var opening_piece := true
var rng := RandomNumberGenerator.new()
var image: Image
var texture: ImageTexture
var led_material: StandardMaterial3D

func _ready() -> void:
	button.set_meta("action", "monitor_power")
	image = Image.create(IMAGE_WIDTH, IMAGE_HEIGHT, false, Image.FORMAT_RGB8)
	image.fill(Color(0.075, 0.09, 0.105))
	texture = ImageTexture.create_from_image(image)
	var material: StandardMaterial3D = screen.mesh.surface_get_material(0).duplicate()
	material.albedo_texture = texture
	screen.material_override = material
	led_material = StandardMaterial3D.new()
	led.material_override = led_material
	reset_simulation()
	update_face()

func set_muted(value: bool) -> void:
	power_audio.volume_db = -80.0 if value else 0.0

func set_connection(value: bool, clean_fraction: float = 0.0) -> void:
	connected = value
	cleanliness = clampf(clean_fraction, 0.0, 1.0)
	simulated_fps = roundi(lerpf(8.0, 60.0, cleanliness * cleanliness))
	reset_simulation()
	update_face()
	changed.emit()

func toggle_power() -> void:
	powered = not powered
	if powered and power_audio.stream != null: power_audio.play()
	reset_simulation()
	update_face()
	notice.emit("Monitor on. %s" % ("Falling-block test running." if connected else "No GPU signal.") if powered else "Monitor off.")
	changed.emit()

func reset_simulation() -> void:
	board.resize(BOARD_WIDTH * BOARD_HEIGHT)
	board.fill(0)
	for row in range(START_STACK.size()):
		for column in range(BOARD_WIDTH):
			board[(BOARD_HEIGHT - START_STACK.size() + row) * BOARD_WIDTH + column] = START_STACK[row][column]
	rng.seed = 2016
	next_kind = rng.randi_range(1, SHAPES.size())
	opening_piece = true
	score = 0
	lines_cleared = 0
	presented_frames = 0
	frame_time = 0.0
	fall_fraction = 0.0
	steer_time = 0.0
	spawn_piece()
	render_image()

func shape_cells(kind: int, rotation: int = 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var minimum := Vector2i(99, 99)
	for cell in SHAPES[kind - 1]:
		var point: Vector2i = cell
		for step in range(rotation): point = Vector2i(-point.y, point.x)
		minimum.x = mini(minimum.x, point.x)
		minimum.y = mini(minimum.y, point.y)
		result.append(point)
	for index in range(result.size()): result[index] -= minimum
	return result

func spawn_piece() -> void:
	var scripted_opening := opening_piece
	opening_piece = false
	piece_kind = 2 if scripted_opening else next_kind
	if not scripted_opening: next_kind = rng.randi_range(1, SHAPES.size())
	piece_cells = shape_cells(piece_kind, rng.randi_range(0, 3))
	var width := 0
	for cell in piece_cells: width = maxi(width, cell.x + 1)
	piece_x = (BOARD_WIDTH - width) / 2
	piece_y = -2
	target_x = 4 if scripted_opening else rng.randi_range(0, BOARD_WIDTH - width)
	fall_fraction = 0.0
	if collides(piece_x, piece_y):
		# Start a fresh demonstration if the random stack reaches the top.
		board.fill(0)
		score = 0
		lines_cleared = 0

func collides(x: int, y: int) -> bool:
	for cell in piece_cells:
		var column := x + cell.x
		var row := y + cell.y
		if column < 0 or column >= BOARD_WIDTH or row >= BOARD_HEIGHT: return true
		if row >= 0 and board[row * BOARD_WIDTH + column] != 0: return true
	return false

func _process(delta: float) -> void:
	if not powered or not connected: return
	frame_time = minf(frame_time + delta, 0.5)
	var interval := 1.0 / float(simulated_fps)
	var updates := 0
	while frame_time >= interval and updates < 3:
		frame_time -= interval
		advance_demo(interval)
		render_image()
		updates += 1
	if updates == 3: frame_time = minf(frame_time, interval)
	if updates > 0: update_face()

func advance_demo(interval: float) -> void:
	presented_frames += 1
	steer_time += interval
	if steer_time >= 0.16:
		steer_time -= 0.16
		var direction := signi(target_x - piece_x)
		if direction != 0 and not collides(piece_x + direction, piece_y): piece_x += direction
	fall_fraction += 5.5 * interval
	while fall_fraction >= 1.0:
		fall_fraction -= 1.0
		if collides(piece_x, piece_y + 1):
			lock_piece()
			fall_fraction = 0.0
			break
		piece_y += 1

func lock_piece() -> void:
	var topped_out := false
	for cell in piece_cells:
		var row := piece_y + cell.y
		if row < 0:
			topped_out = true
		else:
			board[row * BOARD_WIDTH + piece_x + cell.x] = piece_kind
	if topped_out:
		board.fill(0)
		score = 0
		lines_cleared = 0
	else:
		clear_full_rows()
	spawn_piece()

func clear_full_rows() -> void:
	var row := BOARD_HEIGHT - 1
	while row >= 0:
		var full := true
		for column in range(BOARD_WIDTH):
			if board[row * BOARD_WIDTH + column] == 0:
				full = false
				break
		if not full:
			row -= 1
			continue
		for shifted in range(row, 0, -1):
			for column in range(BOARD_WIDTH):
				board[shifted * BOARD_WIDTH + column] = board[(shifted - 1) * BOARD_WIDTH + column]
		for column in range(BOARD_WIDTH): board[column] = 0
		lines_cleared += 1
		score += 100

func block_color(kind: int) -> Color:
	match kind:
		1: return Color(0.22, 0.84, 0.92)
		2: return Color(0.95, 0.76, 0.21)
		3: return Color(0.63, 0.4, 0.9)
		4: return Color(0.38, 0.8, 0.36)
		5: return Color(0.88, 0.31, 0.31)
		6: return Color(0.28, 0.47, 0.92)
		_: return Color(0.95, 0.53, 0.2)

func paint_rect(x: int, y: int, width: int, height: int, color: Color) -> void:
	for py in range(maxi(0, y), mini(IMAGE_HEIGHT, y + height)):
		for px in range(maxi(0, x), mini(IMAGE_WIDTH, x + width)):
			image.set_pixel(px, py, color)

func paint_block(x: int, y: int, color: Color) -> void:
	paint_rect(x, y, CELL_PIXELS, CELL_PIXELS, color.darkened(0.55))
	paint_rect(x + 1, y + 1, CELL_PIXELS - 2, CELL_PIXELS - 2, color)
	paint_rect(x + 1, y + 1, CELL_PIXELS - 2, 1, color.lightened(0.22))

func render_image() -> void:
	if image == null: return
	image.fill(Color(0.045, 0.065, 0.09))
	paint_rect(BOARD_LEFT - 2, BOARD_TOP - 2, BOARD_WIDTH * CELL_PIXELS + 4,
		BOARD_HEIGHT * CELL_PIXELS + 4, Color(0.44, 0.5, 0.54))
	paint_rect(BOARD_LEFT, BOARD_TOP, BOARD_WIDTH * CELL_PIXELS,
		BOARD_HEIGHT * CELL_PIXELS, Color(0.038, 0.067, 0.095))
	for row in range(BOARD_HEIGHT):
		for column in range(BOARD_WIDTH):
			var kind := board[row * BOARD_WIDTH + column]
			var x := BOARD_LEFT + column * CELL_PIXELS
			var y := BOARD_TOP + row * CELL_PIXELS
			if kind == 0:
				paint_rect(x, y, CELL_PIXELS, 1, Color(0.11, 0.15, 0.19))
				paint_rect(x, y, 1, CELL_PIXELS, Color(0.11, 0.15, 0.19))
			else: paint_block(x, y, block_color(kind))
	var offset_pixels := 0 if collides(piece_x, piece_y + 1) else roundi(fall_fraction * CELL_PIXELS)
	for cell in piece_cells:
		var row := piece_y + cell.y
		if row < 0: continue
		var x := BOARD_LEFT + (piece_x + cell.x) * CELL_PIXELS
		var y := BOARD_TOP + row * CELL_PIXELS + offset_pixels
		if y + CELL_PIXELS <= BOARD_TOP + BOARD_HEIGHT * CELL_PIXELS:
			paint_block(x, y, block_color(piece_kind))
	for cell in shape_cells(next_kind):
		paint_block(16 + cell.x * CELL_PIXELS, 43 + cell.y * CELL_PIXELS, block_color(next_kind))
	if texture != null: texture.update(image)

func update_face() -> void:
	led_material.albedo_color = Color(0.18, 0.67, 0.32) if powered else Color(0.67, 0.32, 0.12)
	if not powered:
		image.fill(Color(0.075, 0.09, 0.105))
		readout.text = ""
	elif not connected:
		image.fill(Color(0.055, 0.105, 0.14))
		readout.text = "NO SIGNAL"
	else:
		readout.text = "TETRIS"
	fps_readout.visible = powered and connected
	fps_readout.text = "SIM %02d FPS" % simulated_fps
	stats.visible = powered and connected
	next_label.visible = stats.visible
	stats.text = "SCORE\n%06d\nLINES\n%02d" % [score, lines_cleared]
	if not powered or not connected: texture.update(image)
