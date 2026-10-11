extends Node3D
## The neighbourhood map on a wall screen: a slim bezel hung on the short stretch of the
## window wall between the window and the front corner, where expansions never reach. Bought
## from the PC shop's Workshop page; until then it stays hidden. It only shows the map
## (neighbourhood_map.gd) and takes no clicks.
const UI = preload("res://scripts/screen_ui.gd")
const NeighbourhoodMap = preload("res://scripts/neighbourhood_map.gd")
const PAGE_SIZE := Vector2i(960, 540)
## World units (5 per metre): the screen is 1.12 x 0.63 m, centred about 1.55 m up the wall.
const SCREEN_SIZE := Vector2(5.6, 3.15)
const WALL_POINT := Vector3(33.0, 3.25, 5.9)

var screen: MeshInstance3D
var viewport: SubViewport
var map: Control

func _ready() -> void:
	# Facing into the room (-X), the page's right edge toward the front wall (+Z).
	position = WALL_POINT
	rotation.y = -PI * 0.5
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color("#1d2427")
	shell.roughness = 0.6
	add_box("Bezel", Vector3(SCREEN_SIZE.x + 0.3, SCREEN_SIZE.y + 0.3, 0.14), Vector3(0, 0, 0.07), shell)
	add_box("WallBracket", Vector3(1.4, 0.9, 0.06), Vector3(0, 0, 0.0), shell)
	var caption := Label3D.new()
	caption.name = "Caption"
	caption.text = "NEIGHBOURHOOD"
	caption.pixel_size = 0.004
	caption.font_size = 24
	caption.outline_size = 0
	caption.modulate = Color("#8fa0a6")
	caption.position = Vector3(0, -SCREEN_SIZE.y * 0.5 - 0.08, 0.145)
	add_child(caption)
	screen = MeshInstance3D.new()
	screen.name = "Screen"
	var quad := QuadMesh.new()
	quad.size = SCREEN_SIZE
	screen.mesh = quad
	screen.position = Vector3(0, 0, 0.145)
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(screen)
	viewport = UI.attach_viewport(screen, PAGE_SIZE)
	map = NeighbourhoodMap.new()
	map.name = "NeighbourhoodMap"
	map.size = PAGE_SIZE
	viewport.add_child(map)
	hide()

func add_box(piece_name: String, box_size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var node := MeshInstance3D.new()
	node.name = piece_name
	node.mesh = mesh
	node.material_override = material
	node.position = at
	add_child(node)

func configure(repair_jobs: Node) -> void:
	map.configure(repair_jobs)
