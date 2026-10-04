extends Node3D
## The view out of the right-wall window: a cozy alpine valley. The lawn yard with stepping
## stones, soft pines and a wooden fence; a flower meadow falling to a lake; a village with a
## church, pier and boats on the near shore; pine-forested hills; a snow-capped range; and a
## layered skyline of distant ridges in the sky dome (`sky_backdrop.gdshader`).
## The geometry is the static `assets/outdoor-scenery.glb`, authored in Blender
## (`models/outdoor-scenery.blend`, built by `scripts/blender/build_outdoor_scenery.py`) with
## painted vertex colours. This script gives each mesh its material by name and passes the
## day cycle's lighting through `apply`; the workshop lights never touch the outside, and none of
## it collides or takes clicks (built after the picker).
## World units, 1 unit = 0.2 m; +X looks out of the window.

const SKY_SHADER = preload("res://shaders/sky_backdrop.gdshader")
const SCENERY_SHADER = preload("res://shaders/scenery.gdshader")
const WATER_SHADER = preload("res://shaders/water.gdshader")
const SCENE = preload("res://assets/outdoor-scenery.glb")
## Centred on the window; with the first-person far plane at `first_person.FAR` every part of
## the dome seen through the window stays inside the view distance.
const DOME_CENTRE := Vector3(34.0, 0.0, -7.0)
const DOME_RADIUS := 600.0
const YARD_TOP := -4.5
const WATER_Y := -12.6
## Shader settings per mesh: flat-shaded built things, softly wrapped foliage, swaying leaves.
const LOOKS := {
	"Terrain": {"wrap": 0.15},
	"Forest": {"wrap": 0.3},
	"Foliage": {"wrap": 0.45, "wind_strength": 0.13},
	"Flowers": {"facet_strength": 1.0, "wind_strength": 0.04, "wrap": 0.5},
	"YardBark": {"wrap": 0.2},
	"YardStones": {"facet_strength": 1.0},
	"Fence": {"facet_strength": 1.0},
	"VillageWalls": {"facet_strength": 1.0},
	"VillageRoofs": {"facet_strength": 1.0},
	"Pier": {"facet_strength": 1.0},
	"WindowLights": {"facet_strength": 1.0, "glow": 1.0},
}

var sky_material: ShaderMaterial
var materials: Array[ShaderMaterial] = []
var water_material: ShaderMaterial
var dome: MeshInstance3D
var landscape: Node3D
## Meshes by name, for tests and tools.
var meshes := {}

func _ready() -> void:
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	dome = MeshInstance3D.new()
	dome.name = "SkyDome"
	var sphere := SphereMesh.new()
	sphere.radius = DOME_RADIUS
	sphere.height = DOME_RADIUS * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	dome.mesh = sphere
	dome.material_override = sky_material
	dome.position = DOME_CENTRE
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dome)
	landscape = SCENE.instantiate()
	landscape.name = "Landscape"
	add_child(landscape)
	for mesh in landscape.find_children("*", "MeshInstance3D", true, false):
		meshes[String(mesh.name)] = mesh
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh.name == "Lake":
			water_material = ShaderMaterial.new()
			water_material.shader = WATER_SHADER
			mesh.material_override = water_material
			continue
		var material := ShaderMaterial.new()
		material.shader = SCENERY_SHADER
		var look: Dictionary = LOOKS.get(String(mesh.name), {})
		for key in look:
			material.set_shader_parameter(key, look[key])
		mesh.material_override = material
		materials.append(material)

## Lighting for the time of day, from `day_cycle.gd`.
func apply(state: Dictionary) -> void:
	for key in ["sun_dir", "moon_dir", "light_dir", "light_color", "zenith_color", "horizon_color", "haze_color",
			"ambient_color", "night", "sun_visible", "cloud_shift"]:
		sky_material.set_shader_parameter(key, state[key])
	for material in materials:
		for key in ["light_dir", "light_color", "ambient_color", "haze_color", "night"]:
			material.set_shader_parameter(key, state[key])
		material.set_shader_parameter("ground_color", state.ambient_color.darkened(0.55))
	if water_material:
		for key in ["light_dir", "light_color", "ambient_color", "haze_color", "zenith_color", "horizon_color", "night"]:
			water_material.set_shader_parameter(key, state[key])
