extends Node3D
## The mountain view out of the right-wall window: a yard with a stone parapet on the edge of
## a mountain valley somewhere in central China. Pines, shrubs, yard and parapet form the foreground;
## connected mountain slopes with sculpted rock shelves and gullies form two overlapping ranges. The distant ridgelines
## and sky are drawn by direction inside a sky dome (`sky_backdrop.gdshader`). All outdoor
## materials are lit by `day_cycle.gd` through `apply`, not by
## the workshop lights, and none of it collides or takes clicks (built after the picker).
## World units, 1 unit = 0.2 m; +X looks out of the window.

const SKY_SHADER = preload("res://shaders/sky_backdrop.gdshader")
const SCENERY_SHADER = preload("res://shaders/scenery.gdshader")
const Vegetation = preload("res://scripts/outdoor_vegetation.gd")
## Centred on the window; with the first-person far plane at `first_person.FAR` every part of
## the dome seen through the window stays inside the view distance.
const DOME_CENTRE := Vector3(34.0, 0.0, -7.0)
const DOME_RADIUS := 230.0
const YARD_TOP := -4.5
const YARD_EDGE := 76.0
const GRASS := Color("5f8a62")
const PATH := Color("d8ccb0")
const STONE := Color("cdbf9f")
const ROCK := Color("b8ab92")
const MOUNTAIN_ROCK := Color("b2b4a7")
const MOUNTAIN_GREEN := Color("526e64")
## Authored skyline stations (azimuth in radians, elevation above the horizon). Wide shoulders,
## secondary summits and deep saddles describe connected mountains rather than isolated cones.
const BACK_RIDGE := [
	Vector2(-1.65, 0.12), Vector2(-1.45, 0.22), Vector2(-1.29, 0.18),
	Vector2(-1.12, 0.33), Vector2(-0.98, 0.24), Vector2(-0.85, 0.28),
	Vector2(-0.68, 0.17), Vector2(-0.52, 0.23), Vector2(-0.36, 0.15),
	Vector2(-0.23, 0.12), Vector2(-0.06, 0.055), Vector2(0.10, 0.10),
	Vector2(0.24, 0.27), Vector2(0.34, 0.21), Vector2(0.48, 0.32),
	Vector2(0.60, 0.24), Vector2(0.77, 0.38), Vector2(0.90, 0.29),
	Vector2(1.05, 0.33), Vector2(1.22, 0.17), Vector2(1.42, 0.23), Vector2(1.65, 0.12)]
const FRONT_RIDGE := [
	Vector2(-1.65, 0.18), Vector2(-1.44, 0.28), Vector2(-1.27, 0.21),
	Vector2(-1.10, 0.43), Vector2(-0.99, 0.35), Vector2(-0.89, 0.40),
	Vector2(-0.73, 0.26), Vector2(-0.60, 0.32), Vector2(-0.49, 0.29),
	Vector2(-0.43, 0.38), Vector2(-0.38, 0.35), Vector2(-0.30, 0.23),
	Vector2(-0.24, 0.20), Vector2(-0.16, 0.025), Vector2(0.03, -0.08),
	Vector2(0.20, 0.015), Vector2(0.30, 0.19), Vector2(0.35, 0.18),
	Vector2(0.45, 0.37), Vector2(0.50, 0.34), Vector2(0.56, 0.25),
	Vector2(0.70, 0.35), Vector2(0.83, 0.27),
	Vector2(0.96, 0.31), Vector2(1.13, 0.22), Vector2(1.26, 0.36),
	Vector2(1.43, 0.24), Vector2(1.65, 0.17)]

var sky_material: ShaderMaterial
var scenery_material: ShaderMaterial
var mountain_materials: Array[ShaderMaterial] = []
var dome: MeshInstance3D
var near: MeshInstance3D
var vegetation: Node3D
var rng := RandomNumberGenerator.new()
var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()

func _ready() -> void:
	rng.seed = 1949
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	dome = MeshInstance3D.new()
	dome.name = "SkyDome"
	var sphere := SphereMesh.new()
	sphere.radius = DOME_RADIUS
	sphere.height = DOME_RADIUS * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	dome.mesh = sphere
	dome.material_override = sky_material
	dome.position = DOME_CENTRE
	add_child(dome)
	scenery_material = ShaderMaterial.new()
	scenery_material.shader = SCENERY_SHADER
	build_yard()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	near = MeshInstance3D.new()
	near.name = "NearScenery"
	near.mesh = mesh
	near.material_override = scenery_material
	add_child(near)
	for node in [dome, near]:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	build_range("BackMountains", BACK_RIDGE, 195.0, 0.62)
	build_range("FrontMountains", FRONT_RIDGE, 139.0, 0.28)
	vegetation = Vegetation.new()
	vegetation.name = "Vegetation"
	add_child(vegetation)
	vegetation.build(get_node("FrontMountains"), get_node("BackMountains"))

## Lighting for the time of day, from `day_cycle.gd`.
func apply(state: Dictionary) -> void:
	for key in ["sun_dir", "moon_dir", "light_dir", "light_color", "zenith_color", "horizon_color", "haze_color",
			"ambient_color", "night", "sun_visible", "cloud_shift"]:
		sky_material.set_shader_parameter(key, state[key])
	for material in [scenery_material] + mountain_materials + vegetation.materials:
		for key in ["light_dir", "light_color", "ambient_color", "haze_color"]:
			material.set_shader_parameter(key, state[key])
		material.set_shader_parameter("ground_color", state.ambient_color.darkened(0.55))
	# Cooler atmospheric colour separates the rear range from the foreground rock faces.
	mountain_materials[0].set_shader_parameter("haze_color", state.haze_color.lerp(state.zenith_color, 0.25))

func build_yard() -> void:
	# The yard runs from the shop wall to the parapet on the valley edge.
	box(Vector3(34.0, YARD_TOP - 3.0, -70.0), Vector3(YARD_EDGE + 2.0, YARD_TOP, 56.0), GRASS)
	# Stepping stones from the hatch toward the parapet.
	for index in range(7):
		var at := Vector3(38.0 + index * 5.2, YARD_TOP, -7.0 + sin(index * 1.3) * 2.2)
		cylinder(at, 1.5 + rng.randf() * 0.5, 0.18, PATH, 9)
	# Parapet blocks with a cap rail and a gap where a path once went down.
	var z := -70.0
	while z < 56.0:
		if absf(z + 2.0) > 4.0:
			box(Vector3(YARD_EDGE - 1.2, YARD_TOP, z + 0.15), Vector3(YARD_EDGE + 1.2, YARD_TOP + 2.2, z + 5.85), STONE)
			box(Vector3(YARD_EDGE - 1.5, YARD_TOP + 2.2, z), Vector3(YARD_EDGE + 1.5, YARD_TOP + 2.7, z + 6.0), STONE.lightened(0.08))
		z += 6.0
	for index in range(6):
		var at := Vector3(rng.randf_range(42.0, 72.0), YARD_TOP, rng.randf_range(-55.0, 40.0))
		if absf(at.z + 7.0) < 6.0: continue
		var size := rng.randf_range(1.2, 2.6)
		ellipsoid(at + Vector3(0, size * 0.35, 0), Vector3(size * 1.3, size * 0.75, size), ROCK, 10, 6)

## Detailed stylized terrain: authored major peaks, sculpted ribs/gullies, broad rock shelves
## and branching buttresses. The front/back ranges together use 321,408 indexed triangles;
## the active GPU reference has 131,404. Smooth normals soften the geometry like the rounded GPU art;
## material colour remains broad and texture-free. Distant silhouettes need no extra geometry.
func build_range(label: String, skyline: Array, distance: float, haze: float) -> void:
	var front := label == "FrontMountains"
	var subdivisions := 32 if front else 18
	var rows := 144 if front else 96
	var columns := (skyline.size() - 1) * subdivisions
	var crest_row := rows * 3 / 4
	var relief := FastNoiseLite.new()
	relief.seed = 7301 if front else 9157
	relief.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	relief.fractal_type = FastNoiseLite.FRACTAL_NONE
	relief.frequency = 1.0
	# Secondary spurs branch from major summits and merge into the existing terrain. Their
	# crests, broad shoulders and shallow shelves give each massif readable substructure.
	var spurs: Array[Vector4] = []
	for station in range(1, skyline.size() - 1):
		var peak: Vector2 = skyline[station]
		if peak.y < 0.18 or peak.y < skyline[station - 1].y or peak.y < skyline[station + 1].y: continue
		for branch in range(2):
			var side := -1.0 if branch == 0 else 1.0
			var centre := peak.x * distance + side * (6.0 + 2.0 * sin(station))
			var depth := 0.76 + branch * 0.09 + 0.012 * sin(station * 2.0)
			spurs.append(Vector4(centre, depth, 8.0 + 1.8 * cos(station + branch), 6.0 + peak.y * 9.0))
	var mountain_vertices := PackedVector3Array()
	mountain_vertices.resize((rows + 1) * (columns + 1))
	for row in range(rows + 1):
		var depth := lerpf(0.48, 1.0, float(row) / crest_row) if row <= crest_row else lerpf(1.0, 1.15, float(row - crest_row) / (rows - crest_row))
		for column in range(columns + 1):
			var segment := mini(column / subdivisions, skyline.size() - 2)
			var t := float(column - segment * subdivisions) / subdivisions
			var before: Vector2 = skyline[maxi(segment - 1, 0)]
			var a: Vector2 = skyline[segment]
			var b: Vector2 = skyline[segment + 1]
			var after: Vector2 = skyline[mini(segment + 2, skyline.size() - 1)]
			var azimuth := lerpf(a.x, b.x, t)
			# Rounded but asymmetric summit transitions, with small notches in the skyline.
			var elevation := lerpf(lerpf(a.y, b.y, t), cubic_interpolate(a.y, b.y, before.y, after.y, t), 0.12)
			elevation = clampf(elevation, minf(a.y, b.y) - 0.015, maxf(a.y, b.y) + 0.015)
			var station := float(segment) + t
			var crest_distance := distance + 9.0 * sin(station * 1.7) + 5.0 * cos(station * 0.8)
			var summit_breaks := relief.get_noise_2d(azimuth * distance * 0.42, 83.0)
			var crest_height := tan(elevation) * crest_distance + 2.0 + summit_breaks * 1.2 * sin(t * PI)
			var height := mountain_profile(depth, crest_height)
			var radius := crest_distance * depth
			var across := azimuth * distance
			var buttress := spur_height(across, depth, spurs)
			height += buttress
			radius -= buttress * 0.05
			# Broad spurs carry from the skyline down the face, interrupted by narrow ravines.
			var front_slope := smoothstep(0.48, 0.66, depth) * (1.0 - smoothstep(1.0, 1.15, depth))
			var summit := smoothstep(0.86, 1.0, depth)
			var broad := relief.get_noise_2d(across * 0.085, depth * 9.0)
			var broken := relief.get_noise_2d(across * 0.24 + 19.0, depth * 26.0)
			var ribs := sin(across * 0.44 + 1.6 * sin(across * 0.095) + depth * 2.8)
			var gully := pow(maxf(0.0, ribs), 5.0)
			height += front_slope * (broad * 4.0 + broken * 0.8 - gully * 2.0 * (1.0 - summit * 0.7))
			radius += front_slope * (broad * 0.35 - gully * 0.20)
			# Shallow rounded strata make ledges in the actual surface, rather than painted lines.
			var strata_height := height + 2.4 * sin(across * 0.06) + broad * 1.8
			var strata := floorf(strata_height / 8.0) * 8.0 + smoothstep(0.22, 0.78, fposmod(strata_height / 8.0, 1.0)) * 8.0
			var shelf_region := smoothstep(-0.1, 0.4, relief.get_noise_2d(across * 0.045, depth * 6.0 + 51.0))
			height += (strata - strata_height) * 0.32 * shelf_region * front_slope * (1.0 - summit * 0.75)
			# Scale the whole radial strip to fit the dome. Clamping each point separately
			# pinched the back slopes into folds; constant strip scaling preserves topology.
			var height_bound := maxf(65.0, crest_height + 20.0)
			var radius_bound := sqrt(pow(DOME_RADIUS - 5.0, 2.0) - height_bound * height_bound)
			radius *= minf(1.0, radius_bound / (crest_distance * 1.15 + 2.0))
			mountain_vertices[row * (columns + 1) + column] = Vector3(DOME_CENTRE.x + cos(azimuth) * radius, height, DOME_CENTRE.z + sin(azimuth) * radius)
	var mountain_normals := PackedVector3Array()
	var mountain_colors := PackedColorArray()
	mountain_normals.resize(mountain_vertices.size())
	mountain_colors.resize(mountain_vertices.size())
	for row in range(rows + 1):
		for column in range(columns + 1):
			var index := row * (columns + 1) + column
			var across := mountain_vertices[row * (columns + 1) + mini(column + 1, columns)] - mountain_vertices[row * (columns + 1) + maxi(column - 1, 0)]
			var along := mountain_vertices[mini(row + 1, rows) * (columns + 1) + column] - mountain_vertices[maxi(row - 1, 0) * (columns + 1) + column]
			var normal := across.cross(along).normalized()
			if normal.y < 0.0: normal = -normal
			mountain_normals[index] = normal
			var at := mountain_vertices[index]
			var patch := relief.get_noise_2d(at.x * 0.06, at.z * 0.06)
			var bare := (0.55 + (1.0 - smoothstep(0.45, 0.90, normal.y)) * 0.4) * smoothstep(-38.0, 6.0, at.y) + patch * 0.12
			var color := MOUNTAIN_GREEN.lerp(MOUNTAIN_ROCK, clampf(bare, 0.0, 1.0))
			# Large coherent colour regions; no random colour per triangle or photographic grain.
			color = color.lightened(patch * 0.065)
			mountain_colors[index] = color.srgb_to_linear()
	var mountain_indices := PackedInt32Array()
	mountain_indices.resize(rows * columns * 6)
	var cursor := 0
	for row in range(rows):
		for column in range(columns):
			var a := row * (columns + 1) + column
			var b := a + 1
			var c := a + columns + 1
			var d := c + 1
			var face_indices := [a, b, c, b, d, c] if (row + column) % 2 == 0 else [a, b, d, a, d, c]
			for index in face_indices:
				mountain_indices[cursor] = index
				cursor += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mountain_vertices
	arrays[Mesh.ARRAY_NORMAL] = mountain_normals
	arrays[Mesh.ARRAY_COLOR] = mountain_colors
	arrays[Mesh.ARRAY_INDEX] = mountain_indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = SCENERY_SHADER
	material.set_shader_parameter("detail_strength", 0.0)
	material.set_shader_parameter("facet_strength", 0.22)
	material.set_shader_parameter("haze_distance", 175.0 if not front else 600.0)
	material.set_shader_parameter("haze_amount", haze)
	material.set_shader_parameter("valley_mist", 0.5)
	mountain_materials.append(material)
	var mountain := MeshInstance3D.new()
	mountain.name = label
	mountain.mesh = mesh
	mountain.material_override = material
	mountain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mountain)

## Connected subsidiary ridges, not freestanding columns. A diamond footprint gives each
## ridge a narrow crest and broad sloping shoulders; small bevels soften its planar sides.
func spur_height(across: float, depth: float, spurs: Array[Vector4]) -> float:
	var result := 0.0
	for spur in spurs:
		var along := (depth - spur.y) / 0.145
		if absf(along) >= 1.0: continue
		var sideways := (across - spur.x - along * 2.5) / spur.z
		var edge := pow(absf(sideways), 1.35) + absf(along) * 0.45
		if edge >= 1.0: continue
		var crest := 1.0 - edge
		crest = lerpf(crest, smoothstep(0.0, 1.0, crest), 0.4)
		var end := 1.0 - smoothstep(0.4, 1.0, absf(along))
		result = maxf(result, crest * end * spur.w)
	return result

## Broad mountain mass underneath the erosion, with convex shoulders and a steep upper face.
func mountain_profile(depth: float, crest_height: float) -> float:
	var keys := [Vector2(0.48, -65.0), Vector2(0.62, lerpf(-45.0, crest_height, 0.12)),
		Vector2(0.76, lerpf(-32.0, crest_height, 0.37)), Vector2(0.90, lerpf(-14.0, crest_height, 0.72)),
		Vector2(1.0, crest_height), Vector2(1.06, lerpf(-25.0, crest_height, 0.68)), Vector2(1.15, -50.0)]
	for index in range(keys.size() - 1):
		var a: Vector2 = keys[index]
		var b: Vector2 = keys[index + 1]
		if depth > b.x: continue
		var before: Vector2 = keys[maxi(index - 1, 0)]
		var after: Vector2 = keys[mini(index + 2, keys.size() - 1)]
		var t := clampf((depth - a.x) / (b.x - a.x), 0.0, 1.0)
		return lerpf(lerpf(a.y, b.y, t), cubic_interpolate(a.y, b.y, before.y, after.y, t), 0.18)
	return -50.0

# --- Primitive helpers: append a transformed primitive with one colour -----------------------

func append(mesh: PrimitiveMesh, placement: Transform3D, color: Color) -> void:
	var arrays := mesh.get_mesh_arrays()
	var first := vertices.size()
	var linear := color.srgb_to_linear()
	for vertex in arrays[Mesh.ARRAY_VERTEX]: vertices.append(placement * vertex)
	for normal in arrays[Mesh.ARRAY_NORMAL]: normals.append((placement.basis.inverse().transposed() * normal).normalized())
	for index in range(arrays[Mesh.ARRAY_VERTEX].size()): colors.append(linear)
	for index in arrays[Mesh.ARRAY_INDEX]: indices.append(first + index)

func box(from: Vector3, to: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = to - from
	append(mesh, Transform3D(Basis.IDENTITY, (from + to) * 0.5), color)

func cylinder(at: Vector3, radius: float, height: float, color: Color, segments := 12) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	append(mesh, Transform3D(Basis.IDENTITY, at + Vector3(0, height * 0.5, 0)), color)

func ellipsoid(centre: Vector3, radii: Vector3, color: Color, segments := 12, rings := 6) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = segments
	mesh.rings = rings
	append(mesh, Transform3D(Basis.from_scale(radii), centre), color)
