extends Node
## Gameplay thermal model, not a hardware measurement or engineering solver.
## Dust restricts airflow and dried paste insulates the die; heating requires the
## assembled card on the powered board.
const AMBIENT := 24.0
## Extra die rise from fully dried paste, and the heat that bypasses the cooler.
const PASTE_CORE_RISE := 32.0
const PASTE_COOLER_DROP := 6.0
## The core throttles rather than climbing without limit.
const CORE_LIMIT := 105.0
var memory_c := AMBIENT
var core_c := AMBIENT
var cooler_c := AMBIENT
var bench: Node3D

func configure(world: Node3D) -> void:
	bench = world
	# The source already contains separate packages; add readable package markings.
	for mesh in bench.gpu.find_children("*", "MeshInstance3D", true, false):
		var id := String(mesh.name)
		if not id.begins_with("memory-package-") and not id.begins_with("rear-memory-"): continue
		var marking := Label3D.new()
		marking.name = "MemoryMarking"
		marking.text = memory_name(id) + "\nVRAM"
		marking.font_size = 32
		marking.pixel_size = 0.0025
		marking.outline_size = 0
		marking.modulate = Color(0.70, 0.74, 0.69)
		var bounds: AABB = mesh.get_aabb()
		var rear := id.begins_with("rear-memory")
		marking.position = bounds.get_center()
		marking.position.y = bounds.position.y - 0.003 if rear else bounds.end.y + 0.003
		marking.rotation.x = PI / 2.0 if rear else -PI / 2.0
		mesh.add_child(marking)

func memory_name(id: String) -> String:
	return "U%d" % (int(id.get_slice("-", 2)) + (5 if id.begins_with("rear") else 1))

func dust_load() -> float:
	# Internal cooler/fan restrictions dominate; board dust adds a smaller penalty.
	return clampf(0.45 * (1.0 - bench.cleaning.part_progress("cooler-assembly")) +
		0.35 * (1.0 - bench.cleaning.part_progress("fan-assembly")) +
		0.20 * (1.0 - bench.cleaning.part_progress("board")), 0.0, 1.0)

func paste_load() -> float:
	return 1.0 - bench.paste.contact_quality()

func _process(delta: float) -> void:
	if bench == null: return
	advance(delta)

func advance(delta: float) -> void:
	var powered: bool = bench.testing_station.installed and not bench.testing_station.moving
	var dust := dust_load()
	var paste := paste_load()
	# Bad paste traps heat in the die, so the core rises while the heatsink cools slightly.
	var memory_target := lerpf(48.0, 94.0, dust) if powered else AMBIENT
	var core_target := minf(lerpf(53.0, 98.0, dust) + PASTE_CORE_RISE * paste, CORE_LIMIT) if powered else AMBIENT
	var cooler_target := lerpf(38.0, 65.0, dust) - PASTE_COOLER_DROP * paste if powered else AMBIENT
	var response := 1.0 - exp(-delta / (14.0 if powered else 40.0))
	memory_c = lerpf(memory_c, memory_target, response)
	core_c = lerpf(core_c, core_target, response)
	cooler_c = lerpf(cooler_c, cooler_target, response)
	# The die is hidden under the heatsink; its sensor reading is shown on the test monitor.
	bench.test_monitor.set_core_temperature(core_c)

func category(mesh: MeshInstance3D) -> String:
	var id := String(mesh.name)
	if id.begins_with("memory-package") or id.begins_with("rear-memory") or id.begins_with("memory-residue"): return "memory"
	if id == "gpu-die" or id == "gpu-package" or id == "paste-die": return "core"
	if id == "paste-heatsink": return "cooler"
	if id.begins_with("heatsink"): return "cooler"
	if bench.gpu.is_ancestor_of(mesh): return "board"
	return "ambient"

func surface_temperature(mesh: MeshInstance3D) -> float:
	match category(mesh):
		"memory": return memory_c - 4.0 * (memory_c - AMBIENT) / 70.0
		"core": return core_c - 3.0 * (core_c - AMBIENT) / 74.0
		"cooler": return cooler_c
		"board": return AMBIENT + (memory_c - AMBIENT) * 0.45
	return AMBIENT

func emissivity(mesh: MeshInstance3D) -> float:
	var id := String(mesh.name)
	return 0.25 if id.begins_with("heatsink") or id == "gpu-die" or "screw" in id or "bracket" in id else 0.95

func apparent_temperature(mesh: MeshInstance3D) -> float:
	# Camera assumes 0.95 emissivity. Shiny metal reflects more ambient radiation.
	var fraction := emissivity(mesh) / 0.95
	return pow(fraction * pow(surface_temperature(mesh) + 273.15, 4.0) + (1.0 - fraction) * pow(AMBIENT + 273.15, 4.0), 0.25) - 273.15
