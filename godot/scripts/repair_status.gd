extends RefCounted
## Developer-only summary of what is wrong with the card and how far each fix has got.
## Reads the live controllers; nothing here affects play. States: "fault" (red, broken or
## untouched), "partial" (yellow, work in progress), "done" (green) and "info" (grey).
const FAULT := "fault"
const PARTIAL := "partial"
const DONE := "done"
const INFO := "info"
## Seated contact at or above this counts as a good repaste; a single central dot gives about 0.92.
const GOOD_CONTACT := 0.9

static func rows(bench: Node3D) -> Array[Dictionary]:
	return [dust(bench.cleaning), paste(bench.paste), bearing(bench.bearing),
		assembly(bench.service), test(bench)]

static func row(label: String, state: String, detail: String) -> Dictionary:
	return {"label": label, "state": state, "detail": detail}

static func percent(value: float) -> String:
	return "%d%%" % floori(clampf(value, 0.0, 1.0) * 100.0)

static func dust(cleaning: Node) -> Dictionary:
	var detail := "PCB %s · Fan %s · Heatsink %s" % [percent(cleaning.part_progress("board")),
		percent(cleaning.part_progress("fan-assembly")), percent(cleaning.part_progress("cooler-assembly"))]
	var progress: float = cleaning.progress
	return row("Dust", DONE if progress >= 0.999 else FAULT if progress < 0.02 else PARTIAL, detail)

static func paste(layer: Node) -> Dictionary:
	if layer.seated:
		var contact := "contact " + percent(layer.quality)
		if layer.dried: return row("Thermal paste", FAULT, "Old dried compound, " + contact)
		if layer.quality >= GOOD_CONTACT: return row("Thermal paste", DONE, "Fresh, " + contact)
		return row("Thermal paste", FAULT if layer.quality < 0.5 else PARTIAL,
			"Seated with poor coverage, " + contact + ". Lift test to check the imprint")
	var die: float = layer.face_progress("die")
	var base: float = layer.face_progress("heatsink")
	var dots: float = layer.paste_volume() / layer.IDEAL_VOLUME
	var detail := "Heatsink off · die %s clean · base %s clean · paste %.1f dot" % [percent(die), percent(base), dots]
	var started: bool = die > 0.0 or base > 0.0 or dots > 0.01
	if layer.faces.die.clean and layer.faces.heatsink.clean and dots >= 0.6: detail += " · ready to seat"
	return row("Thermal paste", PARTIAL if started else FAULT, detail)

static func bearing(fan: Node) -> Dictionary:
	var opened := "rotor out" if "fan-rotor" in fan.opened else "sticker off" if "hub-label" in fan.opened else ""
	if not fan.dry and opened == "": return row("Fan bearing", DONE, "Oiled, spins quietly")
	var steps: Array[String] = ["shaft " + percent(fan.progress("shaft")) + " clean", "%d oil drop%s" % [fan.oil_drops, "" if fan.oil_drops == 1 else "s"]]
	if opened != "": steps.append(opened)
	var ready: bool = fan.shaft_clean and fan.oil_drops > 0
	if ready: steps.append("refit the rotor")
	var untouched: bool = fan.dry and opened == "" and fan.progress("shaft") <= 0.0 and fan.oil_drops == 0
	return row("Fan bearing", FAULT if untouched else PARTIAL,
		("Dry and gummed, grinds · " if fan.dry and not ready else "") + " · ".join(steps))

static func assembly(service: Node) -> Dictionary:
	var missing: Array[String] = []
	for id in service.removed:
		if service.contract.objects.has(id) and service.rules.parts.get(id, {}).get("kind", "") == "assembly":
			missing.append(service.assembly_name(id) + " off")
	var screws := 0
	for id in service.fan_screws + service.cooler_screws:
		if id in service.removed: screws += 1
	if screws > 0: missing.append("%d screw%s out" % [screws, "" if screws == 1 else "s"])
	if not service.cable_connected: missing.append("fan cable unplugged")
	if missing.is_empty(): return row("Assembly", DONE, "Fully assembled, ready to test")
	return row("Assembly", PARTIAL, " · ".join(missing))

static func test(bench: Node3D) -> Dictionary:
	var thermal: Node = bench.thermal
	var reading := "core %d°C · %d MHz · VRAM %d°C · heatsink %d°C" % [roundi(thermal.core_c), thermal.core_clock(),
		roundi(thermal.memory_c), roundi(thermal.cooler_c)]
	var errors: float = thermal.memory_error_rate()
	if errors > 0.0: reading += " · memory errors " + percent(errors)
	if not bench.testing_station.installed: return row("Test run", INFO, "Off the test board · " + reading)
	var throttle: float = thermal.throttle()
	var state := FAULT if throttle >= 0.5 or errors >= 0.5 else PARTIAL if throttle > 0.0 or errors > 0.0 else DONE
	return row("Test run", state, reading)

static func color(state: String) -> Color:
	match state:
		FAULT: return Color("#e0584d")
		PARTIAL: return Color("#e6bf3c")
		DONE: return Color("#5ec46f")
	return Color("#8d969c")
