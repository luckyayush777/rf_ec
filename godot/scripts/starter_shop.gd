extends RefCounted
## The inexpensive first workshop. Native furniture keeps the GPU and tool scales intact.
const Contract = preload("res://scripts/asset_contract.gd")
const Room = preload("res://scripts/shop_interior.gd")
const FLOOR_Y := -4.5
const FLOOR_AREA := Rect2(Vector2(10.5, -16.5), Vector2(22.0, 26.0))

static func prepare(bench: Node3D) -> void:
	var desk: Node3D = bench.get_node("RepairDesk")
	desk.position = Vector3(18, -0.29260135, -5)
	# 2.4 x 1.6 m, down from 4 x 2.4 m. Never scale the tools or the card with the table.
	desk.get_node("Tabletop").scale = Vector3(0.6, 1, 2.0 / 3.0)
	for name in ["FrontApron", "RearApron"]:
		var apron: Node3D = desk.get_node(name)
		apron.scale.x = 0.6
		apron.position.z = 3.5 if name == "FrontApron" else -3.5
	for node in desk.get_children():
		var name := String(node.name)
		if name.begins_with("Leg") or name.begins_with("Foot"):
			node.position.x = signf(node.position.x) * 5.4
			node.position.z = signf(node.position.z) * 3.4
		elif name.begins_with("Grid") or name.begins_with("MatPocket") or name == "MatLabel" or name == "SpareParts":
			node.hide()
		elif name.begins_with("Tray"):
			node.position += Vector3(0.6, 0, -1.8)
		elif name.begins_with("Lamp"):
			node.position += Vector3(0.5, 0, 0.3)
	var mat: Node3D = desk.get_node("Mat")
	mat.position = Vector3(-1.8, 0.024, 1.7)
	mat.scale = Vector3(7.0 / 10.5, 1, 3.6 / 7.4)
	desk.get_node("Toolbox").position = Vector3(-0.5, 0.015, -2)
	var card_bounds: AABB = bench.gpu.global_transform * Contract.bounds_in(bench.gpu)
	bench.gpu.global_position += desk.global_position + Vector3(-1.2, 0.275, 2.0) - card_bounds.get_center()
	bench.computer.position = Vector3(12.5, FLOOR_Y, 4)
	bench.computer.rotation.y = PI * 0.5
	bench.delivery_box.position = desk.global_position + Vector3(-4, 0.01, 1.0)
	bench.get_node("ThermalCameraStand").position = desk.global_position + Vector3(5.0, 1.055, -2.5)
	bench.get_node("ThermalCameraStand").hide()
	bench.get_node("ThermalCameraBox").hide()
	bench.testing_desk.hide()
	bench.test_monitor.hide()
	bench.queue_monitor.hide()
	bench.camera_rig.spawn_position = Vector3(17, -4.35, 3)
	bench.camera_rig.respawn()
	# A tired wooden top and an old rubber mat, with a useful pool of light over the work.
	desk.get_node("Tabletop").material_override = Room.flat(Color("514334"), 0.95)
	mat.material_override = Room.flat(Color("303f39"), 0.95)
	var lamp := OmniLight3D.new()
	lamp.name = "BenchTaskLight"
	lamp.position = Vector3(-3.0, 2.8, -1.7)
	lamp.light_color = Color("ffce8a")
	lamp.light_energy = 1.8
	lamp.omni_range = 10.0
	lamp.shadow_enabled = true
	desk.add_child(lamp)

static func enclose(bench: Node3D) -> void:
	var room: Node3D = bench.get_node("ShopInterior")
	room.get_node("Model").hide()
	var shell := Node3D.new()
	shell.name = "StarterShell"
	room.add_child(shell)
	shell.global_transform = Transform3D.IDENTITY
	var plaster := Room.flat(Color("655e4d"), 0.98)
	var concrete := Room.flat(Color("444440"), 1.0)
	var wood := Room.flat(Color("332c26"), 0.95)
	room.piece(shell, "StarterFloor", Vector3(10, -4.8, -17), Vector3(33.8, FLOOR_Y, 10), concrete)
	room.piece(shell, "StarterLeftWall", Vector3(10, FLOOR_Y, -17), Vector3(10.5, 10.5, 10), plaster)
	room.piece(shell, "StarterBackWall", Vector3(10, FLOOR_Y, -17), Vector3(33.8, 10.5, -16.5), plaster)
	room.piece(shell, "StarterFrontLeft", Vector3(10, FLOOR_Y, 9.5), Vector3(14.5, 10.5, 10), plaster)
	room.piece(shell, "StarterFrontRight", Vector3(19.5, FLOOR_Y, 9.5), Vector3(33.8, 10.5, 10), plaster)
	room.piece(shell, "StarterDoorHeader", Vector3(14.5, 6.5, 9.5), Vector3(19.5, 10.5, 10), plaster)
	var ceiling: MeshInstance3D = room.piece(shell, "StarterCeiling", Vector3(10, 10.5, -17), Vector3(33.8, 10.8, 10), plaster)
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for z in [-13.0, -5.0, 3.0]:
		room.piece(shell, "CeilingBeam", Vector3(10.5, 10, z), Vector3(33, 10.5, z + 0.35), wood)
	# Retain the delivery window in its established world position and close its shorter wall.
	for entry in [["WallBackOfWindow", -17.0, Room.WINDOW_Z.x], ["WallFrontOfWindow", Room.WINDOW_Z.y, 10.0]]:
		var piece: MeshInstance3D = room.find_child(entry[0], true, false)
		piece.mesh = piece.mesh.duplicate()
		piece.mesh.size.z = entry[2] - entry[1]
		piece.position.z = (entry[1] + entry[2]) * 0.5
	for name in ["WallBelowWindow", "WallAboveWindow"]:
		var piece: MeshInstance3D = room.find_child(name, true, false)
		piece.mesh = piece.mesh.duplicate()
		piece.mesh.size.z = 27.0
		piece.position.z = -3.5
	for name in ["WallBelowWindow", "WallAboveWindow", "WallBackOfWindow", "WallFrontOfWindow"]:
		room.find_child(name, true, false).material_override = plaster
	var door: MeshInstance3D = room.get_node("EntranceDoor")
	door.global_position = Vector3(17, 1, 9.7)
	door.mesh = door.mesh.duplicate()
	door.mesh.size.x = 1.0
	door.get_node("DoorHandle").position.x = 0.38
	# Sparse scuffs on the floor and worn patches on the wall, kept outside working surfaces.
	var stain := Room.flat(Color("373a33"), 1.0)
	for index in range(12):
		var x := 11.5 + fmod(index * 7.3, 20.0)
		var z := -15.0 + fmod(index * 5.7, 23.0)
		room.add_block(shell, "FloorWear", Vector3(0.4 + fmod(index * 0.63, 1.5), 0.003, 0.12), Vector3(x, FLOOR_Y + 0.005, z), stain)
	for index in range(5):
		room.add_block(shell, "WallWear", Vector3(0.008, 0.4 + index * 0.14, 2.4), Vector3(10.51, -2.2 + index * 0.36, -13 + index * 4.3), stain)

static func refurbish(bench: Node3D) -> void:
	var room: Node3D = bench.get_node("ShopInterior")
	for name in ["StarterLeftWall", "StarterBackWall", "StarterFrontLeft", "StarterFrontRight", "StarterDoorHeader", "StarterCeiling",
			"WallBelowWindow", "WallAboveWindow", "WallBackOfWindow", "WallFrontOfWindow"]:
		room.find_child(name, true, false).material_override = Room.flat(Color("ada991"), 0.85)
	for mesh in room.get_node("StarterShell").get_children():
		if String(mesh.name).begins_with("FloorWear") or String(mesh.name).begins_with("WallWear"): mesh.hide()
	bench.get_node("RepairDesk/Tabletop").material_override = Room.flat(Color("94704b"), 0.8)
