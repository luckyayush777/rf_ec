extends RefCounted
## What went into one card's repair. Every job carries one; service controllers report what they
## use (repair_jobs.gd forwards their `consumed` signals) and customer bills charge it. Prices are
## whole cents so small consumables add up exactly.
## kind "consumable" is used up in the work (paste, IPA, oil); "part" is a spare fitted to the
## card. No spares are stocked yet, so no part entries exist; add them here with a unit cost and
## record them with add() when a replacement is fitted.
const CATALOG := {
	"thermal-paste": {"name": "Thermal paste", "kind": "consumable", "unit": "g", "cents": 150},
	"ipa-pad": {"name": "IPA wipe pad", "kind": "consumable", "unit": "pad", "cents": 15},
	"bearing-oil": {"name": "Bearing oil", "kind": "consumable", "unit": "drop", "cents": 5}}

## item id -> quantity used, in catalog units.
var used: Dictionary = {}

func add(item: String, quantity: float) -> void:
	if not CATALOG.has(item) or quantity <= 0.0:
		push_warning("Bill of materials: unknown item or quantity %s x %s" % [item, quantity])
		return
	used[item] = used.get(item, 0.0) + quantity

func quantity(item: String) -> float:
	return used.get(item, 0.0)

func is_empty() -> bool:
	return used.is_empty()

## One line per item used, in catalog order: id, name, kind, unit, quantity and cost in cents.
func lines() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in CATALOG:
		if not used.has(item): continue
		var entry: Dictionary = CATALOG[item]
		result.append({"item": item, "name": entry.name, "kind": entry.kind, "unit": entry.unit,
			"quantity": used[item], "cents": roundi(used[item] * entry.cents)})
	return result

func total_cents(kind := "") -> int:
	var total := 0
	for line in lines():
		if kind == "" or line.kind == kind: total += line.cents
	return total

## "0.3 g", "0.04 g", "2 pads": whole-unit items print as counts.
static func amount_text(line: Dictionary) -> String:
	var value: float = line.quantity
	if is_equal_approx(value, roundf(value)):
		return "%d %s%s" % [roundi(value), line.unit, "" if roundi(value) == 1 or line.unit == "g" else "s"]
	return ("%.2f %s" if value < 0.1 else "%.1f %s") % [value, line.unit]

static func money(cents: int) -> String:
	return "$%d.%02d" % [cents / 100, cents % 100]
