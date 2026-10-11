extends Control
## The neighbourhood map, a turf map in the manner of San Andreas: one continuous low-poly
## valley (faceted, hill-shaded terrain, the lake, a river, roads, streets of houses, forest and
## farmland) with every scrap of land tinted by who holds it. Territories tile the map edge to
## edge (`Neighbourhood.territory_at`): the shop's zones green, megacorp turf purple, and the
## next zone flashing as contested. Households are small houses, red while their card is
## broken, then yellow or green by how happy the repair left them. Drawn for a 960 x 540
## design and scaled to fit, so the same control serves the N overlay and the wall screen
## (map_display.gd). The land warms from a dull grey wash as more of the shop's households
## turn happy.
const Neighbourhood = preload("res://scripts/neighbourhood.gd")
const DESIGN := Vector2(960, 540)
const MAP_RECT := Rect2(18, 58, 600, 464)
const PANEL := Rect2(636, 58, 306, 464)
const BACKGROUND := Color("#0e171c")
const PANEL_FILL := Color("#15232a")
const INK := Color("#e7ece8")
const MUTED := Color("#8fa0a6")
const SHOP := Color("#3fc1ae")
const STATE_COLORS := {"red": Color("#e0503f"), "yellow": Color("#efbf34"), "green": Color("#5cc86a")}
const LOCKED_HOME := Color("#9a86a0")
## Territory tints (alpha over the land) and their border lines.
const OUR_TURF := Color("#2fcf62", 0.22)
const OUR_LINE := Color("#b4f5c4")
const CSI_TURF := Color("#8e2fa6", 0.38)
## Contested turf (the next zone to open) flashes this, as gang wars do.
const WAR_TURF := Color("#ff4d3d", 0.32)
const CAMPUS_TURF := Color("#6a1f80", 0.55)
const CSI_LINE := Color("#e19ae8")
const TURF_TEXT := Color("#f0b8f4")
## Grey laid over the land while few households are happy.
const DULL_WASH := Color("#40443f")
## Terrain palette before hill shading.
const GRASS := Color("#6aa256")
const MEADOW := Color("#8db85e")
const FOREST := Color("#2f6a3e")
const FOREST_DEEP := Color("#245733")
const ROCK := Color("#8e8a80")
const SNOW := Color("#eef3f4")
const SAND := Color("#dcca94")
const PAVED := Color("#8b8e8f")
const SHALLOW := Color("#6ab7d3")
const DEEP := Color("#2b74a3")
const RIVER := Color("#4f9cc2")
const CROPS := [Color("#cbb860"), Color("#a3c15a"), Color("#b99b5f"), Color("#8eae4d"), Color("#d6c27a")]
const ROOFS := [Color("#b5654a"), Color("#a3533d"), Color("#8f725d"), Color("#6f7f88"), Color("#c38b4f"), Color("#7b6a63")]
const ROAD_CASING := Color("#4d4a40")
const ROAD_FILL := {"main": Color("#f1e8c9"), "street": Color("#e1d6b4"), "track": Color("#c4ad82")}
## Road widths in design pixels.
const ROAD_WIDTH := {"main": 5.0, "street": 3.2, "track": 1.8}

## Geography, in map space (0..1 across the map area, y down). The lake the shop's window
## looks over sits in the middle of the valley, the snowy range along the top.
const LAKE_CENTRE := Vector2(0.47, 0.52)
const LAKE_RADII := Vector2(0.12, 0.105)
const LAKE_NAME := "ALDER LAKE"
## The river runs down from the range into the lake and out of it to the south-east.
const RIVERS := [
	[Vector2(0.43, 0.0), Vector2(0.405, 0.07), Vector2(0.445, 0.15), Vector2(0.42, 0.23), Vector2(0.45, 0.31), Vector2(0.465, 0.43)],
	[Vector2(0.575, 0.575), Vector2(0.66, 0.64), Vector2(0.74, 0.7), Vector2(0.82, 0.73), Vector2(0.9, 0.78), Vector2(1.0, 0.8)]]
const ROADS := [
	# The valley road in from the south, past the shop, and the lane the shop stands on.
	{"kind": "main", "points": [Vector2(0.585, 1.0), Vector2(0.575, 0.93), Vector2(0.56, 0.86), Vector2(0.55, 0.81)]},
	{"kind": "main", "points": [Vector2(0.33, 0.77), Vector2(0.38, 0.79), Vector2(0.45, 0.805), Vector2(0.52, 0.81), Vector2(0.59, 0.805),
		Vector2(0.66, 0.795), Vector2(0.71, 0.77)]},
	# Round the lake.
	{"kind": "main", "points": [Vector2(0.33, 0.77), Vector2(0.305, 0.7), Vector2(0.295, 0.62), Vector2(0.3, 0.52), Vector2(0.32, 0.43),
		Vector2(0.37, 0.37), Vector2(0.44, 0.345), Vector2(0.52, 0.35), Vector2(0.59, 0.375), Vector2(0.635, 0.42)]},
	{"kind": "main", "points": [Vector2(0.71, 0.77), Vector2(0.7, 0.69), Vector2(0.67, 0.61), Vector2(0.65, 0.51), Vector2(0.635, 0.42)]},
	# Out east over the farmland, and Old Town's Market Street out west.
	{"kind": "main", "points": [Vector2(0.67, 0.61), Vector2(0.8, 0.63), Vector2(0.9, 0.6), Vector2(1.0, 0.585)]},
	{"kind": "main", "points": [Vector2(0.0, 0.62), Vector2(0.295, 0.62)]},
	# Old Town's grid.
	{"kind": "street", "points": [Vector2(0.1, 0.43), Vector2(0.1, 1.0)]},
	{"kind": "street", "points": [Vector2(0.19, 0.42), Vector2(0.19, 1.0)]},
	{"kind": "street", "points": [Vector2(0.03, 0.43), Vector2(0.32, 0.43)]},
	{"kind": "street", "points": [Vector2(0.025, 0.755), Vector2(0.326, 0.755)]},
	{"kind": "street", "points": [Vector2(0.025, 0.87), Vector2(0.19, 0.87)]},
	# Lakeside's cul-de-sac and the farm track.
	{"kind": "street", "points": [Vector2(0.45, 0.805), Vector2(0.44, 0.88), Vector2(0.45, 0.95)]},
	{"kind": "track", "points": [Vector2(0.66, 0.795), Vector2(0.72, 0.86), Vector2(0.84, 0.9), Vector2(0.95, 0.97)]},
	# Hillside's switchbacks and spur.
	{"kind": "street", "points": [Vector2(0.635, 0.42), Vector2(0.73, 0.47), Vector2(0.86, 0.5), Vector2(0.92, 0.45), Vector2(0.8, 0.37),
		Vector2(0.69, 0.33), Vector2(0.715, 0.255), Vector2(0.83, 0.215), Vector2(0.93, 0.2)]},
	{"kind": "street", "points": [Vector2(0.69, 0.33), Vector2(0.6, 0.28), Vector2(0.53, 0.19)]},
	{"kind": "track", "points": [Vector2(0.93, 0.2), Vector2(0.97, 0.13), Vector2(1.0, 0.11)]},
	# The CSI campus ring and its two gates.
	{"kind": "street", "points": [Vector2(0.06, 0.11), Vector2(0.25, 0.11), Vector2(0.27, 0.3), Vector2(0.07, 0.31), Vector2(0.06, 0.11)]},
	{"kind": "street", "points": [Vector2(0.19, 0.42), Vector2(0.2, 0.36), Vector2(0.21, 0.305)]},
	{"kind": "street", "points": [Vector2(0.37, 0.37), Vector2(0.31, 0.33), Vector2(0.27, 0.3)]}]
## Where houses line the streets and the forest gives way to lawns.
const TOWNS := [Rect2(0.02, 0.4, 0.3, 0.58), Rect2(0.33, 0.68, 0.39, 0.32), Rect2(0.04, 0.08, 0.26, 0.26)]
const CAMPUS_GROUND := Rect2(0.05, 0.1, 0.23, 0.22)
## Campus office blocks (map-space rectangles) and its car park.
const OFFICES := [Rect2(0.075, 0.13, 0.045, 0.05), Rect2(0.075, 0.24, 0.07, 0.045), Rect2(0.2, 0.25, 0.05, 0.035), Rect2(0.165, 0.13, 0.05, 0.035)]
const CAR_PARK := Rect2(0.19, 0.17, 0.055, 0.06)
## Terrain mesh columns; rows follow the map's aspect.
const GRID := 46
## Height to design pixels for hill shading, and the sun from the north-west, high up.
const RELIEF := 140.0
const SUN := Vector3(-0.45, -0.55, 0.7)
const SNOW_LINE := 0.86
const ROCK_LINE := 0.66
## Seconds per flash of contested turf.
const PULSE_TIME := 1.4

## Built once and shared by every map: terrain and feature triangles (design pixels from the map
## corner), territory triangles and border segments, road and river polylines.
static var geography: Dictionary = {}

var jobs: Node
var font: Font
var scale_factor := 1.0
var origin := Vector2.ZERO
var redraw_wait := 0.0

func _init() -> void:
	font = ThemeDB.fallback_font

func configure(repair_jobs: Node) -> void:
	jobs = repair_jobs
	jobs.changed.connect(queue_redraw)
	resized.connect(queue_redraw)
	queue_redraw()

## Contested turf flashes while the map is on screen.
func _process(delta: float) -> void:
	redraw_wait -= delta
	if redraw_wait > 0.0 or jobs == null or not is_visible_in_tree() or jobs.neighbourhood.next_unlock().is_empty(): return
	redraw_wait = 1.0 / 20.0
	queue_redraw()

## Design space (960 x 540) to this control's pixels.
func p(point: Vector2) -> Vector2:
	return origin + point * scale_factor

## A map position (0..1 across the map area) to design pixels from the map corner, the space the
## map is drawn in.
static func px(point: Vector2) -> Vector2:
	return point * MAP_RECT.size

## A map position to design space, for text.
static func design(point: Vector2) -> Vector2:
	return MAP_RECT.position + point * MAP_RECT.size

func fs(points: float) -> int:
	return maxi(6, roundi(points * scale_factor))

func text(at: Vector2, value: String, points: float, color: Color = INK, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(font, p(at), value, align, width * scale_factor if width > 0.0 else -1.0, fs(points), color)

## Text with a dark rim, readable over the land.
func label(at: Vector2, value: String, points: float, color: Color, width := 200.0) -> void:
	var font_size := fs(points)
	var rim := maxi(2, roundi(3.0 * scale_factor))
	draw_string_outline(font, p(at), value, HORIZONTAL_ALIGNMENT_CENTER, width * scale_factor, font_size, rim, Color(0.03, 0.05, 0.06, 0.85))
	draw_string(font, p(at), value, HORIZONTAL_ALIGNMENT_CENTER, width * scale_factor, font_size, color)

func _draw() -> void:
	if jobs == null: return
	var area: Neighbourhood = jobs.neighbourhood
	scale_factor = minf(size.x / DESIGN.x, size.y / DESIGN.y)
	origin = (size - DESIGN * scale_factor) * 0.5
	draw_rect(Rect2(p(Vector2.ZERO), DESIGN * scale_factor), BACKGROUND)
	text(Vector2(20, 38), "NEIGHBOURHOOD", 26, INK)
	var title_width := font.get_string_size("NEIGHBOURHOOD", HORIZONTAL_ALIGNMENT_LEFT, -1, fs(26)).x / scale_factor
	text(Vector2(36 + title_width, 38), "BENCH REPAIR  ·  %s" % jobs.clock_text(jobs.shop_minutes), 15, MUTED)
	draw_map(area)
	draw_panel(area)

## Territory index (zone, or the campus) to its tint for the shop's current reach.
func turf_color(territory: int, area: Neighbourhood) -> Color:
	if territory == Neighbourhood.CAMPUS_TERRITORY: return CAMPUS_TURF
	return OUR_TURF if territory < area.unlocked else CSI_TURF

func draw_map(area: Neighbourhood) -> void:
	var land := geography_data()
	var item := get_canvas_item()
	draw_set_transform(p(MAP_RECT.position), 0.0, Vector2.ONE * scale_factor)
	RenderingServer.canvas_item_add_triangle_array(item, land.terrain_indices, land.terrain_points, land.terrain_colors)
	for river in land.rivers:
		draw_polyline(river, RIVER.darkened(0.25), 7.5, true)
		draw_polyline(river, RIVER, 5.0, true)
	draw_roads(land)
	RenderingServer.canvas_item_add_triangle_array(item, land.feature_indices, land.feature_points, land.feature_colors)
	draw_campus()
	# The land warms as the shop's households turn happy.
	var counts := area.tally()
	var reach := area.reachable().size()
	var warmth := 0.0 if reach == 0 else float(counts.happy) / reach
	draw_rect(Rect2(Vector2.ZERO, MAP_RECT.size), Color(DULL_WASH, 0.32 * (1.0 - warmth)))
	# Turf: every scrap of land tinted by who holds it, the next zone flashing as contested.
	var contested := area.unlocked if area.unlocked < Neighbourhood.ZONES.size() else -1
	var flash := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU / PULSE_TIME)
	for territory in range(land.turf_points.size()):
		var points: PackedVector2Array = land.turf_points[territory]
		var colors := PackedColorArray()
		colors.resize(points.size())
		colors.fill(turf_color(territory, area))
		RenderingServer.canvas_item_add_triangle_array(item, land.turf_indices[territory], points, colors)
		if territory == contested:
			colors.fill(Color(WAR_TURF, WAR_TURF.a * flash))
			RenderingServer.canvas_item_add_triangle_array(item, land.turf_indices[territory], points, colors)
	for pair in land.borders:
		var sides: Array = pair.split("-")
		var ours := [int(sides[0]) < area.unlocked, int(sides[1]) < area.unlocked]
		var segments: PackedVector2Array = land.borders[pair]
		if ours[0] and ours[1]: draw_multiline(segments, Color(1, 1, 1, 0.3), 1.0, true)
		elif ours[0] or ours[1]:
			draw_multiline(segments, Color(0.02, 0.08, 0.04, 0.55), 4.0, true)
			draw_multiline(segments, OUR_LINE, 2.0, true)
		else: draw_multiline(segments, Color(CSI_LINE, 0.75), 1.4, true)
		if contested >= 0 and str(contested) in sides and (ours[0] or ours[1]):
			draw_multiline(segments, Color(1, 1, 1, 0.75 * flash), 2.0, true)
	var busy: Array = jobs.busy_homes()
	for entry in area.homes:
		var ours: bool = entry.zone < area.unlocked
		house(px(entry.at), STATE_COLORS[entry.state] if ours else LOCKED_HOME, ours and entry.id in busy)
	draw_shop(px(Neighbourhood.SHOP_AT))
	draw_tower(px(Neighbourhood.MEGACORP_AT))
	draw_set_transform(Vector2.ZERO)
	# Mask what trees and roofs spill past the map's edge, then frame it.
	var frame := Rect2(p(MAP_RECT.position), MAP_RECT.size * scale_factor)
	var rim := 10.0 * scale_factor
	for strip in [Rect2(frame.position - Vector2(rim, rim), Vector2(frame.size.x + rim * 2.0, rim)),
			Rect2(Vector2(frame.position.x - rim, frame.end.y), Vector2(frame.size.x + rim * 2.0, rim)),
			Rect2(frame.position - Vector2(rim, 0), Vector2(rim, frame.size.y)), Rect2(Vector2(frame.end.x, frame.position.y), Vector2(rim, frame.size.y))]:
		draw_rect(strip, BACKGROUND)
	draw_rect(frame, Color("#56676d"), false, maxf(1.0, 1.5 * scale_factor))
	draw_labels(area)
	draw_compass(Vector2(0.958, 0.075))

func draw_roads(land: Dictionary) -> void:
	for kind in ["track", "street", "main"]:
		var width: float = ROAD_WIDTH[kind]
		for road in land.roads:
			if road.kind != kind: continue
			if kind != "track":
				draw_polyline(road.points, ROAD_CASING, width + 2.0, true)
				for corner in road.points: draw_circle(corner, (width + 2.0) * 0.5, ROAD_CASING)
		for road in land.roads:
			if road.kind != kind: continue
			draw_polyline(road.points, ROAD_FILL[kind], width, true)
			for corner in road.points: draw_circle(corner, width * 0.5, ROAD_FILL[kind])
	# Bridges where roads cross the river.
	for bridge in land.bridges:
		var along: Vector2 = bridge.along
		var across := along.orthogonal()
		var deck := PackedVector2Array([bridge.at - along * 7.0 - across * 4.0, bridge.at + along * 7.0 - across * 4.0,
			bridge.at + along * 7.0 + across * 4.0, bridge.at - along * 7.0 + across * 4.0])
		draw_colored_polygon(deck, ROAD_CASING)
		draw_line(bridge.at - along * 7.0, bridge.at + along * 7.0, ROAD_FILL.main, 4.0, true)

## The megacorp's car park, a lot of white lines.
func draw_campus() -> void:
	var lot := Rect2(px(CAR_PARK.position), px(CAR_PARK.size))
	draw_rect(lot, Color("#55595e"))
	for bay in range(1, 6):
		var x := lot.position.x + lot.size.x * bay / 6.0
		draw_line(Vector2(x, lot.position.y + 1.0), Vector2(x, lot.position.y + lot.size.y * 0.4), Color(1, 1, 1, 0.55), 0.8)
		draw_line(Vector2(x, lot.end.y - 1.0), Vector2(x, lot.end.y - lot.size.y * 0.4), Color(1, 1, 1, 0.55), 0.8)

## A household: walls and a pitched roof in its state colour; a white ring marks a card at the shop.
func house(at: Vector2, color: Color, at_shop: bool) -> void:
	if at_shop: draw_arc(at + Vector2(0, -2), 13.0, 0.0, TAU, 28, Color(1, 1, 1, 0.95), 2.0, true)
	var dark := Color(0.06, 0.07, 0.08, 0.9)
	var wall := Rect2(at + Vector2(-6, -1), Vector2(12, 8))
	draw_rect(Rect2(wall.position + Vector2(1.5, 1.5), wall.size), Color(0, 0, 0, 0.35))
	draw_rect(wall, color.lightened(0.15))
	var roof := PackedVector2Array([at + Vector2(-8, -0.5), at + Vector2(0, -8.5), at + Vector2(8, -0.5)])
	draw_colored_polygon(roof, color.darkened(0.2))
	draw_polyline(PackedVector2Array([roof[0], roof[1], roof[2], wall.end - Vector2(0.5, 0), Vector2(wall.position.x + 0.5, wall.end.y), roof[0]]), dark, 1.0, true)
	draw_rect(Rect2(at + Vector2(-1.6, 2.4), Vector2(3.2, 4.6)), dark)

## The shop: a teal workshop with a bench sign.
func draw_shop(at: Vector2) -> void:
	draw_circle(at + Vector2(0, -1), 11.0, Color(0.02, 0.05, 0.06, 0.8))
	draw_circle(at + Vector2(0, -1), 9.5, SHOP)
	draw_rect(Rect2(at + Vector2(-5, -3), Vector2(10, 6)), Color("#0e171c"))
	draw_colored_polygon(PackedVector2Array([at + Vector2(-6.5, -2.5), at + Vector2(0, -8), at + Vector2(6.5, -2.5)]), Color("#0e171c"))
	draw_rect(Rect2(at + Vector2(-3, -1.5), Vector2(6, 2)), SHOP)

## The megacorp's tower, drawn standing up off the map.
func draw_tower(at: Vector2) -> void:
	var foot := Rect2(at + Vector2(-9, -2), Vector2(18, 10))
	draw_rect(Rect2(foot.position + Vector2(3, 3), foot.size), Color(0, 0, 0, 0.35))
	draw_rect(foot, Color("#4a2357"))
	var face := Rect2(at + Vector2(-7, -34), Vector2(14, 38))
	draw_colored_polygon(PackedVector2Array([face.position + Vector2(face.size.x, 0), face.position + Vector2(face.size.x + 5, 4),
		face.end + Vector2(5, 0), face.end]), Color("#3a1846"))
	draw_rect(face, Color("#5c2a6d"))
	draw_rect(face, CSI_LINE, false, 1.0)
	for row in range(5):
		for column in range(2):
			draw_rect(Rect2(face.position + Vector2(2.5 + column * 5.5, 3 + row * 6.5), Vector2(3.5, 3.5)), Color(CSI_LINE, 0.8))

func draw_labels(area: Neighbourhood) -> void:
	for zone in range(Neighbourhood.ZONES.size()):
		var ours := zone < area.unlocked
		var title: String = Neighbourhood.ZONES[zone].name.to_upper()
		var at := design(Neighbourhood.ZONES[zone].label)
		if ours: label(at + Vector2(-100, 0), title, 13, INK)
		else:
			label(at + Vector2(-100, 0), title, 13, TURF_TEXT)
			label(at + Vector2(-100, 13), "%s TURF" % Neighbourhood.MEGACORP + ("  ·  CONTESTED" if zone == area.unlocked else ""), 9, TURF_TEXT)
	label(design(Neighbourhood.CAMPUS.label) + Vector2(-100, 0), Neighbourhood.CAMPUS.name.to_upper(), 12, TURF_TEXT)
	label(design(Neighbourhood.MEGACORP_AT) + Vector2(-100, 22), Neighbourhood.MEGACORP + " HQ", 11, TURF_TEXT)
	label(design(Neighbourhood.SHOP_AT) + Vector2(-100, 21), "YOUR BENCH", 11, SHOP)
	label(design(LAKE_CENTRE) + Vector2(-100, 4), LAKE_NAME, 11, Color("#d7f0f8"))

func draw_compass(at_map: Vector2) -> void:
	var at := p(design(at_map))
	var radius := 11.0 * scale_factor
	draw_circle(at, radius + 2.0 * scale_factor, Color(0.03, 0.05, 0.06, 0.6))
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius * 0.35, 0), at + Vector2(-radius * 0.35, 0)]), INK)
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, radius), at + Vector2(radius * 0.35, 0), at + Vector2(-radius * 0.35, 0)]), MUTED.darkened(0.3))
	draw_string(font, at + Vector2(-20, -radius - 4.0 * scale_factor) * Vector2(1, 1), "N", HORIZONTAL_ALIGNMENT_CENTER, 40.0 * scale_factor, fs(10), INK)

func draw_panel(area: Neighbourhood) -> void:
	draw_rect(Rect2(p(PANEL.position), PANEL.size * scale_factor), PANEL_FILL)
	var x := PANEL.position.x + 16
	var y := PANEL.position.y + 30
	text(Vector2(x, y), "YOUR ZONE", 16, INK)
	y += 26
	for zone in range(Neighbourhood.ZONES.size()):
		var name: String = Neighbourhood.ZONES[zone].name
		if zone >= area.unlocked:
			text(Vector2(x, y), name, 14, TURF_TEXT)
			text(Vector2(x + 150, y), "%s turf" % Neighbourhood.MEGACORP, 13, TURF_TEXT)
			y += 24
			continue
		var counts := area.zone_tally(zone)
		text(Vector2(x, y), name, 14, INK)
		var cx := x + 150.0
		for state in ["red", "yellow", "green"]:
			draw_circle(p(Vector2(cx, y - 5)), 6.0 * scale_factor, STATE_COLORS[state])
			text(Vector2(cx + 10, y), str(counts[state]), 14, INK)
			cx += 44.0
		y += 24
	y += 12
	var next := area.next_unlock()
	if next.is_empty():
		text(Vector2(x, y), "Every zone trusts your bench.", 14, OUR_LINE, PANEL.size.x - 32)
		y += 22
	else:
		text(Vector2(x, y), "NEXT: %s" % next.name.to_upper(), 15, INK)
		y += 22
		y = progress(x, y, "Green homes", next.green, next.need_green, STATE_COLORS.green)
		text(Vector2(x, y), "or", 12, MUTED)
		y += 18
		y = progress(x, y, "Happy homes (yellow or green)", next.happy, next.need_happy, STATE_COLORS.yellow)
	y += 10
	text(Vector2(x, y), "HOW HOMES TURN", 13, MUTED)
	y += 20
	for entry in [["red", "Broken card, or an unhappy repair"], ["yellow", "Fixed, satisfaction 3 of 5"],
			["green", "Fixed, satisfaction 4 or 5 of 5"]]:
		draw_circle(p(Vector2(x + 6, y - 5)), 5.0 * scale_factor, STATE_COLORS[entry[0]])
		text(Vector2(x + 18, y), entry[1], 12, INK, PANEL.size.x - 40)
		y += 19
	y += 4
	var swatch_x := x
	for entry in [[Color(OUR_TURF, 0.9), "Your turf"], [Color(CSI_TURF, 0.9), "%s turf" % Neighbourhood.MEGACORP], [Color(WAR_TURF, 0.9), "Contested"]]:
		draw_rect(Rect2(p(Vector2(swatch_x, y - 10)), Vector2(12, 12) * scale_factor), entry[0])
		text(Vector2(swatch_x + 17, y), entry[1], 12, INK)
		swatch_x += 92.0
	y += 22
	var chance := minf(1.0, Neighbourhood.GLUE_CHANCE + Neighbourhood.GLUE_CHANCE_PER_ZONE * (area.unlocked - 1))
	text(Vector2(x, y), "%s glues %d%% of its cards shut%s." % [Neighbourhood.MEGACORP, roundi(chance * 100),
		", every screw" if area.unlocked >= Neighbourhood.GLUE_ALL_ZONES else ", fan screws"], 12, TURF_TEXT, PANEL.size.x - 32)

func progress(x: float, y: float, title: String, have: int, need: int, color: Color) -> float:
	text(Vector2(x, y), "%s  %d / %d" % [title, mini(have, need), need], 12, INK, PANEL.size.x - 32)
	var bar := Rect2(p(Vector2(x, y + 6)), Vector2(PANEL.size.x - 32, 7) * scale_factor)
	draw_rect(bar, Color("#24343c"))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(float(have) / maxf(need, 1), 0.0, 1.0), bar.size.y)), color)
	return y + 26

# --- Geography -----------------------------------------------------------------------------

static func geography_data() -> Dictionary:
	if geography.is_empty(): geography = build_geography()
	return geography

## The lake's shore in design pixels: a wobbly ellipse.
static func lake_outline() -> PackedVector2Array:
	var shore := PackedVector2Array()
	for step in range(40):
		var angle := TAU * step / 40.0
		var wobble := 1.0 + 0.09 * sin(3.0 * angle + 0.6) + 0.05 * sin(5.0 * angle + 2.1)
		shore.append(px(LAKE_CENTRE + Vector2(cos(angle), sin(angle)) * LAKE_RADII * wobble))
	return shore

## 0 at the lake's shore to 1 at its middle.
static func lake_depth(at: Vector2) -> float:
	return smoothstep(1.0, 0.25, ((at / MAP_RECT.size - LAKE_CENTRE) / LAKE_RADII).length())

static func height_at(at: Vector2, noise: FastNoiseLite, detail: FastNoiseLite) -> float:
	var uv := at / MAP_RECT.size
	var ridge := smoothstep(0.27, 0.0, uv.y) * lerpf(0.62, 1.1, smoothstep(0.05, 0.55, uv.x))
	var hills := 0.3 * smoothstep(0.58, 1.0, uv.x) * smoothstep(0.72, 0.18, uv.y)
	var height := ridge * (0.78 + 0.45 * absf(detail.get_noise_2d(at.x, at.y))) + hills + 0.07 * noise.get_noise_2d(at.x, at.y)
	# The campus is graded flat.
	height *= 1.0 - 0.6 * soft_inside(uv, CAMPUS_GROUND, 0.04)
	return maxf(height, 0.0)

## 1 well inside `rect`, easing to 0 over `feather` past its edge.
static func soft_inside(uv: Vector2, rect: Rect2, feather: float) -> float:
	var outside := Vector2(maxf(rect.position.x - uv.x, uv.x - rect.end.x), maxf(rect.position.y - uv.y, uv.y - rect.end.y))
	return smoothstep(feather, 0.0, maxf(outside.x, outside.y))

static func in_town(uv: Vector2) -> bool:
	for town in TOWNS:
		if town.has_point(uv): return true
	return false

## Within `margin` design pixels of a road's edge.
static func near_road(at: Vector2, roads: Array, margin: float) -> bool:
	for road in roads:
		var reach: float = margin + ROAD_WIDTH[road.kind] * 0.5
		if not road.bounds.grow(reach).has_point(at): continue
		var points: PackedVector2Array = road.points
		for index in range(points.size() - 1):
			if at.distance_to(Geometry2D.get_closest_point_to_segment(at, points[index], points[index + 1])) < reach: return true
	return false

static func near_any(at: Vector2, spots: PackedVector2Array, distance: float) -> bool:
	for spot in spots:
		if at.distance_squared_to(spot) < distance * distance: return true
	return false

static func near_polyline(at: Vector2, points: PackedVector2Array, distance: float) -> bool:
	for index in range(points.size() - 1):
		if at.distance_to(Geometry2D.get_closest_point_to_segment(at, points[index], points[index + 1])) < distance: return true
	return false

## What covers the ground at `at` (design pixels), given its height.
static func ground(at: Vector2, height: float, ctx: Dictionary) -> String:
	var uv := at / MAP_RECT.size
	if Geometry2D.is_point_in_polygon(at, ctx.lake): return "water"
	if height > SNOW_LINE + 0.06 * ctx.detail.get_noise_2d(at.x * 3.0, at.y * 3.0): return "snow"
	if height > ROCK_LINE: return "rock"
	if CAMPUS_GROUND.has_point(uv): return "paved" if ctx.noise.get_noise_2d(at.x * 2.0, at.y * 2.0) > 0.1 else "lawn"
	if uv.y > LAKE_CENTRE.y and near_polyline(at, ctx.shore, 10.0): return "sand"
	if uv.x > 0.73 and uv.y > 0.63: return "field"
	return "forest" if forested(at, height, ctx) else "grass"

static func forested(at: Vector2, height: float, ctx: Dictionary) -> bool:
	var uv := at / MAP_RECT.size
	if in_town(uv) or near_any(at, ctx.homes, 22.0): return false
	var cover: float = ctx.noise.get_noise_2d(at.x * 1.6 + 40.0, at.y * 1.6)
	if not (cover > 0.28 or (height > 0.2 and cover > -0.3)): return false
	return not near_road(at, ctx.roads, 5.0)

static func build_geography() -> Dictionary:
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.012
	var detail := FastNoiseLite.new()
	detail.seed = 29
	detail.frequency = 0.03
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var shore := lake_outline()
	var closed_shore := shore.duplicate()
	closed_shore.append(shore[0])
	var roads: Array[Dictionary] = []
	for road in ROADS:
		var line := PackedVector2Array()
		for point in road.points: line.append(px(point))
		var bounds := Rect2(line[0], Vector2.ZERO)
		for point in line: bounds = bounds.expand(point)
		roads.append({"kind": road.kind, "points": line, "bounds": bounds})
	var rivers: Array[PackedVector2Array] = []
	for river in RIVERS:
		var line := PackedVector2Array()
		for point in river: line.append(px(point))
		rivers.append(line)
	var homes := PackedVector2Array()
	for zone in Neighbourhood.ZONES:
		for spot in zone.homes: homes.append(px(spot))
	homes.append(px(Neighbourhood.SHOP_AT))
	var ctx := {"noise": noise, "detail": detail, "lake": shore, "shore": closed_shore, "roads": roads, "homes": homes}
	# A jittered grid with the shore threaded through it, so facets follow the waterline.
	var columns := GRID
	var rows := roundi(GRID * MAP_RECT.size.y / MAP_RECT.size.x)
	var cell := Vector2(MAP_RECT.size.x / columns, MAP_RECT.size.y / rows)
	var points := PackedVector2Array()
	for row in range(rows + 1):
		for column in range(columns + 1):
			var at := Vector2(column * cell.x, row * cell.y)
			if column > 0 and column < columns: at.x += rng.randf_range(-0.38, 0.38) * cell.x
			if row > 0 and row < rows: at.y += rng.randf_range(-0.38, 0.38) * cell.y
			if near_any(at, shore, cell.x * 0.55): continue
			points.append(at)
	points.append_array(shore)
	var heights := PackedFloat32Array()
	for point in points: heights.append(height_at(point, noise, detail))
	var triangles := Geometry2D.triangulate_delaunay(points)
	var sun := SUN.normalized()
	var terrain := PackedVector2Array()
	var terrain_colors := PackedColorArray()
	var turf: Array[PackedVector2Array] = []
	for territory in range(Neighbourhood.CAMPUS_TERRITORY + 1): turf.append(PackedVector2Array())
	var edges := {}
	var borders := {}
	for index in range(0, triangles.size(), 3):
		var corners := [triangles[index], triangles[index + 1], triangles[index + 2]]
		var a: Vector2 = points[corners[0]]
		var b: Vector2 = points[corners[1]]
		var c: Vector2 = points[corners[2]]
		var centre := (a + b + c) / 3.0
		var height: float = (heights[corners[0]] + heights[corners[1]] + heights[corners[2]]) / 3.0
		var kind := ground(centre, height, ctx)
		var color := ground_color(kind, centre, height, ctx)
		if kind != "water":
			var normal := Vector3(b.x - a.x, b.y - a.y, (heights[corners[1]] - heights[corners[0]]) * RELIEF).cross(
				Vector3(c.x - a.x, c.y - a.y, (heights[corners[2]] - heights[corners[0]]) * RELIEF)).normalized()
			if normal.z < 0.0: normal = -normal
			var shade := 0.6 + 0.5 * clampf(normal.dot(sun), 0.0, 1.0)
			color = Color(color.r * shade, color.g * shade, color.b * shade)
		var jitter := rng.randf_range(0.965, 1.035)
		color = Color(color.r * jitter, color.g * jitter, color.b * jitter)
		for corner in [a, b, c]:
			terrain.append(corner)
			terrain_colors.append(color)
		var territory := -1 if kind == "water" else Neighbourhood.territory_at(centre / MAP_RECT.size)
		if territory >= 0: turf[territory].append_array(PackedVector2Array([a, b, c]))
		# Borders run along the edges between two different territories' land.
		for side in range(3):
			var from: int = corners[side]
			var to: int = corners[(side + 1) % 3]
			var key := mini(from, to) * 65536 + maxi(from, to)
			if not edges.has(key):
				edges[key] = territory
				continue
			var other: int = edges[key]
			if other < 0 or territory < 0 or other == territory: continue
			var pair := "%d-%d" % [mini(other, territory), maxi(other, territory)]
			if not borders.has(pair): borders[pair] = PackedVector2Array()
			borders[pair].append_array(PackedVector2Array([points[from], points[to]]))
	var features := build_features(ctx, rng, rivers)
	var turf_indices: Array[PackedInt32Array] = []
	for patch in turf: turf_indices.append(sequence(patch.size()))
	return {"terrain_points": terrain, "terrain_colors": terrain_colors, "terrain_indices": sequence(terrain.size()),
		"feature_points": features.points, "feature_colors": features.colors, "feature_indices": sequence(features.points.size()),
		"turf_points": turf, "turf_indices": turf_indices, "borders": borders, "roads": roads, "rivers": rivers,
		"bridges": bridges(roads, rivers)}

static func sequence(count: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(count)
	for index in range(count): result[index] = index
	return result

static func ground_color(kind: String, at: Vector2, height: float, ctx: Dictionary) -> Color:
	var shift: float = 0.5 + 0.5 * ctx.noise.get_noise_2d(at.x * 2.5, at.y * 2.5)
	match kind:
		"water": return SHALLOW.lerp(DEEP, lake_depth(at))
		"snow": return SNOW
		"rock": return ROCK.lerp(SNOW, smoothstep(ROCK_LINE, SNOW_LINE + 0.1, height) * 0.45)
		"paved": return PAVED
		"lawn": return MEADOW.darkened(0.08)
		"sand": return SAND
		"forest": return FOREST.lerp(FOREST_DEEP, shift)
		"field":
			# A patchwork of crops in slightly skewed plots.
			var plot := at.rotated(0.18)
			var cell := Vector2i(floori(plot.x / 46.0), floori(plot.y / 30.0))
			return CROPS[posmod(cell.x * 7 + cell.y * 13 + cell.x * cell.y, CROPS.size())]
	return GRASS.lerp(MEADOW, shift * (0.4 if height > 0.3 else 1.0))

## Pines in the forest, round trees on the lawns and roofs along the town streets, as flat
## triangles (with soft shadows) in design pixels.
static func build_features(ctx: Dictionary, rng: RandomNumberGenerator, rivers: Array[PackedVector2Array]) -> Dictionary:
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var shadow := Color(0, 0, 0, 0.28)
	# Buildings first, so trees never stand on a roof.
	var roofs := PackedVector2Array()
	for road in ctx.roads:
		if road.kind == "track": continue
		var line: PackedVector2Array = road.points
		var setback: float = ROAD_WIDTH[road.kind] * 0.5 + 7.0
		for index in range(line.size() - 1):
			var from: Vector2 = line[index]
			var to: Vector2 = line[index + 1]
			var along := (to - from).normalized()
			var length := from.distance_to(to)
			var step := 13.0
			var distance := 8.0
			while distance < length - 6.0:
				for side in [-1.0, 1.0]:
					var at: Vector2 = from + along * distance + along.orthogonal() * side * setback
					var uv := at / MAP_RECT.size
					if not in_town(uv) or CAMPUS_GROUND.grow(0.01).has_point(uv) or rng.randf() < 0.18: continue
					if Geometry2D.is_point_in_polygon(at, ctx.lake) or near_any(at, ctx.homes, 16.0) or near_any(at, roofs, 10.5): continue
					if near_road(at, ctx.roads, 4.0) or rivers.any(func(river): return near_polyline(at, river, 8.0)): continue
					roofs.append(at)
					var tint: Color = ROOFS[rng.randi() % ROOFS.size()]
					building(points, colors, at, along, Vector2(rng.randf_range(8.0, 11.0), rng.randf_range(6.5, 8.0)), tint, shadow)
				distance += step
	# The campus offices: big flat roofs.
	for office in OFFICES:
		var rect := Rect2(px(office.position), px(office.size))
		quad(points, colors, rect.position + Vector2(2.5, 2.5), Vector2(rect.size.x, 0), Vector2(0, rect.size.y), shadow)
		quad(points, colors, rect.position, Vector2(rect.size.x, 0), Vector2(0, rect.size.y), Color("#7f8a99"))
		quad(points, colors, rect.position + Vector2(2, 2), Vector2(rect.size.x - 4, 0), Vector2(0, rect.size.y - 4), Color("#97a2b0"))
		roofs.append(rect.get_center())
	# Trees.
	var spacing := 8.5
	var y := 4.0
	while y < MAP_RECT.size.y:
		var x := 4.0
		while x < MAP_RECT.size.x:
			var at := Vector2(x, y) + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
			x += spacing
			var height := height_at(at, ctx.noise, ctx.detail)
			var kind := ground(at, height, ctx)
			if near_any(at, roofs, 9.0) or rivers.any(func(river): return near_polyline(at, river, 5.0)): continue
			if kind == "forest" and rng.randf() < 0.82: pine(points, colors, at, rng.randf_range(0.8, 1.2), shadow)
			elif kind in ["grass", "lawn"] and not near_road(at, ctx.roads, 3.0) and not near_any(at, ctx.homes, 12.0):
				var chance := 0.1 if in_town(at / MAP_RECT.size) else 0.05
				if rng.randf() < chance: round_tree(points, colors, at, rng.randf_range(0.8, 1.15), shadow)
		y += spacing
	# Little boats on the lake and the pier off the Lakeside beach.
	var pier := px(Vector2(0.49, 0.628))
	quad(points, colors, pier + Vector2(-1.5, -18), Vector2(3, 0), Vector2(0, 18), Color("#8a6a48"))
	for boat in [Vector2(0.43, 0.56), Vector2(0.53, 0.47), Vector2(0.4, 0.46)]:
		var at := px(boat)
		tri(points, colors, at + Vector2(-4, 0), at + Vector2(4, 0), at + Vector2(0, 2), Color(1, 1, 1, 0.9))
		tri(points, colors, at + Vector2(0, -6), at + Vector2(0, -0.5), at + Vector2(3.5, -0.5), Color(1, 1, 1, 0.8))
	return {"points": points, "colors": colors}

static func tri(points: PackedVector2Array, colors: PackedColorArray, a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	points.append_array(PackedVector2Array([a, b, c]))
	for corner in range(3): colors.append(color)

static func quad(points: PackedVector2Array, colors: PackedColorArray, corner: Vector2, u: Vector2, v: Vector2, color: Color) -> void:
	tri(points, colors, corner, corner + u, corner + u + v, color)
	tri(points, colors, corner, corner + u + v, corner + v, color)

## A gabled roof square to its street: the sunny slope lighter.
static func building(points: PackedVector2Array, colors: PackedColorArray, at: Vector2, along: Vector2, extent: Vector2, tint: Color, shadow: Color) -> void:
	var u := along * extent.x
	var v := along.orthogonal() * extent.y
	var corner := at - u * 0.5 - v * 0.5
	quad(points, colors, corner + Vector2(1.6, 1.6), u, v, shadow)
	var sunny := v.normalized().dot(Vector2(SUN.x, SUN.y)) < 0.0
	quad(points, colors, corner, u, v * 0.5, tint.lightened(0.12) if sunny else tint.darkened(0.18))
	quad(points, colors, corner + v * 0.5, u, v * 0.5, tint.darkened(0.18) if sunny else tint.lightened(0.12))

## A low-poly pine: a cone seen from the side, lit from the left.
static func pine(points: PackedVector2Array, colors: PackedColorArray, at: Vector2, scale_by: float, shadow: Color) -> void:
	var top := at + Vector2(0, -9) * scale_by
	var left := at + Vector2(-4, 1.5) * scale_by
	var right := at + Vector2(4, 1.5) * scale_by
	var foot := at + Vector2(0, 1.5) * scale_by
	tri(points, colors, at + Vector2(-2, 2) * scale_by, at + Vector2(7, 3) * scale_by, at + Vector2(4, -1) * scale_by, shadow)
	tri(points, colors, top, left, foot, Color("#3f8a4c"))
	tri(points, colors, top, foot, right, Color("#1f4f2c"))

## A broadleaf tree: an octagon crown with a lit cap.
static func round_tree(points: PackedVector2Array, colors: PackedColorArray, at: Vector2, scale_by: float, shadow: Color) -> void:
	for layer in [[Vector2(1.8, 1.8), 4.2, shadow], [Vector2.ZERO, 4.2, Color("#3d7a3c")], [Vector2(-0.9, -0.9), 2.6, Color("#5da04f")]]:
		var centre: Vector2 = at + layer[0] * scale_by
		var radius: float = layer[1] * scale_by
		for side in range(8):
			tri(points, colors, centre, centre + Vector2.from_angle(TAU * side / 8.0) * radius, centre + Vector2.from_angle(TAU * (side + 1) / 8.0) * radius, layer[2])

## Where a road crosses a river: the crossing point and the road's direction there.
static func bridges(roads: Array[Dictionary], rivers: Array[PackedVector2Array]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for road in roads:
		var line: PackedVector2Array = road.points
		for index in range(line.size() - 1):
			for river in rivers:
				for bend in range(river.size() - 1):
					var hit: Variant = Geometry2D.segment_intersects_segment(line[index], line[index + 1], river[bend], river[bend + 1])
					if hit != null: result.append({"at": hit, "along": (line[index + 1] - line[index]).normalized()})
	return result
