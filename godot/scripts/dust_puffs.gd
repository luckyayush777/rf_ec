
extends MultiMeshInstance3D
## Dust lifted by the blowers: soft puffs that billow off the surface and fade, and felt flakes
## that tumble down. A small pool simulated on the CPU and drawn in one call; the close-up view
## shows the same MultiMesh in its own world.
const CAPACITY := 160
const SHADER = preload("res://shaders/dust_puff.gdshader")
const PUFF_COLOR := Color(0.64, 0.61, 0.56)
const FLAKE_COLOR := Color(0.5, 0.47, 0.43)
const CHIP_COLOR := Color(0.47, 0.47, 0.45)
## Mask bytes lifted per puff, and thick-felt bytes per flake.
const BYTES_PER_PUFF := 180.0
const BYTES_PER_FLAKE := 500.0

var particles: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var puff_budget := 0.0
var flake_budget := 0.0
var buffer := PackedFloat32Array()

func _init() -> void:
	name = "DustPuffs"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Instances move freely in world space; never cull the pool by its first positions.
	custom_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))
	var quad := QuadMesh.new()
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("puff", make_texture())
	quad.material = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = CAPACITY
	multimesh.visible_instance_count = 0
	buffer.resize(CAPACITY * 16)
	rng.randomize()
	visible = false

## Emits dust from a cleaned spot. The air glances off the surface, so the cloud leaves along the
## jet's reflection, lifted off the face it came from.
func burst(point: Vector3, normal: Vector3, jet: Vector3, lifted: int, felt: int) -> void:
	if jet.dot(normal) > 0.0: normal = -normal
	var away := (jet - 2.0 * jet.dot(normal) * normal).normalized()
	puff_budget = minf(puff_budget + lifted / BYTES_PER_PUFF, 8.0)
	flake_budget = minf(flake_budget + felt / BYTES_PER_FLAKE, 4.0)
	while puff_budget >= 1.0:
		puff_budget -= 1.0
		spawn(point, normal, away, false)
	while flake_budget >= 1.0:
		flake_budget -= 1.0
		spawn(point, normal, away, true)

## Hard paste glaze breaking off under a blade: small grey chips that hop off and fall.
func chip(point: Vector3, normal: Vector3, count: int) -> void:
	for i in range(mini(count, 6)):
		spawn(point, normal, normal, true, CHIP_COLOR, rng.randf_range(0.004, 0.009))

## Scraped compound leaving a paste face: crumbs or a clump pushed off ahead of the blade.
## Slow and small, sized to the face, so they roll off rather than fly.
func debris(point: Vector3, normal: Vector3, direction: Vector3, count: int, color: Color, size: float) -> void:
	for i in range(mini(count, 6)):
		spawn(point, normal, direction, true, color, size * rng.randf_range(0.7, 1.3), size * 4.0)

## speed: launch speed; 0 uses the dust's own range.
func spawn(point: Vector3, normal: Vector3, away: Vector3, flake: bool, color := Color(), size := 0.0, speed := 0.0) -> void:
	if particles.size() >= CAPACITY: particles.pop_front()
	var spread := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	particles.append({
		"position": point + normal * (size if speed > 0.0 else 0.006) + spread * (size if speed > 0.0 else 0.015),
		"velocity": (away * 0.6 + normal * 0.5 + spread * 0.35).normalized() * (speed * rng.randf_range(0.6, 1.2) if speed > 0.0 else rng.randf_range(0.25, 0.6)),
		"age": 0.0,
		"life": rng.randf_range(1.1, 1.8) if flake else rng.randf_range(0.7, 1.4),
		"size": size if size > 0.0 else rng.randf_range(0.01, 0.018) if flake else rng.randf_range(0.08, 0.18),
		"color": color if color != Color() else FLAKE_COLOR if flake else PUFF_COLOR,
		# Debris falls on the paste face's scale, so it is seen rolling off the die.
		"fall": size * 30.0 if speed > 0.0 else 2.2,
		"flake": flake})
	visible = true

func _process(delta: float) -> void:
	if particles.is_empty(): return
	var alive: Array[Dictionary] = []
	for particle in particles:
		particle.age += delta
		if particle.age >= particle.life: continue
		if particle.flake:
			particle.velocity = particle.velocity * exp(-1.2 * delta) + Vector3.DOWN * particle.fall * delta
		else:
			# Fine dust loses its push quickly and hangs, rising a little in the air.
			particle.velocity = particle.velocity * exp(-2.6 * delta) + Vector3.UP * 0.04 * delta
		particle.position += particle.velocity * delta
		alive.append(particle)
	particles = alive
	for i in range(alive.size()):
		var particle: Dictionary = alive[i]
		var t: float = particle.age / particle.life
		var size: float = particle.size if particle.flake else lerpf(particle.size * 0.3, particle.size, 1.0 - pow(1.0 - t, 2.0))
		var color: Color = particle.color
		var at: Vector3 = particle.position
		var offset := i * 16
		buffer[offset] = size
		buffer[offset + 1] = 0.0
		buffer[offset + 2] = 0.0
		buffer[offset + 3] = at.x
		buffer[offset + 4] = 0.0
		buffer[offset + 5] = size
		buffer[offset + 6] = 0.0
		buffer[offset + 7] = at.y
		buffer[offset + 8] = 0.0
		buffer[offset + 9] = 0.0
		buffer[offset + 10] = size
		buffer[offset + 11] = at.z
		buffer[offset + 12] = color.r
		buffer[offset + 13] = color.g
		buffer[offset + 14] = color.b
		buffer[offset + 15] = (0.9 if particle.flake else 0.35) * smoothstep(0.0, 0.08, t) * pow(1.0 - t, 1.5)
	multimesh.buffer = buffer
	multimesh.visible_instance_count = alive.size()
	visible = not alive.is_empty()

## A soft, ragged round puff.
static func make_texture() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	noise.fractal_octaves = 3
	noise.seed = 77
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var grain := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var edge := clampf(1.0 - Vector2(x - 31.5, y - 31.5).length() / 32.0, 0.0, 1.0)
			var shade := 0.88 + 0.12 * grain
			image.set_pixel(x, y, Color(shade, shade, shade, clampf(edge * edge * (0.45 + 0.75 * grain), 0.0, 1.0)))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
