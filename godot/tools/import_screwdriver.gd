extends SceneTree
## Bake the Blender tool study into a native scene with the established direct part paths.
func _initialize() -> void:
	var imported: Node3D = load("res://assets/screwdriver.glb").instantiate()
	var tool: Node3D = imported.get_node("Screwdriver")
	imported.remove_child(tool)
	imported.free()
	for part in tool.find_children("*", "", true, false):
		part.owner = tool
		if part is MeshInstance3D:
			# Bundle geometry; a native scene never refers into the editor import cache.
			part.mesh = part.mesh.duplicate(true)
	var scene := PackedScene.new()
	var result := scene.pack(tool)
	if result == OK:
		result = ResourceSaver.save(scene, "res://scenes/screwdriver.tscn", ResourceSaver.FLAG_BUNDLE_RESOURCES)
	tool.free()
	if result != OK: push_error("Screwdriver scene bake failed: %s" % result)
	else: print("Screwdriver native scene baked with direct Grip/Collar/Shaft/Tip paths")
	quit(0 if result == OK else 1)
