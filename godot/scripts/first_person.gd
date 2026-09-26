extends "res://scripts/orbit_camera.gd"
## First-person runtime. Inherited orbit poses are used only by legacy acceptance fixtures.
const REACH := 11.0
const SPEED := 10.0
var legacy_test_mode := false
var body: CharacterBody3D
var look_pitch := -0.22
var look_yaw := 0.0
var walking_enabled := true
var captured := false
var movement_override := Vector2.ZERO

func _ready() -> void:
	if legacy_test_mode: return
	camera.fov = 65.0
	body = CharacterBody3D.new()
	body.name = "PlayerBody"
	body.collision_layer = 2
	body.collision_mask = 1
	add_child(body)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.8
	capsule.height = 8.0
	shape.shape = capsule
	shape.position.y = 4.0
	body.add_child(shape)
	body.position = Vector3(-3, -4.35, 9)
	set_captured(true)
	update_camera()

func build_collisions(world: Node3D) -> void:
	if legacy_test_mode: return
	# Static furniture only. Service parts and tools must remain movable/pickable.
	for branch in [world.get_node("ShopInterior"), world.get_node("RepairDesk"), world.get_node("TestingDesk")]:
		for mesh in branch.find_children("*", "MeshInstance3D", true, false):
			if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
			if world.get_node("RepairDesk/Toolbox").is_ancestor_of(mesh): continue
			mesh.create_trimesh_collision()

func set_captured(value: bool) -> void:
	captured = value
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE

func look(relative: Vector2) -> void:
	look_yaw -= relative.x * 0.0025
	look_pitch = clampf(look_pitch - relative.y * 0.0025, -1.45, 1.45)
	update_camera()

func update_camera() -> void:
	if body == null: return
	camera.global_position = body.global_position + Vector3(0, 7.7, 0)
	camera.global_rotation = Vector3(look_pitch, look_yaw, 0)

func _physics_process(delta: float) -> void:
	if legacy_test_mode or body == null: return
	var movement := movement_override
	if captured and walking_enabled:
		movement += Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	else: movement = Vector2.ZERO
	var direction := Basis(Vector3.UP, look_yaw) * Vector3(movement.x, 0, movement.y).limit_length()
	body.velocity.x = direction.x * SPEED
	body.velocity.z = direction.z * SPEED
	if not body.is_on_floor(): body.velocity.y -= 35.0 * delta
	else: body.velocity.y = 0.0
	body.move_and_slide()
	update_camera()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and not legacy_test_mode:
		set_captured(false)

func _exit_tree() -> void:
	if not legacy_test_mode: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
