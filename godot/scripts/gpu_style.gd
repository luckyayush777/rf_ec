extends Node
## Shared brand identity for the card, its retail packaging and the job listing.
const BRANDS := ["Lotac", "Vsus", "CSI"]
const PALETTES := {
	"Lotac": {"board": "397b78", "edge": "205856", "shell": "f0dfbc", "rotor": "306772", "accent": "e79a48", "chip": "294452", "capacitor": "527f91", "metal": "b7cdd0", "box": "f0dfbc", "ink": "263f49"},
	"Vsus": {"board": "405a82", "edge": "253a59", "shell": "263e5a", "rotor": "84c8b8", "accent": "a3dcc7", "chip": "202e48", "capacitor": "658fa5", "metal": "b9cadf", "box": "263e5a", "ink": "edf5ee"},
	"CSI": {"board": "67566f", "edge": "403547", "shell": "363943", "rotor": "c95161", "accent": "ec707a", "chip": "2c2935", "capacitor": "886e91", "metal": "c1becb", "box": "363943", "ink": "f4e9e4"},
}
const MATERIAL_ROLES := {
	"Board": "board", "Board edge": "edge", "Fan plastic": "shell",
	"Fan blades": "rotor", "Rounded hub terracotta": "accent",
	"Rounded screw copper": "accent", "Rounded chip charcoal": "chip",
	"Rounded capacitor blue": "capacitor", "Aluminum": "metal",
	"Cable red": "accent", "Cable black": "chip",
}
var brand := "Lotac"
var materials: Dictionary = {}

static func palette(id: String) -> Dictionary:
	return PALETTES.get(id, PALETTES.Lotac)

func configure(gpu: Node3D) -> void:
	# Private mesh/material resources keep brand changes away from imported assets and
	# other bench instances. Proxies share these meshes, so the colours stay live in focus.
	var meshes: Dictionary = {}
	for node in gpu.find_children("*", "MeshInstance3D", true, false):
		var source: Mesh = node.mesh
		if source == null: continue
		if not meshes.has(source):
			var copy: Mesh = source.duplicate()
			for index in range(source.get_surface_count()):
				var original: Material = source.surface_get_material(index)
				if original == null or not MATERIAL_ROLES.has(original.resource_name): continue
				if not materials.has(original):
					materials[original] = {"material": original.duplicate(), "role": MATERIAL_ROLES[original.resource_name]}
				copy.surface_set_material(index, materials[original].material)
			meshes[source] = copy
		node.mesh = meshes[source]
	apply_brand(brand)

func apply_brand(id: String) -> void:
	brand = id if id in BRANDS else BRANDS[0]
	var colors := palette(brand)
	for entry in materials.values():
		(entry.material as StandardMaterial3D).albedo_color = Color(colors[entry.role])
