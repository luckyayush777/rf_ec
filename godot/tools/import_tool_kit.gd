extends SceneTree
## Bake rounded geometry into native scenes; retain labels and the thermal LCD's native UV quad.
const SCENES := {"AirBlower": "air_blower", "DevBlower": "dev_blower", "Spudger": "spudger",
	"IpaWipe": "ipa_wipe", "PasteSyringe": "paste_syringe", "FanOiler": "fan_oiler",
	"Loupe": "loupe", "ThermalCamera": "thermal_camera", "WorkTools": "work_tool_shapes"}
func _initialize() -> void:
	var imported: Node3D = load("res://assets/tool-kit.glb").instantiate()
	var bag: Node3D = load("res://scenes/toolbox.tscn").instantiate()
	var camera: Node3D = load("res://scenes/thermal_camera.tscn").instantiate()
	var errors := 0
	for id in SCENES:
		var tool := imported.find_child(id, true, false) as Node3D
		if tool == null:
			push_error("Tool kit missing " + id)
			errors += 1
			continue
		tool.get_parent().remove_child(tool)
		tool.transform = Transform3D.IDENTITY
		for part in tool.find_children("*", "", true, false):
			part.name = str(part.name).trim_prefix(id + "__")
			part.owner = tool
			if part is MeshInstance3D: part.mesh = part.mesh.duplicate(true)
		var original: Node3D = camera if id == "ThermalCamera" else bag.get_node_or_null(id)
		if original != null:
			for part in original.get_children():
				if part is Label3D or (id == "ThermalCamera" and part.name == "Display"):
					var copy := part.duplicate()
					tool.add_child(copy)
					copy.owner = tool
		var scene := PackedScene.new()
		var result := scene.pack(tool)
		if result == OK: result = ResourceSaver.save(scene, "res://scenes/" + SCENES[id] + ".tscn", ResourceSaver.FLAG_BUNDLE_RESOURCES)
		if result != OK:
			push_error("Tool bake failed: " + id)
			errors += 1
		tool.free()
	imported.free()
	bag.free()
	camera.free()
	print("TOOL_KIT_BAKE_PASS" if errors == 0 else "TOOL_KIT_BAKE_FAIL")
	quit(0 if errors == 0 else 1)
