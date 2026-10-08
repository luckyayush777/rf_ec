extends Node
## Session ownership, the supply website and placement of purchased workshop equipment.
signal changed
signal notice(text: String)
const Contract = preload("res://scripts/asset_contract.gd")
const Starter = preload("res://scripts/starter_shop.gd")
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
	"shop-expansion": {"name": "Shop expansion", "price": 600, "section": "Workshop", "description": "Knock through the wall left of the delivery window for 2 m more floor to place equipment. Buy once per slot."}}
## Bought repeatedly, one slot at a time, up to `Starter.MAX_EXPANSIONS`.
const EXPANSION := "shop-expansion"
const FAULT_TOOLS := {
	"dust": ["air-blower", "screwdriver"],
	"paste": ["screwdriver", "spudger", "ipa-wipe", "paste-syringe"],
	"bearing": ["screwdriver", "ipa-wipe", "fan-oiler"]}
var bench: Node3D
var jobs: Node
var owned := {"air-blower": true}
## Expansion slots built; the room and placement floor grow with each.
var expansions := 0
## A real finite wallet still exists; the requested sandbox setting bypasses purchase costs.
var unlimited_funds := true
var purchases: Array[Dictionary] = []
var equipment: Dictionary = {}
var placed: Dictionary = {}
var placement_id := ""
var original_pose := Transform3D.IDENTITY
var footprint: MeshInstance3D
var footprint_material: StandardMaterial3D
var placement_valid := false

func configure(world: Node3D, repair_jobs: Node) -> void:
	bench = world
	jobs = repair_jobs
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

## For the expansion, true once every slot is built.
func owns(id: String) -> bool:
	if id == EXPANSION: return expansions >= Starter.MAX_EXPANSIONS
	return owned.get(id, false)

func floor_area() -> Rect2:
	return Starter.floor_area(expansions)

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

func purchase(id: String) -> bool:
	if not CATALOG.has(id) or owns(id) or (id == "dev-blower" and not OS.is_debug_build()): return false
	var item: Dictionary = CATALOG[id]
	if not unlimited_funds and jobs.balance < item.price:
		notice.emit("Not enough money for %s." % item.name)
		return false
	if not unlimited_funds: jobs.balance -= item.price
	var title: String = item.name
	if id == EXPANSION:
		expansions += 1
		title += " %d/%d" % [expansions, Starter.MAX_EXPANSIONS]
		Starter.expand(bench, expansions)
	else: owned[id] = true
	purchases.push_front({"id": id, "name": title, "price": item.price, "paid": 0 if unlimited_funds else item.price})
	if id in bench.tools.TOOLS: bench.tools.set_locked(id, false)
	if id == "thermal-camera": bench.tools.thermal_stand.show()
	if id == "refurbishment": Starter.refurbish(bench)
	if id == "lighting" and bench.day_cycle != null: bench.day_cycle.update()
	var follow_up := "Choose PLACE on the shop page to arrange it." if equipment.has(id) else "The back wall moved out; place equipment in the new space." if id == EXPANSION else "Ready to use."
	notice.emit("Purchased %s. %s" % [title, follow_up])
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
	if bench.testing_station.installed or bench.inspection.held or bench.service.held_part != "" or bench.tools.equipped_tool != "" or bench.carrying_parcel() or not bench.ready_for_action():
		notice.emit("Set down the card and tools, and empty the test station before moving equipment.")
		return false
	placement_id = id
	original_pose = equipment[id].global_transform
	equipment[id].show()
	set_collision(equipment[id], false)
	if id == "test-station": bench.testing_station.available = false
	bench.computer.leave()
	bench.camera_rig.set_captured(true)
	bench.hud.set_status("Place %s: look at a clear floor spot. E/click place, R rotate, Q cancel." % CATALOG[id].name)
	return true

func set_collision(root: Node3D, enabled: bool) -> void:
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		if enabled and not mesh.has_meta("equipment_collision"):
			mesh.create_trimesh_collision()
			mesh.set_meta("equipment_collision", true)
	for body in root.find_children("*", "StaticBody3D", true, false): body.collision_layer = 1 if enabled else 0

func room_rect(node: Node3D) -> Rect2:
	var bounds := node.global_transform * Contract.bounds_in(node)
	return Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))

func working_aisle(node: Node3D) -> Rect2:
	var local := Contract.bounds_in(node)
	var access: AABB = node.global_transform * AABB(Vector3(local.position.x, 0, local.end.z), Vector3(local.size.x, 0.1, 2.2))
	return Rect2(Vector2(access.position.x, access.position.z), Vector2(access.size.x, access.size.z))

func valid_position(node: Node3D) -> bool:
	var rect := room_rect(node).grow(0.25)
	if not floor_area().encloses(rect): return false
	var table: MeshInstance3D = bench.get_node("RepairDesk/Tabletop")
	var bounds := table.global_transform * table.get_aabb()
	var obstacles := [Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)),
		room_rect(bench.computer), Rect2(14.0, 7.7, 6.0, 2.0), Rect2(29.7, -16.5, 3.0, 19.0)]
	for id in equipment:
		if equipment[id] != node and placed.get(id, false):
			obstacles.append(room_rect(equipment[id]))
			if id == "test-station": obstacles.append(working_aisle(equipment[id]))
	# Keep enough floor on the working side to stand at the monitor and PCIe slot.
	if node == equipment["test-station"]:
		var aisle := working_aisle(node)
		if not floor_area().encloses(aisle): return false
		for obstacle in obstacles:
			if aisle.intersects(obstacle): return false
	var player: Vector3 = bench.camera_rig.body.global_position
	obstacles.append(Rect2(Vector2(player.x, player.z) - Vector2.ONE * 0.9, Vector2.ONE * 1.8))
	for obstacle in obstacles:
		if rect.intersects(obstacle): return false
	return true

func preview_at(point: Vector3) -> bool:
	if placement_id == "": return false
	var node: Node3D = equipment[placement_id]
	var bounds := node.global_transform * Contract.bounds_in(node)
	var offset := point - bounds.get_center()
	offset.y = Starter.FLOOR_Y - bounds.position.y
	node.global_position += offset
	placement_valid = valid_position(node)
	var rect := room_rect(node)
	footprint.position = Vector3(rect.get_center().x, Starter.FLOOR_Y + 0.035, rect.get_center().y)
	footprint.scale = Vector3(rect.size.x + 0.15, 1, rect.size.y + 0.15)
	footprint_material.albedo_color = Color(0.2, 0.8, 0.45, 0.4) if placement_valid else Color(0.9, 0.2, 0.1, 0.4)
	footprint.show()
	return placement_valid

func _process(_delta: float) -> void:
	if placement_id == "": return
	var camera: Camera3D = bench.camera_rig.camera
	var center: Vector2 = bench.get_viewport().get_visible_rect().size * 0.5
	var point = Plane(Vector3.UP, Starter.FLOOR_Y).intersects_ray(camera.project_ray_origin(center), camera.project_ray_normal(center))
	placement_valid = false
	footprint.hide()
	if point != null and camera.global_position.distance_to(point) < 26.0: preview_at(point)

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
	notice.emit("%s placed. Use MOVE in the shop to rearrange it." % CATALOG[id].name)
	changed.emit()
	jobs.changed.emit()
	return true

func cancel_placement() -> void:
	if placement_id == "": return
	var id := placement_id
	equipment[id].global_transform = original_pose
	equipment[id].visible = placed.get(id, false)
	set_collision(equipment[id], placed.get(id, false))
	if id == "test-station": bench.testing_station.available = placed.get(id, false)
	placement_id = ""
	footprint.hide()
	notice.emit("Placement cancelled. Purchases stay in storage until placed.")

func handle_input(event: InputEvent) -> void:
	if not bench.camera_rig.captured:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			bench.camera_rig.set_captured(true)
			return
	if event is InputEventMouseMotion and bench.camera_rig.captured: bench.camera_rig.look(event.relative)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E: finish_placement()
			KEY_R:
				equipment[placement_id].rotate_y(PI * 0.5)
				placement_valid = false
			KEY_Q, KEY_ESCAPE, KEY_TAB: cancel_placement()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: finish_placement()
