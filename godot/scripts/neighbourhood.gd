extends RefCounted
## The people the shop works for. Each household owns one card; a broken card makes it a red
## household. A repaired card turns it green or yellow by how satisfied the customer was. The
## shop's zone of influence starts at one small zone; enough happy households open the next
## zone, which brings its households (and more customers) onto the job board. Locked zones are
## megacorp turf, and the megacorp gets pettier as the shop's zone grows.
const RED := "red"
const YELLOW := "yellow"
const GREEN := "green"
## Satisfaction (out of 5) a repaired household needs to turn green or yellow; below yellow it
## stays red.
const GREEN_AT := 4
const YELLOW_AT := 3
## The megacorp is the GPU maker CSI for now.
const MEGACORP := "CSI"
## Zones in unlock order. `homes` are map positions (0..1 across the map area, y down) beside
## the map's streets; `needs` opens this zone once the unlocked zones together hold that many
## green households, or that many happy (yellow or green) ones. `seeds` claim the land: every
## point of the map belongs to the zone (or the CSI campus) with the nearest seed, so the
## territories tile the map edge to edge. `label` is where the zone's name goes.
const ZONES := [
	{"id": "lakeside", "name": "Lakeside Lane", "needs": {}, "label": Vector2(0.75, 0.935),
		"seeds": [Vector2(0.52, 0.8), Vector2(0.4, 0.9), Vector2(0.66, 0.88), Vector2(0.86, 0.86), Vector2(0.52, 0.64)],
		"homes": [Vector2(0.43, 0.75), Vector2(0.505, 0.762), Vector2(0.6, 0.752), Vector2(0.4, 0.86), Vector2(0.645, 0.86)]},
	{"id": "oldtown", "name": "Old Town", "needs": {"green": 2, "happy": 3}, "label": Vector2(0.145, 0.95),
		"seeds": [Vector2(0.15, 0.5), Vector2(0.16, 0.66), Vector2(0.17, 0.84), Vector2(0.26, 0.42)],
		"homes": [Vector2(0.142, 0.545), Vector2(0.245, 0.545), Vector2(0.06, 0.69), Vector2(0.245, 0.69), Vector2(0.142, 0.815),
			Vector2(0.06, 0.9)]},
	{"id": "hillside", "name": "Hillside", "needs": {"green": 5, "happy": 7}, "label": Vector2(0.8, 0.075),
		"seeds": [Vector2(0.8, 0.45), Vector2(0.7, 0.3), Vector2(0.86, 0.22), Vector2(0.58, 0.2), Vector2(0.92, 0.62)],
		"homes": [Vector2(0.785, 0.525), Vector2(0.855, 0.44), Vector2(0.745, 0.41), Vector2(0.64, 0.285), Vector2(0.8, 0.275),
			Vector2(0.9, 0.16), Vector2(0.55, 0.22)]}]
## The megacorp's own district round its tower: always its turf, never opened by the shop.
const CAMPUS := {"name": "CSI Campus", "label": Vector2(0.15, 0.035),
	"seeds": [Vector2(0.14, 0.2), Vector2(0.3, 0.2), Vector2(0.05, 0.35), Vector2(0.4, 0.08)]}
## `territory_at` for the campus.
const CAMPUS_TERRITORY := 3
## Where the shop and the megacorp's tower stand on the map.
const SHOP_AT := Vector2(0.52, 0.858)
const MEGACORP_AT := Vector2(0.14, 0.19)
const RESIDENTS := ["Priya S.", "Marcus T.", "Elena V.", "Tomasz K.", "Aisha R.", "Jonah W.", "Mei L.", "Diego F.", "Sam O.",
	"Fatima N.", "Lukas B.", "Grace H.", "Noor A.", "Ben C.", "Yuki M.", "Ola D.", "Rosa P.", "Ivan G."]
## Megacorp cards (MEGACORP brand) arrive with screws glued shut this often, more as the shop's
## zone grows; from GLUE_ALL_ZONES unlocked zones on, the cooler screws are glued as well.
const GLUE_CHANCE := 0.5
const GLUE_CHANCE_PER_ZONE := 0.25
const GLUE_ALL_ZONES := 3

## One per household: id, zone index, resident, map position, state and last satisfaction.
var homes: Array[Dictionary] = []
## Zones the shop has opened, from the first.
var unlocked := 1

func _init() -> void:
	var index := 0
	for zone in range(ZONES.size()):
		for spot in ZONES[zone].homes:
			homes.append({"id": "%s-%d" % [ZONES[zone].id, homes.size() + 1], "zone": zone, "resident": RESIDENTS[index % RESIDENTS.size()],
				"at": spot, "state": RED, "stars": 0})
			index += 1

func home(id: String) -> Dictionary:
	for entry in homes:
		if entry.id == id: return entry
	return {}

func zone_name(zone: int) -> String:
	return ZONES[zone].name

## The zone index whose land holds `point` (map space), or CAMPUS_TERRITORY on megacorp ground.
static func territory_at(point: Vector2) -> int:
	var best := CAMPUS_TERRITORY
	var nearest := INF
	for zone in range(CAMPUS_TERRITORY + 1):
		for anchor in (CAMPUS if zone == CAMPUS_TERRITORY else ZONES[zone]).seeds:
			var distance := point.distance_squared_to(anchor)
			if distance < nearest:
				nearest = distance
				best = zone
	return best

## Households in the shop's zone of influence.
func reachable() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in homes:
		if entry.zone < unlocked: result.append(entry)
	return result

## A household to send the next customer card: a red one in reach that has no card on the board
## or the bench yet, chosen at random. With `any_state` a happy one may call again when no red
## household is free. Empty when nobody can.
func pick(busy: Array, rng: RandomNumberGenerator, any_state := false) -> Dictionary:
	var free: Array[Dictionary] = []
	var fallback: Array[Dictionary] = []
	for entry in reachable():
		if entry.id in busy: continue
		if entry.state == RED: free.append(entry)
		else: fallback.append(entry)
	if free.is_empty() and any_state: free = fallback
	return {} if free.is_empty() else free[rng.randi_range(0, free.size() - 1)]

static func state_for(stars: int) -> String:
	return GREEN if stars >= GREEN_AT else YELLOW if stars >= YELLOW_AT else RED

## A card went back to household `id` with `stars` satisfaction (0 for a card still broken).
## Returns the names of zones this opened, in order.
func record(id: String, stars: int) -> Array[String]:
	var entry := home(id)
	var opened: Array[String] = []
	if entry.is_empty(): return opened
	entry.stars = stars
	entry.state = state_for(stars)
	while unlocked < ZONES.size() and ready_to_open(unlocked):
		opened.append(ZONES[unlocked].name)
		unlocked += 1
	return opened

## Green and happy (yellow or green) households across the unlocked zones.
func tally() -> Dictionary:
	var counts := {RED: 0, YELLOW: 0, GREEN: 0}
	for entry in reachable(): counts[entry.state] += 1
	counts.happy = counts[YELLOW] + counts[GREEN]
	return counts

func zone_tally(zone: int) -> Dictionary:
	var counts := {RED: 0, YELLOW: 0, GREEN: 0}
	for entry in homes:
		if entry.zone == zone: counts[entry.state] += 1
	return counts

func ready_to_open(zone: int) -> bool:
	var needs: Dictionary = ZONES[zone].needs
	var counts := tally()
	return counts[GREEN] >= needs.get("green", 0) or counts.happy >= needs.get("happy", 0)

## What opens the next zone, for the map's progress line; empty once every zone is open.
func next_unlock() -> Dictionary:
	if unlocked >= ZONES.size(): return {}
	var counts := tally()
	var needs: Dictionary = ZONES[unlocked].needs
	return {"zone": unlocked, "name": ZONES[unlocked].name, "green": counts[GREEN], "happy": counts.happy,
		"need_green": needs.green, "need_happy": needs.happy}

## The screws a megacorp card arrives glued over: none, the fan screws, or every screw once the
## shop has grown enough to really annoy them.
func glue_roll(rng: RandomNumberGenerator, fan_screws: Array, cooler_screws: Array) -> Array:
	if rng.randf() >= minf(1.0, GLUE_CHANCE + GLUE_CHANCE_PER_ZONE * (unlocked - 1)): return []
	return fan_screws + cooler_screws if unlocked >= GLUE_ALL_ZONES else fan_screws.duplicate()
