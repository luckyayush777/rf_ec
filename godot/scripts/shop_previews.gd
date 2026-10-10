extends Node
## Product shots for the shop computer's supply catalog: every store item turned on a small
## turntable in its own SubViewport and world. Tools come from their own scenes, equipment from
## scriptless copies of the shop's real furniture, and the workshop upgrades from simple props.
## Each view renders once; the one whose catalog card is hovered keeps turning.
const Contract = preload("res://scripts/asset_contract.gd")
const SIZE := Vector2i(256, 150)
const BACKDROP := Color("#0a1c11")
const FOV := 30.0
## Camera elevation above the turntable and the resting three-quarter turn.
const ELEVATION := 0.42
const REST_YAW := -0.55
const TURN_SPEED := 0.8
const TOOL_SCENES := {
	"air-blower": "res://scenes/air_blower.tscn",
	"screwdriver": "res://scenes/screwdriver.tscn",
	"spudger": "res://scenes/spudger.tscn",
	"ipa-wipe": "res://scenes/ipa_wipe.tscn",
	"paste-syringe": "res://scenes/paste_syringe.tscn",
	"fan-oiler": "res://scenes/fan_oiler.tscn",
	"loupe": "res://scenes/loupe.tscn",
	"thermal-camera": "res://scenes/thermal_camera.tscn",
	"dev-blower": "res://scenes/dev_blower.tscn"}

var views := {}
var turntables := {}
var spinning := ""

## One view per catalog item of `shop` (a `shop_inventory.gd`).
func build(shop: Node) -> void:
	for id in shop.CATALOG:
		var model := make_model(id, shop)
		if model != null: add_view(id, model)

func texture(id: String) -> Texture2D:
	return views[id].get_texture() if views.has(id) else null

## Turns the hovered item; the others hold their last frame.
func spin(id: String, on: bool) -> void:
	if on: spinning = id
	elif spinning == id: spinning = ""
	for key in views:
		views[key].render_target_update_mode = SubViewport.UPDATE_ALWAYS if key == spinning else SubViewport.UPDATE_ONCE

func _process(delta: float) -> void:
	if spinning != "" and turntables.has(spinning): turntables[spinning].rotate_y(delta * TURN_SPEED)

func make_model(id: String, shop: Node) -> Node3D:
	if TOOL_SCENES.has(id): return load(TOOL_SCENES[id]).instantiate()
	if shop.equipment.has(id): return copy(shop.equipment[id])
	match id:
		"lighting": return lamp_prop()
		"refurbishment": return paint_prop()
		"shop-expansion": return floor_prop()
	return null

## A look-alike of live furniture: no scripts, screens' viewports, collision, sound or lights.
static func copy(source: Node3D) -> Node3D:
	var model: Node3D = source.duplicate(0)
	model.transform = Transform3D.IDENTITY
	model.visible = true
	strip(model)
	return model

static func strip(node: Node) -> void:
	for child in node.get_children():
		if child is Viewport or child is CollisionObject3D or child is Light3D or child is Camera3D or not child is Node3D:
			node.remove_child(child)
			child.free()
		else: strip(child)

func add_view(id: String, model: Node3D) -> void:
	var view := SubViewport.new()
	view.name = "Preview_" + id
	view.size = SIZE
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	var turntable := Node3D.new()
	turntable.name = "Turntable"
	view.add_child(turntable)
	turntable.add_child(model)
	# Tools lie with their longest side across the frame; furniture and props stand upright.
	var bounds := Contract.bounds_in(model)
	if TOOL_SCENES.has(id):
		if bounds.size.y > maxf(bounds.size.x, bounds.size.z) * 1.4: model.basis = Basis(Vector3.BACK, PI * 0.5) * model.basis
		elif bounds.size.z > bounds.size.x: model.basis = Basis(Vector3.UP, PI * 0.5) * model.basis
	bounds = model.transform * bounds
	model.position -= bounds.get_center()
	var half := bounds.size * 0.5
	turntable.rotation.y = REST_YAW
	turntables[id] = turntable
	# Far enough that the model stays in frame through a whole turn.
	var aspect := float(SIZE.x) / SIZE.y
	var tangent := tan(deg_to_rad(FOV) * 0.5)
	var radius := Vector2(half.x, half.z).length()
	var tall := half.y * cos(ELEVATION) + radius * sin(ELEVATION)
	var distance := maxf(radius / (tangent * aspect), tall / tangent) * 1.08 + radius * 0.5
	var camera := Camera3D.new()
	camera.fov = FOV
	camera.near = maxf(0.01, distance * 0.02)
	camera.far = distance * 4.0
	camera.position = Vector3(0, sin(ELEVATION), cos(ELEVATION)) * distance
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKDROP
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.9, 1.0)
	environment.ambient_light_energy = 0.55
	camera.environment = environment
	view.add_child(camera)
	camera.look_at(Vector3.ZERO)
	for entry in [[Vector3(-0.9, 0.6, 0), 1.25, Color(1.0, 0.95, 0.88)], [Vector3(-0.35, -2.4, 0), 0.45, Color(0.7, 0.85, 1.0)]]:
		var light := DirectionalLight3D.new()
		light.rotation = entry[0]
		light.light_energy = entry[1]
		light.light_color = entry[2]
		view.add_child(light)
	views[id] = view

# --- Workshop props --------------------------------------------------------------------------

static func material(color: Color, roughness := 0.7, glow := 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	if glow > 0.0:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = glow
	return result

static func box(parent: Node3D, size: Vector3, at: Vector3, look: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = look
	node.position = at
	parent.add_child(node)
	return node

static func cylinder(parent: Node3D, radius: float, length: float, at: Vector3, look: Material, along := Vector3.UP) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 24
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = look
	node.position = at
	if along != Vector3.UP: node.basis = Basis(Quaternion(Vector3.UP, along.normalized()))
	parent.add_child(node)
	return node

## A twin-tube workshop batten on its chains.
static func lamp_prop() -> Node3D:
	var root := Node3D.new()
	var housing := material(Color("#e8e2d2"), 0.5)
	box(root, Vector3(4.2, 0.22, 0.8), Vector3(0, 0.9, 0), housing)
	for side in [-0.18, 0.18]:
		cylinder(root, 0.09, 3.9, Vector3(0, 0.72, side), material(Color("#fff4dc"), 0.3, 2.5), Vector3.RIGHT)
	for end in [-1.6, 1.6]:
		cylinder(root, 0.025, 1.0, Vector3(end, 1.5, 0), material(Color("#8d8a82"), 0.4))
	box(root, Vector3(4.6, 0.12, 1.2), Vector3(0, 2.05, 0), material(Color("#6f6a5f"), 0.9))
	return root

## A tin of fresh wall paint with its roller and a sanding block for the worktop.
static func paint_prop() -> Node3D:
	var root := Node3D.new()
	cylinder(root, 0.62, 0.95, Vector3(-0.5, 0.475, 0), material(Color("#d9d3c1"), 0.4, 0.0))
	cylinder(root, 0.63, 0.34, Vector3(-0.5, 0.5, 0), material(Color("#2f8f83"), 0.5))
	cylinder(root, 0.6, 0.04, Vector3(-0.5, 0.97, 0), material(Color("#ada991"), 0.6))
	cylinder(root, 0.17, 0.9, Vector3(0.75, 0.17, 0.25), material(Color("#ada991"), 0.95), Vector3(0.2, 0, 1))
	cylinder(root, 0.03, 0.5, Vector3(0.82, 0.24, -0.27), material(Color("#8d8a82"), 0.3), Vector3(0.1, 0.25, -1))
	box(root, Vector3(0.12, 0.12, 0.65), Vector3(0.86, 0.33, -0.75), material(Color("#2b2b2b"), 0.6))
	box(root, Vector3(0.6, 0.22, 0.35), Vector3(0.6, 0.11, 0.95), material(Color("#94704b"), 0.8))
	return root

## A square of new floor, two walls already up, and the next square hovering ready to drop.
static func floor_prop() -> Node3D:
	var root := Node3D.new()
	var plaster := material(Color("#ada991"), 0.85)
	box(root, Vector3(2.6, 0.12, 2.6), Vector3(0, 0.06, 0), material(Color("#5a5953"), 1.0))
	box(root, Vector3(2.6, 0.9, 0.1), Vector3(0, 0.57, -1.25), plaster)
	box(root, Vector3(0.1, 0.9, 2.6), Vector3(-1.25, 0.57, 0), plaster)
	var ghost := material(Color(0.25, 0.85, 0.5, 0.45), 0.5, 0.6)
	ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box(root, Vector3(2.6, 0.08, 2.6), Vector3(2.75, 0.9, 0), ghost)
	return root
