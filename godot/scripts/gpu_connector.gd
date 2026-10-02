extends Node
## The card's PCIe edge connector: its gold fingers and how well they meet the test board's
## slot. Damage states:
##   "oxidised" - tarnished fingers. The link trains at x8 and drops out now and then, more
##                often while the card is rocked in the slot.
##   "lifted"   - one finger peeled up at its tip. Full x16 until the seated card is rocked
##                past LIFT_CONTACT_ANGLE, then the picture cuts out until it settles.
##   "torn"     - one finger ripped off. Its lanes are gone: a steady x4 link.
## A narrow link caps the test feed's frame rate while temperatures and clock stay healthy.
## Damage is drawn on the imported gold-contact meshes, fine enough to want the loupe.
## Repairs are not implemented yet, so jobs never roll these; debug builds set them.
signal changed
signal notice(text: String)

const STATES := ["ok", "oxidised", "lifted", "torn"]
const LINK_WIDTH := {"ok": 16, "oxidised": 8, "lifted": 16, "torn": 4}
const LABELS := {"ok": "clean contacts", "oxidised": "oxidised fingers", "lifted": "lifted finger", "torn": "torn finger"}
## Imported contacts are gold-contact-<index>-<side>; index 5-6 is the key notch, side 1 faces the fan.
const TARNISHED := ["gold-contact-8-1", "gold-contact-9-1", "gold-contact-12-1", "gold-contact-13-1", "gold-contact-14-1",
	"gold-contact-20-1", "gold-contact-21-1", "gold-contact-27-1", "gold-contact-2--1", "gold-contact-10--1",
	"gold-contact-11--1", "gold-contact-22--1", "gold-contact-30--1"]
const LIFTED := "gold-contact-17-1"
const TORN := "gold-contact-24-1"
const LIFT_ANGLE := 0.24
## Contact half-length along the finger, in its mesh space.
const HALF_LENGTH := 0.1325
## Rocking the seated card past this opens a lifted finger's contact.
const LIFT_CONTACT_ANGLE := 0.011
## Link retraining after a dropout, once contact is restored.
const RETRAIN_TIME := 0.8
## Mean seconds between oxidised dropouts under power; rocking makes them much likelier.
const DROP_INTERVAL := 9.0
const ROCK_DROP_BOOST := 12.0

var bench: Node3D
var state := "ok"
var contacts: Dictionary = {}
var homes: Dictionary = {}
var materials: Dictionary = {}
var tarnish: StandardMaterial3D
var scar: Array[MeshInstance3D] = []
var link_up := true
var retrain := 0.0
var drops := 0
var rng := RandomNumberGenerator.new()

func configure(world: Node3D) -> void:
	bench = world
	rng.randomize()
	var edge: Node3D = bench.gpu.find_child("edge-connector", true, false)
	for node in edge.get_children():
		if String(node.name).begins_with("gold-contact-"):
			contacts[String(node.name)] = node
			homes[String(node.name)] = node.transform
			materials[String(node.name)] = node.material_override
	tarnish = StandardMaterial3D.new()
	tarnish.metallic = 0.35
	tarnish.roughness = 0.8
	tarnish.uv1_triplanar = true
	tarnish.uv1_scale = Vector3(14, 14, 14)
	var noise := FastNoiseLite.new()
	noise.seed = 2416
	noise.frequency = 0.06
	noise.fractal_octaves = 3
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.45, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(0.77, 0.65, 0.36), Color(0.6, 0.47, 0.24), Color(0.4, 0.31, 0.15), Color(0.3, 0.36, 0.22)])
	var pattern := NoiseTexture2D.new()
	pattern.width = 64
	pattern.height = 64
	pattern.seamless = true
	pattern.noise = noise
	pattern.color_ramp = ramp
	tarnish.albedo_texture = pattern
	# The torn finger leaves a stub, bare fibreglass where it was, and a curl of trace.
	var torn: MeshInstance3D = contacts[TORN]
	var gold: Material = torn.get_active_material(0)
	scar.append(add_block(edge, "torn-finger-stub", Vector3(0.071, 0.009, 0.08), Vector3(0, 0, -HALF_LENGTH + 0.04), torn, gold))
	scar.append(add_block(edge, "torn-finger-scar", Vector3(0.075, 0.004, 0.18), Vector3(0, -0.003, 0.04), torn,
		flat(Color(0.74, 0.7, 0.52), 0.9)))
	scar.append(add_block(edge, "torn-finger-trace", Vector3(0.016, 0.006, 0.05), Vector3(0.012, 0.001, -0.02), torn,
		flat(Color(0.72, 0.42, 0.24), 0.4, 0.8)))
	set_state("ok")

func flat(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func add_block(parent: Node3D, block_name: String, size: Vector3, offset: Vector3, beside: Node3D, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = block_name
	node.mesh = mesh
	parent.add_child(node)
	node.transform = homes[String(beside.name)] * Transform3D(Basis.IDENTITY, offset)
	return node

## Lays the damage on the fingers; "ok" restores every authored contact.
func set_state(id: String) -> void:
	state = id
	for key in contacts:
		var contact: MeshInstance3D = contacts[key]
		contact.transform = homes[key]
		contact.material_override = materials[key]
		contact.visible = true
	for node in scar: node.visible = id == "torn"
	match id:
		"oxidised":
			for key in TARNISHED: contacts[key].material_override = tarnish
		"lifted":
			# The tip peels away from the board about the finger's inner end.
			var pivot := Vector3(0, 0, -HALF_LENGTH)
			contacts[LIFTED].transform = homes[LIFTED] * Transform3D(Basis.IDENTITY, pivot) * Transform3D(Basis(Vector3.RIGHT, -LIFT_ANGLE), -pivot)
		"torn":
			contacts[TORN].visible = false
	link_up = true
	retrain = 0.0
	changed.emit()

func debug_cycle() -> bool:
	if not OS.is_debug_build(): return false
	set_state(STATES[(STATES.find(state) + 1) % STATES.size()])
	notice.emit("Debug: edge connector now has %s." % LABELS[state])
	return true

## World centre and length of the finger row, for framing it under the loupe.
func centre() -> Vector3:
	var total := Vector3.ZERO
	for key in contacts: total += contacts[key].global_position
	return total / contacts.size()

func span() -> float:
	var low := INF
	var high := -INF
	for key in contacts:
		var along: float = bench.gpu.to_local(contacts[key].global_position).x
		low = minf(low, along)
		high = maxf(high, along)
	return (high - low) * bench.gpu.global_basis.get_scale().x

## Lanes the slot trained; 0 while the link is down.
func link_width() -> int:
	return LINK_WIDTH[state] if link_up else 0

func drop() -> void:
	link_up = false
	retrain = RETRAIN_TIME
	drops += 1

func _process(delta: float) -> void:
	if bench == null: return
	step(delta)

func step(delta: float) -> void:
	var station: Node = bench.testing_station
	if not station.installed or station.moving:
		link_up = true
		retrain = 0.0
		return
	var rocking: float = absf(station.rock_angle)
	var open: bool = state == "lifted" and rocking > LIFT_CONTACT_ANGLE
	if link_up:
		if open: drop()
		elif state == "oxidised":
			var chance := delta / DROP_INTERVAL * (1.0 + ROCK_DROP_BOOST * clampf(rocking / LIFT_CONTACT_ANGLE, 0.0, 1.0))
			if rng.randf() < chance: drop()
	elif not open:
		retrain -= delta
		if retrain <= 0.0: link_up = true
	bench.test_monitor.set_link(link_width())
