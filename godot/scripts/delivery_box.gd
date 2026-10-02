extends Node3D
## A taped shipping carton: four walls, a floor, four top flaps on hinges, a packing tape strip
## and a printed label. Inside, a foam insert with a recess cradles the card. The origin sits
## at the centre of the carton's footprint on the table. A sealed carton (the thermal camera
## for now) only reports what is inside; a delivery carton opens with one click.

## Outer size: x across the long side, y height, z depth.
@export var box_size := Vector3(2.2, 0.7, 1.3)
@export_multiline var label_text := ""
@export var sealed := false
## Shown hidden until a job ships it; a sealed box shows from the start.
@export var start_visible := false

const WALL := 0.03
const OPEN_ANGLE := deg_to_rad(235.0)
const FOAM_HEIGHT := 0.42

var flaps: Array[Node3D] = []
var flap_axes: Array[Vector3] = []
var tape: MeshInstance3D
var label: Label3D
var cardboard: StandardMaterial3D
var motion: Tween
var rest := Transform3D.IDENTITY

func _ready() -> void:
	rest = transform
	set_meta("action", "sealed_box" if sealed else "delivery_box")
	cardboard = StandardMaterial3D.new()
	cardboard.albedo_color = Color(0.46, 0.31, 0.17)
	cardboard.roughness = 0.92
	var inner := StandardMaterial3D.new()
	inner.albedo_color = Color(0.38, 0.26, 0.14)
	inner.roughness = 0.95
	var w := box_size.x
	var h := box_size.y
	var d := box_size.z
	add_block("Floor", Vector3(w, WALL, d), Vector3(0, WALL * 0.5, 0), inner)
	add_block("WallFront", Vector3(w, h, WALL), Vector3(0, h * 0.5, d * 0.5 - WALL * 0.5), cardboard)
	add_block("WallBack", Vector3(w, h, WALL), Vector3(0, h * 0.5, -d * 0.5 + WALL * 0.5), cardboard)
	add_block("WallLeft", Vector3(WALL, h, d - WALL * 2.0), Vector3(-w * 0.5 + WALL * 0.5, h * 0.5, 0), cardboard)
	add_block("WallRight", Vector3(WALL, h, d - WALL * 2.0), Vector3(w * 0.5 - WALL * 0.5, h * 0.5, 0), cardboard)
	if not sealed:
		var foam := StandardMaterial3D.new()
		foam.albedo_color = Color(0.82, 0.84, 0.86)
		foam.roughness = 1.0
		add_block("Foam", Vector3(w - WALL * 2.0, FOAM_HEIGHT, d - WALL * 2.0), Vector3(0, WALL + FOAM_HEIGHT * 0.5, 0), foam)
		var recess := StandardMaterial3D.new()
		recess.albedo_color = Color(0.36, 0.38, 0.41)
		recess.roughness = 1.0
		add_block("FoamRecess", Vector3(w * 0.74, 0.004, d * 0.62), Vector3(0, WALL + FOAM_HEIGHT + 0.002, 0), recess)
	# Long flaps meet in the middle; the short end flaps fold under them.
	add_flap(Vector3(0, h, d * 0.5), Vector3(w, WALL, d * 0.5), Vector3(0, 0, -d * 0.25), Vector3.RIGHT, 0.0)
	add_flap(Vector3(0, h, -d * 0.5), Vector3(w, WALL, d * 0.5), Vector3(0, 0, d * 0.25), Vector3.LEFT, 0.0)
	var short := minf(w, d) * 0.45
	add_flap(Vector3(w * 0.5, h, 0), Vector3(short, WALL, d - WALL * 2.0), Vector3(-short * 0.5, 0, 0), Vector3.FORWARD, -WALL)
	add_flap(Vector3(-w * 0.5, h, 0), Vector3(short, WALL, d - WALL * 2.0), Vector3(short * 0.5, 0, 0), Vector3.BACK, -WALL)
	var tape_material := StandardMaterial3D.new()
	tape_material.albedo_color = Color(0.72, 0.6, 0.38, 0.85)
	tape_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tape_material.roughness = 0.35
	tape = add_block("Tape", Vector3(w + 0.02, 0.006, 0.16), Vector3(0, h + WALL * 0.5 + 0.004, 0), tape_material)
	var sticker := StandardMaterial3D.new()
	sticker.albedo_color = Color(0.94, 0.93, 0.89)
	sticker.roughness = 0.8
	add_block("LabelPaper", Vector3(w * 0.62, h * 0.62, 0.004), Vector3(0, h * 0.5, d * 0.5 + 0.002), sticker)
	label = Label3D.new()
	label.name = "Label"
	label.font_size = 40
	label.outline_size = 0
	label.modulate = Color(0.12, 0.13, 0.15)
	label.position = Vector3(0, h * 0.5, d * 0.5 + 0.006)
	add_child(label)
	set_label(label_text)
	if sealed:
		var band := StandardMaterial3D.new()
		band.albedo_color = Color(0.93, 0.47, 0.12)
		add_block("ProductBand", Vector3(w + 0.004, h * 0.14, d + 0.004), Vector3(0, h * 0.16, 0), band)
	visible = start_visible

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

## hinge: top edge of a wall; offset: flap centre from the hinge; axis: opening rotation axis.
func add_flap(hinge: Vector3, size: Vector3, offset: Vector3, axis: Vector3, drop: float) -> void:
	var pivot := Node3D.new()
	pivot.name = "Flap%d" % flaps.size()
	pivot.position = hinge + Vector3(0, WALL * 0.5 + drop, 0)
	add_child(pivot)
	add_block("Panel", size, offset, cardboard, pivot)
	flaps.append(pivot)
	flap_axes.append(axis)

## Fits the printed text inside the label paper.
func set_label(text: String) -> void:
	label_text = text
	if label == null: return
	label.text = text
	var lines := text.split("\n")
	var longest := 1
	for line in lines: longest = maxi(longest, line.length())
	label.pixel_size = minf(box_size.x * 0.58 / (longest * 24.0), box_size.y * 0.55 / (lines.size() * 52.0))

## A courier drops the closed, taped box on the desk.
func deliver(text: String) -> void:
	set_label(text)
	if motion != null: motion.kill()
	for pivot in flaps: pivot.basis = Basis.IDENTITY
	tape.visible = true
	transform = rest.translated(Vector3(0, 1.6, 0))
	scale = Vector3.ONE
	visible = true
	motion = create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	motion.tween_property(self, "transform", rest, 0.5)

## Slits the tape and swings the flaps out over the walls.
func open() -> Signal:
	if motion != null: motion.kill()
	transform = rest
	tape.visible = false
	motion = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for index in range(flaps.size()):
		# Angles, not bases: a basis tween would take the short way round.
		var pivot := flaps[index]
		var axis := flap_axes[index]
		motion.tween_method(func(angle: float): pivot.basis = Basis(axis, angle), 0.0, OPEN_ANGLE * (1.0 if index < 2 else 0.9), 0.55) \
			.set_delay(0.08 * (index % 2) + (0.12 if index >= 2 else 0.0))
	return motion.finished

## Where the card's footprint centre rests on the foam, in world space.
func cradle_point() -> Vector3:
	return to_global(Vector3(0, WALL + FOAM_HEIGHT + 0.004, 0))

## The empty carton is cleared off the desk.
func take_away() -> void:
	if motion != null: motion.kill()
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	motion.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.35)
	motion.finished.connect(func():
		visible = false
		transform = rest)
