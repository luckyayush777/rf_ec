@tool
extends Node3D
## Segmented canvas physically winds around a roll; pockets follow the fabric.
var strips: Array[Node3D] = []
var opening := 0.0
var cloth: StandardMaterial3D
var trim: StandardMaterial3D
var seam: StandardMaterial3D

func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.95
	return result

func box(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	node.mesh = mesh
	parent.add_child(node)
	node.position = at

func _ready() -> void:
	for child in get_children():
		if child.name in ["Screwdriver", "DevBlower", "Lid"]:
			if child.name == "Lid":
				for old in child.get_children():
					child.remove_child(old)
					old.queue_free()
			continue
		remove_child(child)
		child.queue_free()
	cloth = material(Color("#485357"))
	trim = material(Color("#202a2e"))
	seam = material(Color("#b19d71"))
	for i in range(40):
		var strip := Node3D.new()
		add_child(strip)
		strips.append(strip)
		box(strip, Vector3.ZERO, Vector3(0.155, 0.055, 3.3), cloth)
		for z in [-1.61, 1.61]:
			box(strip, Vector3(0, 0.034, z), Vector3(0.15, 0.025, 0.07), trim)
			box(strip, Vector3(0, 0.051, z), Vector3(0.085, 0.009, 0.012), seam)
	for i in range(6):
		var strip: Node3D = strips[3 + i * 6]
		box(strip, Vector3(0, 0.11, 0.52), Vector3(0.76, 0.16, 1.45), trim)
		box(strip, Vector3(0, 0.2, 0.55), Vector3(0.72, 0.045, 1.34), cloth)
		box(strip, Vector3(0, 0.21, -0.2), Vector3(0.70, 0.025, 0.065), trim)
		for x in [-0.34, 0.34]:
			for z in range(9):
				box(strip, Vector3(x, 0.228, -0.05 + z * 0.14), Vector3(0.015, 0.008, 0.065), seam)
		# Retaining webbing and empty, dark pocket mouths remain visible.
		box(strip, Vector3(0, 0.14, -0.8), Vector3(0.72, 0.07, 0.15), trim)
	for index in [9, 30]:
		box(strips[index], Vector3(0, -0.07, 0), Vector3(0.13, 0.06, 3.65), trim)
		box(strips[index], Vector3(0, 0.07, 1.8), Vector3(0.24, 0.12, 0.3), seam)
	$Screwdriver.position = Vector3(-2.475, 0.4, -0.1)
	$Screwdriver.rotation.y = PI / 2
	$Screwdriver.scale = Vector3.ONE * 0.78
	$DevBlower.position = Vector3(-1.575, 0.43, -0.1)
	$DevBlower.rotation.y = PI / 2
	$DevBlower.scale = Vector3.ONE * 0.7
	$Screwdriver.set_meta("roll_home", $Screwdriver.transform)
	$DevBlower.set_meta("roll_home", $DevBlower.transform)
	set_opening(0.0)

func set_opening(value: float) -> void:
	opening = value
	var flat := value * 6.0
	for i in range(strips.size()):
		var length := (i + 0.5) * 0.15
		var angle := maxf(0, length - flat) / 0.56
		var radius := 0.56 + angle * 0.009
		strips[i].position = Vector3(-3 * value + minf(length, flat) + sin(angle) * radius, 0.15 + (1 - cos(angle)) * radius, 0)
		strips[i].rotation.z = angle
	for entry in [["Screwdriver", 0.18], ["DevBlower", 0.33]]:
		var tool := get_node_or_null(NodePath(entry[0])) as Node3D
		if tool != null:
			var open_home: Transform3D = tool.get_meta("roll_home")
			tool.position.x = open_home.origin.x + 3 * (1 - value)
			tool.visible = value > entry[1] and (entry[0] != "DevBlower" or OS.is_debug_build())
