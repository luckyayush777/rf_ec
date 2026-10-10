extends Node
## Session ownership, the supply website, expansion squares and placement of purchased workshop
## equipment. `build_view.gd` drives placement, stashing and expansions with its plan pointer.
signal changed
signal notice(text: String)
const Contract = preload("res://scripts/asset_contract.gd")
const Starter = preload("res://scripts/starter_shop.gd")
const AudioMix = preload("res://scripts/audio_mix.gd")
## A heavy build-mode thud as equipment lands; each expansion slot plays it lower and heavier.
const PLACE_SOUND = preload("res://assets/sounds/build_place.wav")
const PLACE_GAIN_DB := -3.0
const EXPANSION_PITCH := 0.78
const CATALOG := {
	"air-blower": {"name": "Air blower", "price": 35, "section": "Tools", "description": "Starter tool. Clean the exterior fan without opening the card."},
	"screwdriver": {"name": "Precision screwdriver", "price": 30, "section": "Tools", "description": "Open the cooler and fan for internal service."},
	"spudger": {"name": "Plastic spudger", "price": 12, "section": "Tools", "description": "Scrape hardened thermal compound."},
	"ipa-wipe": {"name": "IPA cleaning kit", "price": 18, "section": "Tools", "description": "Clean paste residue and the fan shaft. Refills included for now."},
	"paste-syringe": {"name": "Thermal paste syringe", "price": 25, "section": "Tools", "description": "Apply fresh compound. Refills included for now."},
	"fan-oiler": {"name": "Bearing oil dropper", "price": 20, "section": "Tools", "description": "Service a dry fan bearing. Refills included for now."},
	"loupe": {"name": "Jeweller's loupe", "price": 45, "section": "Tools", "description": "Magnify contacts and inspect the card."},
	"thermal-camera": {"name": "Thermal camera", "price": 350, "section": "Tools", "description": "Inspect surface temperatures. Arrives on its bench stand."},
	"dev-blower": {"name": "Dev blower", "price": 500, "section": "Tools", "description": "Development tool: fast, broad dust removal."},
	"test-station": {"name": "GPU testing station", "price": 400, "section": "Equipment", "description": "Test board, monitor and compact table. Place it to unlock repair and diagnosis work."},
	"queue-display": {"name": "Job queue display", "price": 120, "section": "Equipment", "description": "Freestanding display for your current repair."},
	"lighting": {"name": "Workshop lighting", "price": 150, "section": "Workshop", "description": "Upgrade the room lights for a brighter workday."},
	"refurbishment": {"name": "Paint and bench refinish", "price": 250, "section": "Workshop", "description": "Fresh walls, a cleaned floor and a refinished worktop."},
	"shop-expansion": {"name": "Shop expansion", "price": 600, "section": "Workshop", "description": "A 5.2 m square of floor. Plop it against the shop in build view and the wall between is knocked through."}}
## Bought repeatedly in build view, one square at a time, up to `Starter.MAX_EXPANSIONS`.
const EXPANSION := "shop-expansion"
## Furniture the shop starts with: always owned and placed, never sold or stashed, but moved
## and turned in build view like bought equipment.
const FIXTURES := {"repair-desk": {"name": "Repair desk"}, "shop-computer": {"name": "Shop computer"}}
## Worked from the front (+Z): placement keeps standing room clear on that side.
const WORKSTATIONS := ["test-station", "repair-desk", "shop-computer"]
## Standing room in front of a workstation, in world units (0.44 m).
const AISLE_DEPTH := 2.2
const FAULT_TOOLS := {
	"dust": ["air-blower", "screwdriver"],
	"paste": ["screwdriver", "spudger", "ipa-wipe", "paste-syringe"],
	"bearing": ["screwdriver", "ipa-wipe", "fan-oiler"]}
var bench: Node3D
var jobs: Node
var owned := {"air-blower": true}
## Built expansion squares (x, z floor rectangles); the room and placement floor grow with each.
var expansion_squares: Array[Rect2] = []
var expansions: int:
	get: return expansion_squares.size()
## A real finite wallet still exists; the requested sandbox setting bypasses purchase costs.
var unlimited_funds := true
var purchases: Array[Dictionary] = []
var equipment: Dictionary = {}
var placed: Dictionary = {}
var placement_id := ""
var original_pose := Transform3D.IDENTITY
## Where the piece being placed last was; the repair desk's riders follow each change.
var last_pose := Transform3D.IDENTITY
var footprint: MeshInstance3D
var footprint_material: StandardMaterial3D
var placement_valid := false
var place_audio: AudioStreamPlayer
var muted := false

func configure(world: Node3D, repair_jobs: Node) -> void:
	bench = world
	jobs = repair_jobs
	place_audio = AudioStreamPlayer.new()
	place_audio.name = "BuildPlaceSound"
	place_audio.stream = PLACE_SOUND
	place_audio.volume_db = PLACE_GAIN_DB
	place_audio.bus = AudioMix.BUILD_PLACE
	add_child(place_audio)
	for id in bench.tools.TOOLS: bench.tools.set_locked(id, not owns(id))
	var station := Node3D.new()
	station.name = "TestingEquipment"
	bench.add_child(station)
	station.position = Vector3(19, 0, 0)
	for node in [bench.testing_desk, bench.test_monitor, bench.get_node("BoardToMonitorCable")]:
		node.reparent(station, true)
		node.show()
	station.position = Vector3(26, 0, 4)
	station.hide()
	equipment["test-station"] = station
	equipment["queue-display"] = bench.queue_monitor
	bench.queue_monitor.position = Vector3(16, Starter.FLOOR_Y, -14)
	bench.testing_station.available = false
	equipment["repair-desk"] = bench.get_node("RepairDesk")
	equipment["shop-computer"] = bench.computer
	for id in FIXTURES:
		placed[id] = true
		# Their furniture collision already exists (the toolbox deliberately has none); placing
		# them only switches it.
		for mesh in equipment[id].find_children("*", "MeshInstance3D", true, false): mesh.set_meta("equipment_collision", true)
	footprint = MeshInstance3D.new()
	footprint.name = "EquipmentFootprint"
	var shape := BoxMesh.new()
	shape.size = Vector3(1, 0.025, 1)
	footprint.mesh = shape
	footprint_material = StandardMaterial3D.new()
	footprint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	footprint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	footprint.material_override = footprint_material
	footprint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bench.add_child(footprint)
	footprint.hide()

## For the expansion, true once every slot is built. Fixtures are always owned.
func owns(id: String) -> bool:
	if id == EXPANSION: return expansions >= Starter.MAX_EXPANSIONS
	return FIXTURES.has(id) or owned.get(id, false)

func item_name(id: String) -> String:
	return FIXTURES[id].name if FIXTURES.has(id) else CATALOG[id].name

func floor_rects() -> Array[Rect2]:
	return Starter.floor_rects(expansion_squares)

## Progress shown beside a repeatable item's name; empty for one-time purchases.
func stock_text(id: String) -> String:
	return "%d/%d BUILT" % [expansions, Starter.MAX_EXPANSIONS] if id == EXPANSION else ""

func is_available(id: String) -> bool:
	return owns(id) and (not equipment.has(id) or placed.get(id, false))

func catalog_ids(section: String) -> Array[String]:
	var ids: Array[String] = []
	for id in CATALOG:
		if CATALOG[id].section == section and (id != "dev-blower" or OS.is_debug_build()): ids.append(id)
	return ids

func money_text() -> String:
	return "UNLIMITED" if unlimited_funds else "$%d" % jobs.balance

func set_unlimited(value: bool) -> void:
	unlimited_funds = value
	changed.emit()
	jobs.changed.emit()

func can_afford(id: String) -> bool:
	return unlimited_funds or jobs.balance >= CATALOG[id].price

## Debits the wallet, or refuses with a notice.
func charge(id: String) -> bool:
	if not can_afford(id):
		notice.emit("Not enough money for %s." % CATALOG[id].name)
		return false
	if not unlimited_funds: jobs.balance -= CATALOG[id].price
	return true

## One-time items. Expansions are bought where they are put down, with `build_expansion`.
func purchase(id: String) -> bool:
	if not CATALOG.has(id) or owns(id) or (id == "dev-blower" and not OS.is_debug_build()): return false
	if id == EXPANSION:
		notice.emit("Plop expansions down in build view (B).")
		return false
	if not charge(id): return false
	var item: Dictionary = CATALOG[id]
	owned[id] = true
	record(id, item.name)
	if id in bench.tools.TOOLS: bench.tools.set_locked(id, false)
	if id == "thermal-camera": bench.tools.thermal_stand.show()
	if id == "refurbishment": Starter.refurbish(bench)
	if id == "lighting" and bench.day_cycle != null: bench.day_cycle.update()
	notice.emit("Purchased %s. %s" % [item.name, "It waits in storage; place it in build view (B)." if equipment.has(id) else "Ready to use."])
	changed.emit()
	jobs.changed.emit()
	return true

func record(id: String, title: String) -> void:
	purchases.push_front({"id": id, "name": title, "price": CATALOG[id].price, "paid": 0 if unlimited_funds else CATALOG[id].price})

## Whether another square may be bought now; the build view shows why not otherwise.
func expansion_block() -> String:
	if expansions >= Starter.MAX_EXPANSIONS: return "All %d expansions are built." % Starter.MAX_EXPANSIONS
	if not can_afford(EXPANSION): return "Not enough money for a shop expansion."
	return ""

## Buys and builds an expansion square where the build view put it down.
func build_expansion(square: Rect2) -> bool:
	if expansion_block() != "" or not Starter.expansion_fits(expansion_squares, square) or not charge(EXPANSION): return false
	expansion_squares.append(square)
	Starter.build_plan(bench, expansion_squares)
	var plan: Node3D = bench.get_node("ShopInterior/StarterShell/Plan")
	bench.picker.add_meshes(plan)
	bench.thermal_viewer.add_meshes(plan)
	play_place(EXPANSION_PITCH)
	var title := "%s %d/%d" % [CATALOG[EXPANSION].name, expansions, Starter.MAX_EXPANSIONS]
	record(EXPANSION, title)
	notice.emit("Built %s. The wall between is knocked through; arrange equipment on the new floor." % title)
	changed.emit()
	jobs.changed.emit()
	return true

func missing_for(job: Dictionary) -> Array[String]:
	var required: Array[String] = []
	if job.get("exterior_clean", false): required.append("air-blower")
	else:
		required.append("test-station")
		if not jobs.is_tech(job): required.append("thermal-camera")
		for fault in job.faults:
			for id in FAULT_TOOLS.get(fault, []):
				if id not in required: required.append(id)
	var missing: Array[String] = []
	for id in required:
		if not is_available(id): missing.append(("Place " if owns(id) else "") + CATALOG[id].name)
	return missing

func begin_placement(id: String) -> bool:
	if not owns(id) or not equipment.has(id) or placement_id != "": return false
	if hands_busy() or not bench.settled() or not station_free(id) or (id == "repair-desk" and not desk_clear()): return false
	placement_id = id
	original_pose = equipment[id].global_transform
	last_pose = original_pose
	equipment[id].show()
	set_collision(equipment[id], false)
	if id == "test-station": bench.testing_station.available = false
	changed.emit()
	notice.emit("Placing %s: click a clear floor spot. R rotates, %sEsc or right-click cancels." % [item_name(id), "" if FIXTURES.has(id) else "X stashes, "])
	return true

## Building and arranging needs empty hands; says so when they are not.
func hands_busy() -> bool:
	if bench.inspection.held or bench.service.held_part != "" or bench.tools.equipped_tool != "" or bench.carrying_parcel():
		notice.emit("Set down the card, parts, parcel and tools before building.")
		return true
	return false

## The test station stays put while a card sits in its slot.
func station_free(id: String) -> bool:
	if id == "test-station" and (bench.testing_station.installed or bench.testing_station.moving):
		notice.emit("Take the card out of the test station before moving it.")
		return false
	return true

## The repair desk moves only with nothing loose on it: the card refitted (or still boxed), the
## tools put away and the test station empty, so everything on it can ride along.
func desk_clear() -> bool:
	var clear: bool = not bench.testing_station.installed and not bench.testing_station.moving and bench.service.removed.is_empty() and not bench.delivery_box.moving
	for id in bench.tools.TOOLS:
		if bench.tools.tool_location(id) not in ["toolbox", "stand"]: clear = false
	if not clear: notice.emit("Clear the repair desk first: refit the card, put every tool away and take the card out of the test station.")
	return clear

func rotate_placement() -> void:
	if placement_id == "": return
	equipment[placement_id].rotate_y(PI * 0.5)
	placement_valid = false
	follow()

## Carries what rides on the repair desk by however far it moved since the last call.
func follow() -> void:
	if placement_id != "repair-desk": return
	var pose: Transform3D = equipment[placement_id].global_transform
	var delta := pose * last_pose.affine_inverse()
	last_pose = pose
	if not delta.is_equal_approx(Transform3D.IDENTITY): bench.carry_with_desk(delta)

## Puts placed equipment (or the piece being placed) back into storage, out of the room.
func stash(id: String) -> bool:
	if not equipment.has(id) or not owns(id) or not station_free(id): return false
	if FIXTURES.has(id):
		notice.emit("The %s stays in the shop; move it instead." % item_name(id).to_lower())
		return false
	if placement_id != "" and placement_id != id: return false
	if placement_id == id:
		equipment[id].global_transform = original_pose
		placement_id = ""
		footprint.hide()
	elif not placed.get(id, false): return false
	placed[id] = false
	equipment[id].hide()
	set_collision(equipment[id], false)
	if id == "test-station": bench.testing_station.available = false
	notice.emit("%s stashed in storage. Place it again from build view." % item_name(id))
	changed.emit()
	jobs.changed.emit()
	return true

## Equipment in storage: owned, not on the floor and not being placed.
func stored_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in equipment:
		if owns(id) and not placed.get(id, false) and id != placement_id: ids.append(id)
	return ids

## Placed equipment whose footprint covers a floor point, or "".
func placed_at(point: Vector2) -> String:
	for id in equipment:
		if placed.get(id, false) and id != placement_id and room_rect(equipment[id]).has_point(point): return id
	return ""

## Switching collision off keeps each body's layer, so switching it on restores the same one.
func set_collision(root: Node3D, enabled: bool) -> void:
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		if enabled and not mesh.has_meta("equipment_collision"):
			mesh.create_trimesh_collision()
			mesh.set_meta("equipment_collision", true)
	for body in root.find_children("*", "StaticBody3D", true, false):
		if not enabled and body.collision_layer != 0: body.set_meta("equipment_layer", body.collision_layer)
		body.collision_layer = body.get_meta("equipment_layer", 1) if enabled else 0

## Bounds of what is shown, in `node`'s space: hidden parts (the desk's spare fittings, locked
## tools) take no floor. Everything counts while the whole piece is hidden in storage.
static func shown_bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var started := false
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not shown_under(mesh, node): continue
		var box: AABB = (node.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		bounds = bounds.merge(box) if started else box
		started = true
	return bounds if started else Contract.bounds_in(node)

static func shown_under(item: Node, root: Node) -> bool:
	while item != null and item != root:
		if item is Node3D and not item.visible: return false
		item = item.get_parent()
	return true

func room_rect(node: Node3D) -> Rect2:
	var bounds := node.global_transform * shown_bounds(node)
	return Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))

func working_aisle(node: Node3D) -> Rect2:
	var local := shown_bounds(node)
	var access: AABB = node.global_transform * AABB(Vector3(local.position.x, 0, local.end.z), Vector3(local.size.x, 0.1, AISLE_DEPTH))
	return Rect2(Vector2(access.position.x, access.position.z), Vector2(access.size.x, access.size.z))

func valid_position(node: Node3D) -> bool:
	# 2 cm off the walls: the starting PC stands that close.
	var rect := room_rect(node).grow(0.1)
	if not Starter.covers(floor_rects(), rect): return false
	# The front door's swing and the hatch counter.
	var obstacles := [Rect2(14.0, 7.7, 6.0, 2.0), Rect2(29.7, -16.5, 3.0, 19.0)]
	for id in equipment:
		if equipment[id] != node and placed.get(id, false):
			obstacles.append(room_rect(equipment[id]))
			if id in WORKSTATIONS: obstacles.append(working_aisle(equipment[id]))
	# Keep enough floor on the working side to stand at the desk, the PC keyboard, or the
	# station's monitor and PCIe slot.
	if WORKSTATIONS.any(func(id: String): return equipment[id] == node):
		var aisle := working_aisle(node)
		if not Starter.covers(floor_rects(), aisle): return false
		for obstacle in obstacles:
			if aisle.intersects(obstacle): return false
	# An empty box left on the floor keeps its spot.
	if bench.delivery_box.visible and bench.delivery_box.location == "aside": obstacles.append(room_rect(bench.delivery_box))
	var player: Vector3 = bench.camera_rig.body.global_position
	obstacles.append(Rect2(Vector2(player.x, player.z) - Vector2.ONE * 0.9, Vector2.ONE * 1.8))
	for obstacle in obstacles:
		if rect.intersects(obstacle): return false
	return true

func preview_at(point: Vector3) -> bool:
	if placement_id == "": return false
	var node: Node3D = equipment[placement_id]
	var bounds := node.global_transform * shown_bounds(node)
	var offset := point - bounds.get_center()
	# Bought pieces stand on the floor; the fixtures keep their authored height.
	offset.y = 0.0 if FIXTURES.has(placement_id) else Starter.FLOOR_Y - bounds.position.y
	node.global_position += offset
	follow()
	placement_valid = valid_position(node)
	var rect := room_rect(node)
	footprint.position = Vector3(rect.get_center().x, Starter.FLOOR_Y + 0.035, rect.get_center().y)
	footprint.scale = Vector3(rect.size.x + 0.15, 1, rect.size.y + 0.15)
	footprint_material.albedo_color = Color(0.2, 0.8, 0.45, 0.4) if placement_valid else Color(0.9, 0.2, 0.1, 0.4)
	footprint.show()
	return placement_valid

## The build view's pointer left the floor: nothing is previewed and nothing can be placed.
func hide_preview() -> void:
	placement_valid = false
	footprint.hide()

func finish_placement() -> bool:
	if placement_id == "" or not placement_valid or not valid_position(equipment[placement_id]): return false
	var id := placement_id
	placed[id] = true
	set_collision(equipment[id], true)
	if id == "test-station":
		bench.testing_station.available = true
		bench.testing_station.equipment_yaw = equipment[id].rotation.y
	placement_id = ""
	footprint.hide()
	play_place()
	notice.emit("%s placed. Click it in build view (B) to move %s." % [item_name(id), "it" if FIXTURES.has(id) else "or stash it"])
	changed.emit()
	jobs.changed.emit()
	return true

## Slightly re-pitched each time so repeated placements do not sound identical.
func play_place(pitch := 1.0) -> void:
	if muted: return
	place_audio.pitch_scale = pitch * randf_range(0.94, 1.06)
	place_audio.play()

func set_muted(value: bool) -> void:
	muted = value
	if muted: place_audio.stop()

func cancel_placement() -> void:
	if placement_id == "": return
	var id := placement_id
	equipment[id].global_transform = original_pose
	follow()
	equipment[id].visible = placed.get(id, false)
	set_collision(equipment[id], placed.get(id, false))
	if id == "test-station": bench.testing_station.available = placed.get(id, false)
	placement_id = ""
	footprint.hide()
	notice.emit("Placement cancelled." if placed.get(id, false) else "Placement cancelled. %s stays in storage until placed." % item_name(id))
	changed.emit()
