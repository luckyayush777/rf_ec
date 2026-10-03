extends Node3D
## Printed retail packaging, with a hinged lid, foam cradle and anti-static sleeve.

@export var box_size := Vector3(2.2, 0.7, 1.3)
@export_multiline var label_text := ""
@export var sealed := false
@export var start_visible := false

const GpuStyle = preload("res://scripts/gpu_style.gd")
const AudioMix = preload("res://scripts/audio_mix.gd")
## Flaps opening, then the card sliding out of its anti-static sleeve, timed to the lid and lift.
const UNBOX_SOUND = preload("res://assets/sounds/gpu_unbox.wav")
const UNBOX_GAIN_DB := -4.0
## Paperwork on the lid. A referring tech tags the faults they found in marker: a green tag for
## one, a yellow tag for two, a red card for three or more. A customer leaves a sticky note in pen.
const MARKER_FONT = preload("res://assets/fonts/PermanentMarker-Regular.ttf")
const PEN_FONT = preload("res://assets/fonts/Caveat-Variable.ttf")
const MARKER_INK := Color("16181d")
const PEN_INK := Color("1f3a8f")
## Saturated, because the bench lamp washes pale paper out to white.
const TAG_COLORS := {"green": Color("3f9e4c"), "yellow": Color("e8b21c"), "red": Color("c42e26")}
const NOTE_COLOR := Color("f2d33a")
## Paper sizes on the lid (width, depth) and how many characters fit a handwritten line; large
## enough to read from where the player stands at the desk.
const TAG_SIZE := Vector2(0.95, 0.5)
const CARD_SIZE := Vector2(1.05, 0.64)
const NOTE_SIZE := Vector2(0.78, 0.74)
const NOTE_LINE_CHARS := 13
const LINE_HEIGHT := 0.12
const WALL := 0.03
const OPEN_ANGLE := deg_to_rad(110.0)
const FOAM_HEIGHT := 0.24

var flaps: Array[Node3D] = []
var tape: MeshInstance3D
var label: Label3D
var cardboard: StandardMaterial3D
var accent: StandardMaterial3D
var inner: StandardMaterial3D
var motion: Tween
var rest := Transform3D.IDENTITY
var brand := "Lotac"
var parked := false
var print_labels: Array[Label3D] = []
var brand_labels: Array[Label3D] = []
var unbox_audio: AudioStreamPlayer
var muted := false
## The paper on the lid: "" (none), "green"/"yellow"/"red" (tech fault tag) or "note".
var paperwork := ""
var paper: Node3D
var paper_material: StandardMaterial3D
## Every handwritten line currently on the paper, for tests and captures.
var handwriting: Array[Label3D] = []

func _ready() -> void:
	rest = transform
	set_meta("action", "sealed_box" if sealed else "delivery_box")
	cardboard = flat("f0dfbc", 0.65)
	accent = flat("e79a48", 0.5)
	inner = flat("e5e5dc", 0.9)
	var w := box_size.x
	var h := box_size.y
	var d := box_size.z
	add_block("Floor", Vector3(w, WALL, d), Vector3(0, WALL * 0.5, 0), inner)
	add_block("WallFront", Vector3(w, h, WALL), Vector3(0, h * 0.5, d * 0.5 - WALL * 0.5), cardboard)
	add_block("WallBack", Vector3(w, h, WALL), Vector3(0, h * 0.5, -d * 0.5 + WALL * 0.5), cardboard)
	add_block("WallLeft", Vector3(WALL, h, d - WALL * 2.0), Vector3(-w * 0.5 + WALL * 0.5, h * 0.5, 0), cardboard)
	add_block("WallRight", Vector3(WALL, h, d - WALL * 2.0), Vector3(w * 0.5 - WALL * 0.5, h * 0.5, 0), cardboard)
	add_block("PrintedFrontBand", Vector3(w, h * 0.13, 0.006), Vector3(0, h * 0.43, d * 0.5 + 0.003), accent)
	for side in [-1.0, 1.0]:
		add_block("PrintedSideBand", Vector3(0.006, h * 0.13, d), Vector3(side * (w * 0.5 + 0.003), h * 0.43, 0), accent)
	var pivot := Node3D.new()
	pivot.name = "LidHinge"
	pivot.position = Vector3(0, h, -d * 0.5)
	add_child(pivot)
	add_block("Lid", Vector3(w + 0.035, WALL, d + 0.035), Vector3(0, WALL * 0.5, d * 0.5), cardboard, pivot)
	flaps.append(pivot)
	add_block("LidStripe", Vector3(w * 0.20, 0.005, d + 0.035), Vector3(w * 0.38, WALL + 0.003, d * 0.5), accent, pivot)
	brand_labels.append(add_text("TopBrand", "LOTAC", Vector3(-w * 0.13, WALL + 0.01, d * 0.24), w * 0.57, pivot, true))
	var model := add_text("TopModel", "710", Vector3(-w * 0.18, WALL + 0.01, d * 0.56), w * 0.42, pivot, true)
	model.font_size = 160
	model.pixel_size *= 0.75
	add_text("TopSpecs", "2GB DDR3 / GRAPHICS", Vector3(-w * 0.13, WALL + 0.01, d * 0.85), w * 0.72, pivot, true)
	var fan := MeshInstance3D.new()
	fan.name = "PrintedFan"
	var disc := CylinderMesh.new()
	disc.top_radius = d * 0.19
	disc.bottom_radius = disc.top_radius
	disc.height = 0.005
	disc.material = inner
	fan.mesh = disc
	fan.position = Vector3(w * 0.33, WALL + 0.012, d * 0.54)
	pivot.add_child(fan)
	for index in range(6):
		var angle := index * TAU / 6.0
		var blade := add_block("PrintedBlade", Vector3(d * 0.08, 0.005, d * 0.20), Vector3(sin(angle) * d * 0.075, 0.005, cos(angle) * d * 0.075), cardboard, fan)
		blade.rotation.y = angle + 0.35
	var inside := add_text("InsideBrand", "LOTAC", Vector3(0, -0.008, d * 0.53), w * 0.65, pivot)
	inside.rotation.x = PI * 0.5
	brand_labels.append(inside)
	brand_labels.append(add_text("FrontBrand", "LOTAC / 710", Vector3(0, h * 0.72, d * 0.5 + 0.008), w * 0.8))
	label = add_text("Label", "", Vector3(0, h * 0.20, d * 0.5 + 0.01), w * 0.8)
	label.font_size = 40
	set_label(label_text)
	tape = add_block("TamperSeal", Vector3(w * 0.14, h * 0.26, 0.008), Vector3(w * 0.39, h * 0.78, d * 0.5 + 0.015), accent)
	if not sealed:
		build_packing()
		unbox_audio = AudioStreamPlayer.new()
		unbox_audio.name = "UnboxSound"
		unbox_audio.stream = UNBOX_SOUND
		unbox_audio.volume_db = UNBOX_GAIN_DB
		unbox_audio.bus = AudioMix.UNBOX
		add_child(unbox_audio)
		paper = Node3D.new()
		paper.name = "Paperwork"
		pivot.add_child(paper)
		paper_material = flat("ffffff", 0.9)
	set_brand("" if sealed else brand)
	visible = start_visible

func flat(color: String, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = roughness
	material.metallic = metallic
	return material

func add_block(block_name: String, size: Vector3, at: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = block_name
	node.mesh = mesh
	node.position = at
	parent.add_child(node)
	return node

func add_text(text_name: String, text: String, at: Vector3, width: float, parent: Node3D = self, top := false) -> Label3D:
	var node := Label3D.new()
	node.name = text_name
	node.text = text
	node.font_size = 100
	node.outline_size = 0
	node.double_sided = false
	node.pixel_size = width / maxf(text.length() * 60.0, 60.0)
	node.position = at
	if top: node.rotation.x = -PI * 0.5
	parent.add_child(node)
	print_labels.append(node)
	return node

func build_packing() -> void:
	var w := box_size.x
	var d := box_size.z
	var foam := flat("242c39", 1.0)
	add_block("FoamBed", Vector3(w - WALL * 2.0, FOAM_HEIGHT, d - WALL * 2.0), Vector3(0, WALL + FOAM_HEIGHT * 0.5, 0), foam)
	for side in [-1.0, 1.0]:
		add_block("FoamEnd", Vector3(w * 0.10, 0.15, d - 0.10), Vector3(side * w * 0.435, WALL + FOAM_HEIGHT + 0.075, 0), foam)
		add_block("FoamRail", Vector3(w * 0.77, 0.12, d * 0.12), Vector3(0, WALL + FOAM_HEIGHT + 0.06, side * d * 0.41), foam)
	var foil := flat("acbac5", 0.36, 0.72)
	add_block("AntiStaticSleeve", Vector3(w * 0.79, 0.025, d * 0.67), Vector3(0, WALL + FOAM_HEIGHT + 0.015, 0), foil)
	for side in [-1.0, 1.0]:
		for index in range(9):
			add_block("SleeveCrimp", Vector3(0.003, 0.005, d * 0.64), Vector3(side * w * 0.39 + (index - 4) * 0.006, WALL + FOAM_HEIGHT + 0.030, 0), foil)
	var esd := add_text("ESDMark", "ESD / STATIC SHIELD", Vector3(0, WALL + FOAM_HEIGHT + 0.030, d * 0.19), w * 0.48, self, true)
	esd.modulate = Color("34414c")
	print_labels.erase(esd)

func set_label(text: String) -> void:
	label_text = text
	if label == null: return
	label.text = text
	var lines := text.split("\n")
	var longest := 1
	for line in lines: longest = maxi(longest, line.length())
	label.pixel_size = minf(box_size.x * 0.8 / (longest * 24.0), box_size.y * 0.30 / (lines.size() * 52.0))

func set_brand(id: String) -> void:
	brand = id
	var colors := GpuStyle.palette(id)
	cardboard.albedo_color = Color(colors.box if not id.is_empty() else "e5e8e8")
	accent.albedo_color = Color(colors.accent if not id.is_empty() else "6d9cb2")
	for text in print_labels:
		text.modulate = Color(colors.ink if not id.is_empty() else "304450")
	brand_labels[0].text = id.to_upper() if not id.is_empty() else "BENCH"
	brand_labels[1].text = id.to_upper() + "\n710 / 2GB DDR3" if not id.is_empty() else "INSTRUMENTS"
	var longest := 1
	for line in brand_labels[1].text.split("\n"): longest = maxi(longest, line.length())
	brand_labels[1].pixel_size = box_size.x * 0.65 / (longest * 60.0)
	brand_labels[2].text = id.to_upper() + " / 710" if not id.is_empty() else "THERMAL CAMERA"
	if sealed:
		get_node("LidHinge/TopModel").text = "IR"
		get_node("LidHinge/TopSpecs").text = "HANDHELD IMAGER"

## Colour of a tech's fault tag for this many diagnosed faults.
static func tag_color(count: int) -> String:
	return "green" if count <= 1 else "yellow" if count == 2 else "red"

## Lays the job's paperwork on the lid: tagged faults from a tech (signed), or a customer's note.
## Both empty leaves the lid bare.
func set_paperwork(faults: Array, note := "", signature := "") -> void:
	if paper == null: return
	for child in paper.get_children(): child.queue_free()
	handwriting.clear()
	paperwork = "" if faults.is_empty() and note == "" else "note" if faults.is_empty() else tag_color(faults.size())
	paper.visible = paperwork != ""
	if paperwork == "": return
	var w := box_size.x
	var d := box_size.z
	# The same handwriting every time the same paperwork is laid out.
	var jitter := RandomNumberGenerator.new()
	jitter.seed = hash(str(faults) + note + signature)
	var size: Vector2 = NOTE_SIZE if paperwork == "note" else CARD_SIZE if paperwork == "red" else TAG_SIZE
	paper_material.albedo_color = NOTE_COLOR if paperwork == "note" else TAG_COLORS[paperwork]
	# Stuck on the lid's front half beside the printed fan, a little askew.
	# Above the lid's printed text and fan (up to WALL + 0.015).
	paper.position = Vector3(w * 0.06, WALL + 0.018, d * 0.6)
	paper.rotation = Vector3(0, jitter.randf_range(-0.22, -0.08) if paperwork == "note" else jitter.randf_range(0.1, 0.24), 0)
	add_block("Paper", Vector3(size.x, 0.004, size.y), Vector3.ZERO, paper_material, paper)
	var lines: Array[String] = []
	var font: Font = PEN_FONT if paperwork == "note" else MARKER_FONT
	var ink: Color = PEN_INK if paperwork == "note" else MARKER_INK
	if paperwork == "note":
		lines = wrap_words(note, NOTE_LINE_CHARS)
	else:
		lines.assign(faults)
		# Tags hang on a string; the red card is plain card.
		if paperwork != "red": add_tag_eyelet(size)
	# Marker capitals need a little more room per line than ballpoint.
	var height := LINE_HEIGHT * (0.9 if paperwork != "note" else 0.85)
	var top := -height * (lines.size() + (0.9 if signature != "" else 0.0)) * 0.5 + height * 0.5
	var left := -size.x * (0.36 if paperwork != "note" else 0.42)
	for index in range(lines.size()):
		write_line(lines[index], font, ink, height, Vector3(left, 0, top + index * height), jitter)
	if signature != "":
		write_line("- " + signature, PEN_FONT, PEN_INK, height * 0.95, Vector3(size.x * 0.05, 0, top + lines.size() * height + height * 0.05), jitter)

## One handwritten line, left-aligned at `at` on the paper, slightly off the ruled line.
func write_line(line: String, font: Font, ink: Color, height: float, at: Vector3, jitter: RandomNumberGenerator) -> void:
	var node := Label3D.new()
	node.name = "Handwriting"
	node.text = line
	node.font = font
	node.font_size = 64
	# Glyphs fill most of the line height.
	node.pixel_size = height / 60.0 * jitter.randf_range(0.94, 1.06)
	# A slightly thicker stroke in the same ink reads as pen pressure, not an outline.
	node.outline_size = 3
	node.modulate = ink
	node.outline_modulate = ink
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	node.double_sided = false
	node.position = at + Vector3(jitter.randf_range(-0.012, 0.012), 0.004, jitter.randf_range(-0.008, 0.008))
	node.rotation = Vector3(-PI * 0.5, 0, jitter.randf_range(-0.07, 0.07))
	paper.add_child(node)
	handwriting.append(node)

## A paper tag's reinforced eyelet and a loose length of string on its left end.
func add_tag_eyelet(size: Vector2) -> void:
	var ring := MeshInstance3D.new()
	ring.name = "Eyelet"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.035
	disc.bottom_radius = 0.035
	disc.height = 0.002
	disc.material = flat("f4efe2", 0.8)
	ring.mesh = disc
	ring.position = Vector3(-size.x * 0.5 + 0.05, 0.003, 0)
	paper.add_child(ring)
	var string := add_block("String", Vector3(0.24, 0.006, 0.01), Vector3(-size.x * 0.5 - 0.06, 0.004, 0.03), flat("c9b48a", 1.0), paper)
	string.rotation.y = 0.5

static func wrap_words(text: String, width: int) -> Array[String]:
	var lines: Array[String] = []
	var current := ""
	for word in text.split(" ", false):
		if current != "" and current.length() + 1 + word.length() > width:
			lines.append(current)
			current = word
		else:
			current = word if current == "" else current + " " + word
	if current != "": lines.append(current)
	return lines

func deliver(text: String, id := "Lotac", faults: Array = [], note := "", signature := "") -> void:
	set_brand(id)
	set_label(text)
	set_paperwork(faults, note, signature)
	if motion != null: motion.kill()
	for pivot in flaps: pivot.basis = Basis.IDENTITY
	tape.visible = true
	parked = false
	set_meta("action", "delivery_box")
	transform = rest.translated(Vector3(0, 1.6, 0))
	scale = Vector3.ONE
	visible = true
	motion = create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	motion.tween_property(self, "transform", rest, 0.5)

func open() -> Signal:
	if motion != null: motion.kill()
	transform = rest
	tape.visible = false
	if unbox_audio != null and not muted: unbox_audio.play()
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	motion.tween_property(flaps[0], "rotation:x", -OPEN_ANGLE, 0.55)
	return motion.finished

func set_muted(value: bool) -> void:
	muted = value
	if muted and unbox_audio != null: unbox_audio.stop()

func _exit_tree() -> void:
	if unbox_audio != null: unbox_audio.stop()

func cradle_point() -> Vector3:
	return to_global(Vector3(0, WALL + FOAM_HEIGHT + 0.030, 0))

func park_at(destination: Vector3) -> Signal:
	if motion != null: motion.kill()
	parked = true
	set_meta("action", "")
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	motion.tween_property(self, "global_position", destination, 0.45)
	return motion.finished

func take_away() -> void:
	if motion != null: motion.kill()
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	motion.tween_property(self, "scale", Vector3.ONE * 0.01, 0.25)
	motion.finished.connect(func():
		visible = false
		parked = false
		transform = rest)
