@tool
extends Node3D
## Adapt the meter-scale room around the existing playable desks.
## Prop proportions stay uniform; only the architectural shell is expanded.

## The right wall's window, in world units (1 unit = 0.2 m): three bays over a counter. Parcels
## come in through the hatch in the middle bay's lower part (closed by the roller shutter in
## `delivery_window.gd`); the rest is glazed and looks out over the mountains.
const WALL_X := Vector2(33.0, 33.96)
const WINDOW_Z := Vector2(-16.0, 2.0)
const HATCH_Z := Vector2(-10.0, -4.0)
const SILL_Y := 0.0
const HATCH_TOP := 2.6
const TRANSOM_TOP := 3.0
const WINDOW_TOP := 9.2
const COUNTER_DEPTH := 2.8
const FRAME_COLOR := Color(0.08, 0.22, 0.24)

func _ready() -> void:
	# Godot wraps the authored glTF root in its imported scene root.
	var model := $Model.get_node("shop-interior")
	for group in model.get_children():
		if String(group.name).begins_with("Room"):
			group.scale = Vector3(1.6, 1.0, 1.4)
			if String(group.name).begins_with("Room - hide"): group.visible = false
		else:
			group.position.z = -0.9
	# Keep the aisle furnishings clear of the playable desk footprints.
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var id := String(mesh.name)
		if id.begins_with("stool"):
			mesh.position += Vector3(-3.6, 0, 2.0)
		elif id.begins_with("cart-") or id.begins_with("AWAITING TEST") or id in ["service-manual", "manual-title"]:
			mesh.position += Vector3(1.7, 0, 2.0)

func enclose_room() -> void:
	var shell := $Model.get_node("shop-interior/Room - hide for cutaway (front right ceiling)")
	shell.visible = true
	# Keep the existing broad workshop lighting; the ceiling does not eclipse it.
	var ceiling: GeometryInstance3D = find_child("ceiling", true, false)
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var door := MeshInstance3D.new()
	door.name = "EntranceDoor"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.92, 2.2, 0.035)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = FRAME_COLOR
	mesh.material = paint
	door.mesh = mesh
	add_child(door)
	door.position = Vector3(0.32, 1.1, 3.444)
	# Leaving through the front door ends the day.
	door.set_meta("action", "exit_door")
	var handle := add_block(door, "DoorHandle", Vector3(0.04, 0.32, 0.05), Vector3(0.78, 0.0, -0.04), flat(Color("c9c2b0"), 0.35, 0.8))
	handle.set_meta("action", "exit_door")
	# On the door header, just proud of the wall face.
	var exit_sign := Label3D.new()
	exit_sign.name = "ExitSign"
	exit_sign.text = "EXIT"
	exit_sign.font_size = 96
	exit_sign.pixel_size = 0.0022
	exit_sign.modulate = Color("8fe3a3")
	exit_sign.outline_size = 0
	exit_sign.position = Vector3(0.0, 1.22, -0.1)
	exit_sign.rotation.y = PI
	door.add_child(exit_sign)
	build_window()

## Replaces the solid right wall with wall pieces around the window opening, then frames it:
## counter, hatch reveal, transom, glazing and a mullion. Built in world units under a node
## that cancels this wrapper's 5x scale; everything here gets room collision.
func build_window() -> void:
	var wall: MeshInstance3D = find_child("right-plaster-wall", true, false)
	var plaster: Material = wall.get_active_material(0)
	wall.visible = false
	var root := Node3D.new()
	root.name = "RightWallWindow"
	add_child(root)
	root.global_transform = Transform3D.IDENTITY
	var bounds: AABB = wall.global_transform * wall.get_aabb()
	var x0 := WALL_X.x
	var x1 := WALL_X.y
	var floor_y := bounds.position.y
	var top_y := bounds.end.y
	var z0 := bounds.position.z
	var z1 := bounds.end.z
	piece(root, "WallBelowWindow", Vector3(x0, floor_y, z0), Vector3(x1, SILL_Y, z1), plaster)
	piece(root, "WallAboveWindow", Vector3(x0, WINDOW_TOP, z0), Vector3(x1, top_y, z1), plaster)
	piece(root, "WallBackOfWindow", Vector3(x0, SILL_Y, z0), Vector3(x1, WINDOW_TOP, WINDOW_Z.x), plaster)
	piece(root, "WallFrontOfWindow", Vector3(x0, SILL_Y, WINDOW_Z.y), Vector3(x1, WINDOW_TOP, z1), plaster)
	var frame := flat(FRAME_COLOR, 0.55)
	var wood := flat(Color("b98a5c"), 0.6)
	var t := 0.3
	piece(root, "WindowJambBack", Vector3(x0 - 0.12, SILL_Y, WINDOW_Z.x - 0.05), Vector3(x1, WINDOW_TOP, WINDOW_Z.x + t), frame)
	piece(root, "WindowJambFront", Vector3(x0 - 0.12, SILL_Y, WINDOW_Z.y - t), Vector3(x1, WINDOW_TOP, WINDOW_Z.y + 0.05), frame)
	piece(root, "WindowHead", Vector3(x0 - 0.12, WINDOW_TOP - t, WINDOW_Z.x), Vector3(x1, WINDOW_TOP + 0.05, WINDOW_Z.y), frame)
	piece(root, "Transom", Vector3(x0 - 0.12, HATCH_TOP, WINDOW_Z.x), Vector3(x1 - 0.2, TRANSOM_TOP, WINDOW_Z.y), frame)
	# Mullions on the hatch's sides divide the three bays from sill to head.
	for z in [HATCH_Z.x, HATCH_Z.y]:
		piece(root, "Mullion", Vector3(x0 - 0.12, SILL_Y, z - 0.15), Vector3(x0 + 0.62, WINDOW_TOP, z + 0.15), frame)
	# The counter the parcels slide onto, on three brackets.
	piece(root, "HatchCounter", Vector3(x0 - COUNTER_DEPTH, SILL_Y - 0.3, WINDOW_Z.x - 0.4), Vector3(x1 - 0.1, SILL_Y, WINDOW_Z.y + 0.4), wood)
	for z in [WINDOW_Z.x + 1.2, (HATCH_Z.x + HATCH_Z.y) * 0.5, WINDOW_Z.y - 1.2]:
		piece(root, "CounterBracket", Vector3(x0 - 1.6, SILL_Y - 1.6, z - 0.12), Vector3(x0, SILL_Y - 0.3, z + 0.12), frame)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.78, 0.9, 0.92, 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic_specular = 0.8
	# Upper glazing across all three bays; lower panes beside the hatch.
	var panes: Array[MeshInstance3D] = [
		piece(root, "WindowGlass", Vector3(x0 + 0.44, TRANSOM_TOP, WINDOW_Z.x), Vector3(x0 + 0.48, WINDOW_TOP - t, WINDOW_Z.y), glass),
		piece(root, "LowerGlassBack", Vector3(x0 + 0.44, SILL_Y, WINDOW_Z.x), Vector3(x0 + 0.48, HATCH_TOP, HATCH_Z.x), glass),
		piece(root, "LowerGlassFront", Vector3(x0 + 0.44, SILL_Y, HATCH_Z.y), Vector3(x0 + 0.48, HATCH_TOP, WINDOW_Z.y), glass)]
	for pane in panes: pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var label := Label3D.new()
	label.name = "DeliveriesSign"
	label.text = "DELIVERIES"
	label.font_size = 96
	label.pixel_size = 0.009
	label.modulate = FRAME_COLOR
	label.outline_size = 0
	label.position = Vector3(x0 - 0.02, (WINDOW_TOP + 10.5) * 0.5, (HATCH_Z.x + HATCH_Z.y) * 0.5)
	label.rotation.y = -PI * 0.5
	root.add_child(label)

func piece(parent: Node3D, piece_name: String, from: Vector3, to: Vector3, material: Material) -> MeshInstance3D:
	return add_block(parent, piece_name, to - from, (from + to) * 0.5, material)

func add_block(parent: Node3D, block_name: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = block_name
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	node.mesh = box
	node.position = at
	parent.add_child(node)
	return node

static func flat(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material
