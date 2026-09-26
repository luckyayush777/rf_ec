@tool
extends Node3D
## Adapt the meter-scale room around the existing playable desks.
## Prop proportions stay uniform; only the architectural shell is expanded.

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
	paint.albedo_color = Color(0.08, 0.22, 0.24)
	mesh.material = paint
	door.mesh = mesh
	add_child(door)
	door.position = Vector3(0.32, 1.1, 3.444)
