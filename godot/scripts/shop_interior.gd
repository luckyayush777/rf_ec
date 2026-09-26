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
