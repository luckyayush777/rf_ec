extends Node3D
## Stylized windswept pines and clustered shrubs. Geometry is merged into two meshes;
## mountain roots are sampled from actual terrain vertices and restricted to gentler ledges.
## Created after the picker by OutdoorScenery; no collision or interaction targets.
const SHADER = preload("res://shaders/scenery.gdshader")
const BARK := Color("725441")
const NEEDLES := Color("427864")
const TIPS := Color("86a078")
const SHRUB := Color("66834f")
const YARD_Y := -4.5

var materials: Array[ShaderMaterial] = []
var tree_roots: Array[Vector3] = []
var shrub_roots: Array[Vector3] = []
var ledge_roots: Array[Vector3] = []
var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
var rng := RandomNumberGenerator.new()

func build(front: MeshInstance3D, back: MeshInstance3D) -> void:
	rng.seed = 8507
	# Taller crowns frame the sides. Nothing tall grows in the path/central valley sightline.
	for spot in [Vector4(57, -21, 15.0, 0.55), Vector4(68, 11, 15.0, -0.7),
		Vector4(71, -45, 11.0, 0.25), Vector4(48, 36, 9.0, -0.3), Vector4(76, 41, 11.5, -0.55)]:
		var root := Vector3(spot.x, YARD_Y, spot.y)
		tree_roots.append(root)
		pine(root, spot.z, spot.w, true)
	# Shrubs gather in loose groups, leaving the stepping stones and parapet opening clear.
	for cluster in [Vector3(46, 0, -23), Vector3(62, 0, -29), Vector3(71, 0, -20),
		Vector3(49, 0, 8), Vector3(64, 0, 14), Vector3(74, 0, 21), Vector3(74, 0, 37),
		Vector3(43, 0, -47), Vector3(62, 0, -48)]:
		for plant in range(3):
			var at := Vector3(cluster.x + rng.randf_range(-2.5, 2.5), YARD_Y,
				cluster.z + rng.randf_range(-3.0, 3.0))
			shrub_roots.append(at)
			shrub(at, rng.randf_range(1.0, 2.0), true)
	finish_mesh("YardPlants", 0.13, 450.0)
	# Roots are vertices of the final displaced terrain, not guesses from its ideal profile.
	scatter_ledge_plants(front, 55, 3.3)
	scatter_ledge_plants(back, 28, 2.4)
	finish_mesh("CliffPlants", 0.06, 190.0)

func scatter_ledge_plants(terrain: MeshInstance3D, count: int, height: float) -> void:
	var arrays := terrain.mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var slopes: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var placed := 0
	for attempt in range(count * 250):
		if placed == count: break
		var index := rng.randi_range(0, points.size() - 1)
		var at := points[index]
		# Keep exposed cliffs bare and leave room for a crown inside the sky dome.
		if slopes[index].y < 0.72 or at.y < -24.0 or at.y > 55.0: continue
		if at.distance_to(Vector3(34, 0, -7)) > 211.0: continue
		if ledge_roots.any(func(other): return other.distance_to(at) < 5.0): continue
		ledge_roots.append(at)
		if placed % 3 == 0:
			pine(at - Vector3(0, 0.2, 0), height * rng.randf_range(0.8, 1.4), rng.randf_range(-0.5, 0.5), false)
		else:
			shrub(at - Vector3(0, 0.15, 0), height * rng.randf_range(0.24, 0.40), false)
		placed += 1

func pine(at: Vector3, height: float, lean: float, detailed: bool) -> void:
	var segments := 12 if detailed else 8
	var bend := Vector3(0.18, 0, lean * 0.10) * height
	var trunk := [at, at + Vector3(0, height * 0.32, 0) + bend * 0.2,
		at + Vector3(0, height * 0.66, 0) + bend * 0.6,
		at + Vector3(0, height * 0.91, 0) + bend]
	for part in range(3):
		branch(trunk[part], trunk[part + 1], height * (0.030 - part * 0.008),
			height * (0.022 - part * 0.008), BARK, segments)
	# Root flare and a couple of bare lower branches make the trunk readable below the crown.
	if detailed:
		for root in range(5):
			var direction := Vector3(cos(root * TAU / 5.0), 0, sin(root * TAU / 5.0))
			branch(at + direction * height * 0.085, at + Vector3(0, height * 0.12, 0), height * 0.014, height * 0.027, BARK, 8)
	var tiers := 5 if detailed else 3
	for tier in range(tiers):
		var fraction := lerpf(0.40, 0.90, float(tier) / (tiers - 1))
		var origin := at + Vector3(0, height * fraction, 0) + bend * fraction * fraction
		var arms := 3 if detailed else 2
		for arm in range(arms):
			var angle := tier * 1.73 + arm * TAU / arms + rng.randf_range(-0.20, 0.20)
			var reach := height * lerpf(0.26, 0.11, float(tier) / (tiers - 1)) * rng.randf_range(0.8, 1.1)
			var direction := Vector3(cos(angle), 0, sin(angle))
			var elbow := origin + direction * reach * 0.45 + Vector3(0, height * 0.035, 0)
			var tip := origin + direction * reach + Vector3(0, height * rng.randf_range(0.045, 0.085), 0)
			branch(origin, elbow, height * 0.013, height * 0.008, BARK, segments)
			branch(elbow, tip, height * 0.008, height * 0.003, BARK, segments)
			# Several uneven tuft volumes form one broad, flatter pine foliage pad.
			var lobes := 6 if detailed else 3
			for lobe in range(lobes):
				var spread := height * (0.073 - tier * 0.008)
				var centre := tip + Vector3(rng.randf_range(-spread, spread), rng.randf_range(-spread * 0.2, spread * 0.3), rng.randf_range(-spread, spread))
				var color := NEEDLES.lerp(TIPS, 0.13 + float(tier) * 0.10 + rng.randf_range(0.0, 0.12))
				foliage(centre, Vector3(spread * 1.3, spread * 0.47, spread), color, detailed)
	foliage(trunk[-1] + Vector3(0, height * 0.045, 0), Vector3(height * 0.08, height * 0.055, height * 0.08), TIPS, detailed)

func shrub(at: Vector3, size: float, detailed: bool) -> void:
	var lobes := 7 if detailed else 4
	for lobe in range(lobes):
		var angle := lobe * 2.4
		var spread := size * rng.randf_range(0.3, 0.8)
		var centre := at + Vector3(cos(angle) * spread, size * rng.randf_range(0.4, 0.8), sin(angle) * spread)
		branch(at, centre, size * 0.045, size * 0.015, BARK, 6)
		var radius := size * rng.randf_range(0.45, 0.75)
		foliage(centre, Vector3(radius, radius * 0.72, radius), SHRUB.lerp(TIPS, rng.randf_range(0, 0.35)), detailed)

## Lobed needle clusters with shaped edges, not stacked spheres or flat image cards.
func foliage(at: Vector3, radii: Vector3, color: Color, detailed: bool) -> void:
	var segments := 18 if detailed else 10
	var rings := 10 if detailed else 6
	var phase := rng.randf() * TAU
	var first := vertices.size()
	for ring in range(rings + 1):
		var latitude := PI * float(ring) / rings
		for segment in range(segments):
			var angle := TAU * float(segment) / segments
			var lobe := 1.0 + (0.12 * sin(angle * 5.0 + phase) + 0.07 * sin(angle * 9.0 - latitude * 4.0 + phase)) * sin(latitude)
			var direction := Vector3(sin(latitude) * cos(angle), cos(latitude), sin(latitude) * sin(angle))
			vertices.append(at + direction * radii * lobe)
			normals.append((direction / radii).normalized())
			var shade := color.darkened((1.0 - direction.y) * 0.09)
			shade.a = 1.0 # shader wind weight; bark stays fixed
			colors.append(shade.srgb_to_linear())
	for ring in range(rings):
		for segment in range(segments):
			var a := first + ring * segments + segment
			var b := first + ring * segments + (segment + 1) % segments
			indices.append_array([a, b, a + segments, b, b + segments, a + segments])

func branch(from: Vector3, to: Vector3, bottom: float, top: float, color: Color, segments: int) -> void:
	var axis := (to - from).normalized()
	var tangent := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var bitangent := axis.cross(tangent)
	var first := vertices.size()
	for ring in range(4):
		var t := float(ring) / 3.0
		for segment in range(segments):
			var angle := TAU * float(segment) / segments
			var normal := tangent * cos(angle) + bitangent * sin(angle)
			vertices.append(from.lerp(to, t) + normal * lerpf(bottom, top, t))
			normals.append(normal)
			var shade := color.lightened(0.035 * sin(angle * 3.0))
			shade.a = 0.0
			colors.append(shade.srgb_to_linear())
	for ring in range(3):
		for segment in range(segments):
			var a := first + ring * segments + segment
			var b := first + ring * segments + (segment + 1) % segments
			indices.append_array([a, b, a + segments, b, b + segments, a + segments])

func finish_mesh(label: String, wind: float, haze_distance: float) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("detail_strength", 0.0)
	material.set_shader_parameter("wind_strength", wind)
	material.set_shader_parameter("haze_distance", haze_distance)
	material.set_shader_parameter("haze_amount", 0.40 if label == "YardPlants" else 0.60)
	materials.append(material)
	var plants := MeshInstance3D.new()
	plants.name = label
	plants.mesh = mesh
	plants.material_override = material
	plants.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plants)
	vertices = PackedVector3Array()
	normals = PackedVector3Array()
	colors = PackedColorArray()
	indices = PackedInt32Array()
