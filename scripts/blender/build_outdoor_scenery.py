"""Author the view out of the shop window: a cozy alpine valley. Refuses to overwrite saved edits.
blender --background --factory-startup --python scripts/blender/build_outdoor_scenery.py
Use -- --force only to intentionally rebuild this source, discarding manual edits.

Everything is authored in Godot world units (1 unit = 0.2 m, +X looks out of the window, +Y up)
and converted to Blender's Z-up axes on creation, so the glTF export lands back exactly where it
was designed. The shop's window wall is at x = 34; the yard runs out to the fence at x = 77.

Layout, near to far: the lawn yard with stepping stones, soft pines and a rustic fence; a flower
meadow falling to a lake; a village on the near shore with a church, a pier and boats; pine-
forested hills; a snow-capped range. Colours are painted into a vertex colour attribute; Godot's
`scenery.gdshader` lights, hazes and sways it by object name (see `outdoor_scenery.gd`).
"""
import math
import random
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector, noise

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'models/outdoor-scenery.blend'
if DEST.exists() and '--force' not in sys.argv:
    raise RuntimeError('outdoor-scenery.blend exists; edit it directly or explicitly pass --force.')

random.seed(1871)
CENTRE = (34.0, -7.0)           # plan centre of the view (x, z): the middle of the window wall
YARD = (34.0, 77.5, -72.0, 58.0)  # lawn rectangle x0, x1, z0, z1
YARD_Y = -4.5
FENCE_X = 77.0
GATE = (-6.0, 2.0)               # gap in the fence (z range) where the path goes down
LAKE = {'az': 0.0, 'r': 176.0, 'radial': 40.0, 'across': 88.0}
WATER_Y = -12.6
VILLAGE = {'az': 0.10, 'r': 246.0, 'radial': 26.0, 'across': 56.0}
TERRAIN_FAR = 568.0
AZIMUTH = 1.75
TREE_LINE = 58.0
SNOW_LINE = 92.0
# Designed summits (azimuth, distance, height, footprint radius); the hero stands centre right.
PEAKS = [(0.06, 480, 178, 125), (-0.28, 462, 140, 105), (0.36, 470, 152, 112), (-0.66, 476, 168, 118),
         (0.78, 462, 150, 110), (-1.08, 456, 136, 100), (1.18, 458, 146, 106), (-1.50, 462, 132, 100),
         (1.55, 466, 128, 100), (-0.12, 535, 150, 95), (0.58, 530, 140, 95), (-0.90, 535, 150, 98)]

# --- helpers ---------------------------------------------------------------------------------

def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)

def lerp(a, b, t):
    return a + (b - a) * t

def srgb(hex_colour):
    """Linear RGB from an sRGB hex string (vertex colours are stored linear)."""
    channels = [int(hex_colour[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels)

def mix(a, b, t):
    return tuple(lerp(a[i], b[i], t) for i in range(3))

def shade(c, k):
    return tuple(min(1.0, v * k) for v in c)

def polar(az, r):
    return (CENTRE[0] + math.cos(az) * r, CENTRE[1] + math.sin(az) * r)

def to_blender(x, y, z):
    return (x, -z, y)

def n2(x, z, f, seed=0.0):
    return noise.noise(Vector((x * f + seed, z * f - seed * 0.7, seed * 0.31)), noise_basis='PERLIN_NEW')

def fbm(x, z, f, octaves=4, seed=0.0):
    total, amp, norm = 0.0, 1.0, 0.0
    for _ in range(octaves):
        total += n2(x, z, f, seed) * amp
        norm += amp
        f *= 2.03
        amp *= 0.5
        seed += 17.1
    return total / norm

def ridged(x, z, f, octaves=6, seed=0.0):
    """0..1 ridged multifractal: sharp crests and gullies for the rock faces."""
    total, amp, norm, weight = 0.0, 1.0, 0.0, 1.0
    for _ in range(octaves):
        r = 1.0 - abs(n2(x, z, f, seed))
        r *= r * weight
        weight = min(max(r * 1.6, 0.0), 1.0)
        total += r * amp
        norm += amp
        f *= 2.1
        amp *= 0.5
        seed += 11.3
    return total / norm

def ellipse(x, z, area):
    cx, cz = polar(area['az'], area['r'])
    ux, uz = math.cos(area['az']), math.sin(area['az'])
    ox, oz = x - cx, z - cz
    return math.hypot((ox * ux + oz * uz) / area['radial'], (-ox * uz + oz * ux) / area['across'])

def smooth_max(a, b, k):
    gap = max(k - abs(a - b), 0.0)
    return max(a, b) + gap * gap / (4.0 * k)

def outside_yard(x, z):
    return math.hypot(max(YARD[0] - x, 0.0, x - YARD[1]), max(YARD[2] - z, 0.0, z - YARD[3]))

# A dirt path from the fence gate, winding down the meadow to the village square.
PATH = [(77.5, -2.0), (92.0, -5.0), (106.0, -11.0), (120.0, -12.0), (133.0, -9.0), (146.0, -12.0), (158.0, -14.0)]

def path_distance(x, z):
    best = 1e9
    for (ax, az_), (bx, bz) in zip(PATH, PATH[1:]):
        dx, dz = bx - ax, bz - az_
        t = min(max(((x - ax) * dx + (z - az_) * dz) / (dx * dx + dz * dz), 0.0), 1.0)
        best = min(best, math.hypot(x - ax - dx * t, z - az_ - dz * t))
    return best

# --- terrain height --------------------------------------------------------------------------

def height(x, z):
    dx, dz = x - CENTRE[0], z - CENTRE[1]
    r = math.hypot(dx, dz)
    az = math.atan2(dz, dx)
    out = outside_yard(x, z)
    if out <= 0.0:
        return YARD_Y
    side = abs(az)
    # Meadow: rolls down from the fence to the lake shore in soft swells.
    h = YARD_Y - 7.4 * smoothstep(0.0, 100.0, out) + fbm(x, z, 0.03, 3, 2.0) * 1.6 * smoothstep(0.0, 25.0, out)
    # The valley sides rise into forested slopes left and right of the view.
    rise = smoothstep(0.50, 1.40, side) * smoothstep(8.0, 70.0, out)
    h += rise * (24.0 + 16.0 * fbm(x, z, 0.012, 4, 5.0)) + rise * rise * 18.0
    # Beyond the lake a sunny slope climbs to the hills; the village sits on terraces cut into it.
    far_shore = smoothstep(205.0, 310.0, r) * (1.0 - smoothstep(0.45, 0.95, side))
    h += far_shore * (30.0 + 6.0 * fbm(x, z, 0.02, 2, 13.0))
    village = ellipse(x, z, VILLAGE)
    if village < 1.4:
        step = 3.2
        terrace = math.floor(h / step) * step + smoothstep(0.75, 1.0, h / step - math.floor(h / step)) * step
        h = lerp(terrace, h, smoothstep(0.9, 1.4, village))
    lake = ellipse(x, z, LAKE)
    shore = WATER_Y + 0.45 + fbm(x, z, 0.05, 2, 3.0) * 0.3
    h = lerp(shore, h, smoothstep(1.05, 1.7, lake))
    h = lerp(WATER_Y - 4.0, h, smoothstep(0.55, 1.0, lake))
    # Rolling forested hills beyond the lake, lower in the middle so the range shows.
    band = smoothstep(lerp(290.0, 200.0, smoothstep(0.3, 0.9, side)), 340.0, r) * smoothstep(440.0, 380.0, r)
    hills = lerp(-40.0, 4.0 + (18.0 + 26.0 * (0.5 + 0.5 * fbm(x, z, 0.010, 4, 7.0))) * (0.6 + 0.4 * smoothstep(0.05, 0.45, side)), band)
    h = smooth_max(h, hills, 6.0)
    # The range: a ridged massif under designed summits.
    envelope = smoothstep(360.0, 440.0, r) * smoothstep(TERRAIN_FAR + 2.0, 530.0, r)
    if envelope > 0.0:
        crag = ridged(x, z, 0.0065, 6, 3.0)
        mountain = -12.0 + envelope * (40.0 + 110.0 * crag * (0.6 + 0.4 * fbm(x, z, 0.004, 2, 1.0)))
        for p_az, p_r, p_h, p_radius in PEAKS:
            px, pz = polar(p_az, p_r)
            t = math.hypot(x - px, z - pz) / p_radius
            if t < 1.0:
                summit = -12.0 + (p_h + 12.0) * (0.62 * (1.0 - t) ** 1.35 + 0.38 * (1.0 - smoothstep(0.0, 1.0, t)))
                summit += (crag - 0.45) * 70.0 * (1.0 - t)
                mountain = smooth_max(mountain, summit, 10.0)
        h = smooth_max(h, mountain, 8.0)
    return h

def terrain_colour(x, z, h, up):
    out = outside_yard(x, z)
    patch = 0.5 + 0.5 * fbm(x, z, 0.05, 3, 4.0)
    broad = 0.5 + 0.5 * fbm(x, z, 0.012, 3, 15.0)
    if out <= 0.0:
        # Lawn: sunlit and shaded patches rather than one flat green.
        return mix(mix(srgb('4c7c36'), srgb('6f9a45'), patch), srgb('8aa955'), smoothstep(0.55, 0.85, broad) * 0.5)
    meadow = mix(mix(srgb('5f913d'), srgb('84b052'), patch), srgb('a3bb5c'), smoothstep(0.6, 0.9, broad) * 0.45)
    forest_floor = mix(srgb('35603a'), srgb('46703f'), patch)
    alpine = mix(srgb('5c7448'), srgb('6f8456'), patch)
    snow = srgb('f4f7fb')
    r = math.hypot(x - CENTRE[0], z - CENTRE[1])
    # Rock: light crests and dark gullies from the same ridged field that carved them.
    crag = ridged(x, z, 0.0065, 6, 3.0) if r > 330.0 else 0.5
    rock = mix(srgb('5c606e'), srgb('b0b2bc'), smoothstep(0.2, 0.8, crag))
    rock = mix(rock, srgb('8b8073'), 0.25 * (0.5 + 0.5 * fbm(x, z, 0.01, 2, 8.0)))
    dense = forest_density(x, z, h)
    # Up on the range the open ground is alpine turf, never the bright valley meadow.
    colour = mix(mix(meadow, alpine, smoothstep(300.0, 380.0, r)), forest_floor, min(1.0, dense * 1.4))
    wobble = fbm(x, z, 0.02, 3, 6.0) * 12.0
    colour = mix(colour, alpine, smoothstep(TREE_LINE - 2.0, TREE_LINE + 6.0, h + wobble))
    steep = (1.0 - smoothstep(0.52, 0.66, up)) * smoothstep(20.0, 40.0, h)
    colour = mix(colour, rock, max(steep, smoothstep(68.0, 76.0, h + wobble)))
    snowy = smoothstep(SNOW_LINE - 3.0, SNOW_LINE + 3.0, h + (crag - 0.5) * 50.0 + wobble * 1.4) * smoothstep(0.30, 0.48, up)
    colour = mix(colour, snow, snowy)
    # Sandy shore, dirt path, village greens.
    lake = ellipse(x, z, LAKE)
    colour = mix(colour, srgb('d6c592'), smoothstep(1.32, 1.08, lake))
    colour = mix(colour, srgb('5e7f6c'), smoothstep(1.0, 0.9, lake))
    colour = mix(colour, srgb('b49a6c'), smoothstep(1.7, 0.9, path_distance(x, z)))
    colour = mix(colour, mix(srgb('7fa650'), srgb('a0b862'), patch), smoothstep(1.2, 0.8, ellipse(x, z, VILLAGE)))
    return colour

def forest_density(x, z, h):
    """0..1 where pines grow: hills, valley sides and lower mountain slopes, in patches."""
    if outside_yard(x, z) < 30.0 and abs(math.atan2(z - CENTRE[1], x - CENTRE[0])) < 0.9:
        return 0.0
    if ellipse(x, z, LAKE) < 1.35 or ellipse(x, z, VILLAGE) < 1.3 or path_distance(x, z) < 4.0:
        return 0.0
    if h > TREE_LINE + 6.0:
        return 0.0
    r = math.hypot(x - CENTRE[0], z - CENTRE[1])
    open_meadow = smoothstep(285.0, 320.0, r) if abs(math.atan2(z - CENTRE[1], x - CENTRE[0])) < 0.5 else 1.0
    clumps = smoothstep(-0.25, 0.25, fbm(x, z, 0.018, 3, 12.0))
    return clumps * open_meadow * smoothstep(TREE_LINE + 6.0, TREE_LINE - 10.0, h)

# --- mesh building ---------------------------------------------------------------------------

collection = bpy.data.collections.new('Outdoor scenery')
bpy.context.scene.collection.children.link(collection)
preview = bpy.data.collections.new('Preview (not exported)')
bpy.context.scene.collection.children.link(preview)

material = bpy.data.materials.new('Outdoor vertex colour')
material.use_nodes = True
nodes = material.node_tree.nodes
bsdf = nodes.get('Principled BSDF')
attribute = nodes.new('ShaderNodeVertexColor')
attribute.layer_name = 'Col'
material.node_tree.links.new(attribute.outputs['Color'], bsdf.inputs['Base Color'])
bsdf.inputs['Roughness'].default_value = 1.0

class Builder:
    """Collects Godot-space triangles/quads with per-vertex colours and normals."""
    def __init__(self):
        self.verts, self.faces, self.colours, self.normals = [], [], [], []

    def add(self, points, faces, colours, normals=None):
        first = len(self.verts)
        self.verts.extend(points)
        self.faces.extend([tuple(first + i for i in face) for face in faces])
        self.colours.extend(colours if isinstance(colours, list) else [colours] * len(points))
        if normals is not None:
            self.normals.extend(normals)

    def build(self, name, smooth=True):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata([to_blender(*v) for v in self.verts], [], self.faces)
        finish(mesh, self.colours, smooth)
        if self.normals and smooth:
            mesh.normals_split_custom_set_from_vertices([Vector(to_blender(*n)).normalized() for n in self.normals])
        obj = bpy.data.objects.new(name, mesh)
        collection.objects.link(obj)
        return obj

def finish(mesh, colours, smooth):
    attr = mesh.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    flat = np.ones((len(colours), 4), dtype=np.float32)
    flat[:, :3] = np.array(colours, dtype=np.float32)
    attr.data.foreach_set('color', flat.ravel())
    mesh.color_attributes.active_color = attr
    mesh.polygons.foreach_set('use_smooth', [smooth] * len(mesh.polygons))
    mesh.materials.append(material)
    mesh.update()

def build_terrain():
    rows, columns = 480, 900
    radii = [1.0 + (TERRAIN_FAR - 1.0) * (i / rows) ** 2.1 for i in range(rows + 1)]
    azimuths = [-AZIMUTH + 2.0 * AZIMUTH * j / columns for j in range(columns + 1)]
    grid = np.zeros((rows + 1, columns + 1, 3))
    for i, r in enumerate(radii):
        for j, az in enumerate(azimuths):
            x, z = polar(az, r)
            grid[i, j] = (x, height(x, z), z)
    # Upward normals from the grid's neighbours, for colouring by slope.
    along = np.gradient(grid, axis=0)
    across = np.gradient(grid, axis=1)
    normal = np.cross(across, along)
    normal /= np.linalg.norm(normal, axis=2, keepdims=True) + 1e-9
    normal *= np.sign(normal[:, :, 1:2] + 1e-9)
    colours = []
    for i in range(rows + 1):
        for j in range(columns + 1):
            x, h, z = grid[i, j]
            colours.append(terrain_colour(x, z, h, normal[i, j, 1]))
    mesh = bpy.data.meshes.new('Terrain')
    points = grid.reshape(-1, 3)
    mesh.vertices.add(len(points))
    mesh.vertices.foreach_set('co', np.column_stack((points[:, 0], -points[:, 2], points[:, 1])).ravel())
    quads = []
    for i in range(rows):
        for j in range(columns):
            a = i * (columns + 1) + j
            # Counter-clockwise from above in Blender (+Z up), so every face points up.
            quads.extend((a, a + 1, a + columns + 2, a + columns + 1))
    count = rows * columns
    mesh.loops.add(count * 4)
    mesh.loops.foreach_set('vertex_index', quads)
    mesh.polygons.add(count)
    mesh.polygons.foreach_set('loop_start', list(range(0, count * 4, 4)))
    mesh.validate()
    finish(mesh, colours, True)
    obj = bpy.data.objects.new('Terrain', mesh)
    collection.objects.link(obj)
    print('terrain vertices', len(points))

def build_lake():
    builder = Builder()
    rings, segments = 24, 96
    points = [polar(LAKE['az'], LAKE['r'])]
    cx, cz = points[0]
    ux, uz = math.cos(LAKE['az']), math.sin(LAKE['az'])
    verts = [(cx, WATER_Y, cz)]
    for ring in range(1, rings + 1):
        s = 1.12 * ring / rings
        for k in range(segments):
            a = math.tau * k / segments
            ra, rb = math.cos(a) * LAKE['radial'] * s, math.sin(a) * LAKE['across'] * s
            verts.append((cx + ra * ux - rb * uz, WATER_Y, cz + ra * uz + rb * ux))
    faces = []
    for k in range(segments):
        faces.append((0, 1 + (k + 1) % segments, 1 + k))
    for ring in range(rings - 1):
        for k in range(segments):
            a = 1 + ring * segments + k
            b = 1 + ring * segments + (k + 1) % segments
            faces.append((a, b, b + segments, a + segments))
    builder.add(verts, faces, srgb('3d6f86'))
    builder.build('Lake')

# --- plants ----------------------------------------------------------------------------------

def cylinder(builder, base, top, r0, r1, colour, segments=8):
    axis = Vector(top) - Vector(base)
    up = axis.normalized()
    side = up.cross(Vector((0, 0, 1)) if abs(up.z) < 0.9 else Vector((1, 0, 0))).normalized()
    other = up.cross(side)
    points, normals = [], []
    for ring, (centre, radius) in enumerate(((Vector(base), r0), (Vector(top), r1))):
        for k in range(segments):
            a = math.tau * k / segments
            n = side * math.cos(a) + other * math.sin(a)
            points.append(tuple(centre + n * radius))
            normals.append(tuple(n))
    faces = [(k, (k + 1) % segments, segments + (k + 1) % segments, segments + k) for k in range(segments)]
    builder.add(points, faces, colour, normals)

def clump(builder, centre, radii, crown, colour, soften=0.6, segments=12, rings=8):
    """A lumpy foliage ellipsoid; normals lean toward the whole crown so trees shade as one mass."""
    phase = random.random() * math.tau
    points, normals, colours = [], [], []
    c = Vector(centre)
    for ring in range(rings + 1):
        lat = math.pi * ring / rings
        for k in range(segments):
            a = math.tau * k / segments
            lobe = 1.0 + (0.14 * math.sin(a * 3 + phase) + 0.08 * math.sin(a * 5 - lat * 3 + phase)) * math.sin(lat)
            d = Vector((math.sin(lat) * math.cos(a), math.cos(lat), math.sin(lat) * math.sin(a)))
            p = c + Vector((d.x * radii[0], d.y * radii[1], d.z * radii[2])) * lobe
            own = Vector((d.x / radii[0], d.y / radii[1], d.z / radii[2])).normalized()
            whole = (p - Vector(crown)).normalized() if (p - Vector(crown)).length > 0.01 else own
            points.append(tuple(p))
            normals.append(tuple(own.lerp(whole, soften).normalized()))
            colours.append(shade(colour, 0.72 + 0.28 * (0.5 + 0.5 * d.y) + 0.06 * max(d.y, 0.0)))
    faces = []
    for ring in range(rings):
        for k in range(segments):
            a = ring * segments + k
            b = ring * segments + (k + 1) % segments
            faces.append((a, b, b + segments, a + segments))
    builder.add(points, faces, colours, normals)

def tall_pine(bark, leaves, at, h, lean=0.0):
    x, y, z = at
    axis = lambda f: (x + lean * h * f * f, y + h * f, z + lean * 0.6 * h * f * f)
    stations = [0.0, 0.3, 0.6, 0.95]
    for a, b in zip(stations, stations[1:]):
        cylinder(bark, axis(a), axis(b), h * lerp(0.034, 0.006, a), h * lerp(0.034, 0.006, b), srgb('6e4733'), 10)
    for k in range(5):
        ang = k * math.tau / 5 + 0.4
        cylinder(bark, (x + math.cos(ang) * h * 0.075, y - 0.2, z + math.sin(ang) * h * 0.075), axis(0.08),
                 h * 0.010, h * 0.022, srgb('6e4733'), 6)
    tiers = 8
    deep, light = srgb('2f6a42'), srgb('84b862')
    for tier in range(tiers):
        f = tier / (tiers - 1)
        origin = Vector(axis(lerp(0.34, 0.90, f)))
        spread = h * lerp(0.21, 0.055, f)
        count = 6 if tier < 3 else (5 if tier < 6 else 3)
        for k in range(count):
            ang = tier * 1.9 + k * math.tau / count + random.uniform(-0.25, 0.25)
            out = Vector((math.cos(ang), 0, math.sin(ang)))
            centre = origin + out * spread * 0.62 - Vector((0, spread * 0.2, 0))
            tone = min(max(f * 0.8 + random.uniform(-0.08, 0.14), 0.0), 1.0)
            clump(leaves, tuple(centre), (spread * 0.62, spread * 0.36, spread * 0.62), tuple(origin + Vector((0, spread * 0.5, 0))),
                  mix(deep, light, tone), 0.55)
        clump(leaves, tuple(origin), (spread * 0.45, spread * 0.3, spread * 0.45), tuple(origin), shade(deep, 0.8), 0.3)
    top = Vector(axis(0.95))
    clump(leaves, tuple(top), (h * 0.04, h * 0.075, h * 0.04), tuple(top - Vector((0, h * 0.03, 0))), light, 0.5)

def round_tree(bark, leaves, at, h, deep='3f7a3a', light='a2cc5e'):
    base = Vector(at)
    fork = base + Vector((0, h * 0.42, 0))
    cylinder(bark, tuple(base - Vector((0, 0.2, 0))), tuple(fork), h * 0.055, h * 0.04, srgb('6e4733'), 10)
    crown = base + Vector((0, h * 0.72, 0))
    radii = Vector((h * 0.40, h * 0.30, h * 0.40))
    for k in range(3):
        ang = k * math.tau / 3 + 0.5
        tip = crown + Vector((math.cos(ang) * radii.x * 0.5, -radii.y * 0.1, math.sin(ang) * radii.z * 0.5))
        cylinder(bark, tuple(fork), tuple(tip), h * 0.03, h * 0.012, srgb('6e4733'), 8)
    count = 14
    for k in range(count):
        yy = lerp(0.85, -0.35, (k + 0.5) / count)
        ring = math.sqrt(1 - yy * yy)
        ang = k * 2.39996
        centre = crown + Vector((math.cos(ang) * ring * radii.x, yy * radii.y, math.sin(ang) * ring * radii.z)) * 0.72
        size = h * random.uniform(0.17, 0.22)
        tone = min(max((yy + 0.4) * 0.6 + random.uniform(-0.1, 0.1), 0.0), 1.0)
        clump(leaves, tuple(centre), (size, size * 0.8, size), tuple(crown), mix(srgb(deep), srgb(light), tone), 0.6)
    clump(leaves, tuple(crown), tuple(radii * 0.6), tuple(crown), shade(srgb(deep), 0.85), 0.6)

def shrub(leaves, at, size):
    base = Vector(at)
    centre = base + Vector((0, size * 0.35, 0))
    for k in range(6):
        ang = k * 2.4
        spread = size * random.uniform(0.3, 0.7)
        c = base + Vector((math.cos(ang) * spread, size * random.uniform(0.35, 0.7), math.sin(ang) * spread))
        radius = size * random.uniform(0.45, 0.65)
        clump(leaves, tuple(c), (radius, radius * 0.75, radius), tuple(centre),
              mix(srgb('4c8238'), srgb('9cc85c'), random.uniform(0.0, 0.45)), 0.6, 10, 6)

def cone(builder, base, radius, h, colour, segments=7, spin=0.0):
    bx, by, bz = base
    points = [(bx + math.cos(spin + math.tau * k / segments) * radius, by, bz + math.sin(spin + math.tau * k / segments) * radius)
              for k in range(segments)]
    normals = [(math.cos(spin + math.tau * k / segments), radius / h, math.sin(spin + math.tau * k / segments)) for k in range(segments)]
    points.append((bx, by + h, bz))
    normals.append((0, 1, 0))
    colours = [shade(colour, 0.7)] * segments + [shade(colour, 1.15)]
    faces = [(k, segments, (k + 1) % segments) for k in range(segments)]
    builder.add(points, faces, colours, normals)

def forest_pine(builder, at, h, colour):
    x, y, z = at
    spin = random.random() * math.tau
    cylinder(builder, (x, y - 0.3, z), (x, y + h * 0.25, z), h * 0.05, h * 0.04, srgb('5a3d2c'), 5)
    for k, (lift, radius, length, tone) in enumerate(((0.12, 0.34, 0.50, 0.9), (0.36, 0.27, 0.46, 1.0), (0.58, 0.18, 0.42, 1.12))):
        cone(builder, (x, y + h * lift, z), h * radius, h * length, shade(colour, tone), 7, spin + k)

def build_plants():
    bark, leaves, forest, flowers = Builder(), Builder(), Builder(), Builder()
    # Framing trees in the yard; nothing tall in the path or the central sightline.
    for x, z, h, lean in [(60, -29, 30, 0.04), (68, 22, 34, -0.05), (73, -50, 27, 0.03), (49, 40, 24, -0.04),
                          (77, 46, 29, 0.02), (44, -54, 22, 0.05), (90, -60, 32, 0.02), (95, 48, 30, -0.03)]:
        tall_pine(bark, leaves, (x, height(x, z), z), h, lean)
    for x, z, h in [(66, -40, 15), (55, 28, 13), (75, 33, 14), (41, -33, 11), (88, 36, 14), (86, -46, 13)]:
        round_tree(bark, leaves, (x, height(x, z), z), h)
    for cx, cz in [(46, -23), (62, -27), (71, -19), (49, 8), (63, 16), (74, 21), (73, 36), (43, -45), (60, -49)]:
        for _ in range(3):
            x, z = cx + random.uniform(-2.5, 2.5), cz + random.uniform(-3, 3)
            shrub(leaves, (x, YARD_Y, z), random.uniform(1.2, 2.2))
    # A few round trees down the meadow and around the village.
    for x, z, h in [(112, -40, 12), (120, 24, 14), (150, -60, 13), (158, -38, 11), (128, -52, 10), (150, -74, 12), (146, 44, 15)]:
        round_tree(bark, leaves, (x, height(x, z), z), h, '3d7a3c', '9cc85c')
    # Pine forest on a jittered grid, wider-spaced and larger with distance so it reads as texture.
    shades = [srgb('2b5a3a'), srgb('33663f'), srgb('3e7446'), srgb('2f5f45'), srgb('47784a')]
    planted = 0
    for i in range(-160, 161):
        for j in range(0, 700):
            r = 60.0 + j * (1.6 + j * 0.0045)
            if r > 540:
                break
            spacing = r * 0.0105 + 1.4
            az = (i + random.uniform(-0.45, 0.45)) * spacing / r
            if abs(az) > AZIMUTH - 0.03:
                continue
            x, z = polar(az, r + random.uniform(-0.5, 0.5) * spacing)
            if outside_yard(x, z) <= 2.0:
                continue
            h = height(x, z)
            density = forest_density(x, z, h)
            if density <= 0.05 or random.random() > density:
                continue
            # Slope from finite differences: no trees on cliffs.
            e = 1.0
            gx = (height(x + e, z) - height(x - e, z)) / (2 * e)
            gz = (height(x, z + e) - height(x, z - e)) / (2 * e)
            if math.hypot(gx, gz) > 0.75:
                continue
            size = (3.6 + r * 0.016) * random.uniform(0.75, 1.3)
            forest_pine(forest, (x, h, z), size, random.choice(shades))
            planted += 1
    print('forest pines', planted)
    # Wildflowers in patches on the lawn edges and the meadow.
    petals = [srgb('f6f2e4'), srgb('f3d34a'), srgb('f6f2e4'), srgb('ec9fb4'), srgb('f3d34a'), srgb('b49be0')]
    for _ in range(1700):
        x, z = random.uniform(40, 150), random.uniform(-80, 60)
        out = outside_yard(x, z)
        if out <= 0.0 and not (x > 72 or z < -62 or z > 48):
            continue
        if path_distance(x, z) < 2.0 or ellipse(x, z, VILLAGE) < 1.2 or ellipse(x, z, LAKE) < 1.4:
            continue
        if fbm(x, z, 0.06, 2, 21.0) < 0.12:
            continue
        colour = petals[int((fbm(x, z, 0.03, 2, 33.0) * 0.5 + 0.5) * len(petals)) % len(petals)]
        y = height(x, z)
        s = random.uniform(0.12, 0.22) * (1.0 + out * 0.012)
        pts = [(x, y + s * 2.2, z), (x + s, y + s * 1.2, z), (x, y + s * 1.2, z + s), (x - s, y + s * 1.2, z), (x, y + s * 1.2, z - s), (x, y + s * 0.4, z)]
        faces = [(0, 2, 1), (0, 3, 2), (0, 4, 3), (0, 1, 4), (5, 1, 2), (5, 2, 3), (5, 3, 4), (5, 4, 1)]
        flowers.add(pts, faces, colour)
    bark.build('YardBark')
    leaves.build('Foliage')
    forest.build('Forest')
    flowers.build('Flowers', smooth=False)

# --- yard, fence and village -----------------------------------------------------------------

def box(builder, lo, hi, colour):
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    p = [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), (x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)]
    # Each face gets its own corners so flat shading stays crisp.
    for quad in ((0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
        builder.add([p[i] for i in quad], [(0, 1, 2, 3)], colour)

def build_yard():
    stones, fence = Builder(), Builder()
    for k in range(8):
        x, z = 38.0 + k * 5.2, -7.0 + math.sin(k * 1.3) * 2.2 + (k > 6) * 4.0
        r = 1.5 + random.random() * 0.5
        pts = [(x + math.cos(a) * r * (1 + 0.1 * math.sin(a * 3 + k)), YARD_Y + 0.18, z + math.sin(a) * r) for a in
               [math.tau * s / 9 for s in range(9)]]
        stones.add(pts + [(x, YARD_Y + 0.2, z)], [(9, (s + 1) % 9, s) for s in range(9)], srgb('e0d2ae'))
        stones.add([(p[0], YARD_Y - 0.1, p[2]) for p in pts] + pts, [(s, (s + 1) % 9, 9 + (s + 1) % 9, 9 + s) for s in range(9)], srgb('c9b993'))
    for k in range(7):
        x, z = random.uniform(44, 74), random.uniform(-60, 46)
        if abs(z + 7) < 7:
            continue
        s = random.uniform(1.2, 2.6)
        clump(stones, (x, YARD_Y + s * 0.3, z), (s * 1.3, s * 0.7, s), (x, YARD_Y, z), srgb('b9ad92'), 0.0, 10, 6)
    wood, wood_dark = srgb('8d6747'), srgb('6f5038')
    z = YARD[2]
    while z < YARD[3] - 0.1:
        nxt = min(z + 4.0, YARD[3])
        for edge in (z,):
            if GATE[0] < edge < GATE[1]:
                continue
            lean = random.uniform(-0.12, 0.12)
            top = YARD_Y + random.uniform(3.0, 3.4)
            box(fence, (FENCE_X - 0.25, YARD_Y - 0.3, edge - 0.25), (FENCE_X + 0.25 + lean, top, edge + 0.25), wood_dark)
        if not (z < GATE[1] and nxt > GATE[0]):
            for rail in (1.2, 2.4):
                y = YARD_Y + rail + random.uniform(-0.08, 0.08)
                box(fence, (FENCE_X - 0.12, y, z), (FENCE_X + 0.12, y + 0.32, nxt), wood)
        z = nxt
    # Gate posts.
    for edge in GATE:
        box(fence, (FENCE_X - 0.35, YARD_Y - 0.3, edge - 0.35), (FENCE_X + 0.35, YARD_Y + 3.9, edge + 0.35), wood_dark)
    stones.build('YardStones', smooth=False)
    fence.build('Fence', smooth=False)

def house(walls, roofs, glass, at, width, depth, height_, facing, wall, roof, steeple=False):
    """A gabled house (width across, depth along `facing`); windows are separate glowing quads."""
    x, y, z = at
    ux, uz = math.cos(facing), math.sin(facing)
    vx, vz = -uz, ux
    def p(a, b, c):  # a along facing (depth), b across (width), c up
        return (x + ux * a + vx * b, y + c, z + uz * a + vz * b)
    d, w, h = depth / 2, width / 2, height_
    corners = [p(-d, -w, -4.0), p(d, -w, -4.0), p(d, w, -4.0), p(-d, w, -4.0), p(-d, -w, h), p(d, -w, h), p(d, w, h), p(-d, w, h)]
    for quad in ((0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        walls.add([corners[i] for i in quad], [(0, 1, 2, 3)], wall)
    # Gable ends and the roof, with a little overhang.
    ridge = h + width * 0.42
    walls.add([p(d, -w, h), p(d, w, h), p(d, 0, ridge)], [(0, 1, 2)], wall)
    walls.add([p(-d, w, h), p(-d, -w, h), p(-d, 0, ridge)], [(0, 1, 2)], wall)
    o = 0.45
    for side in (-1, 1):
        roofs.add([p(-d - o, side * (w + o), h - 0.3), p(d + o, side * (w + o), h - 0.3), p(d + o, 0, ridge + 0.05), p(-d - o, 0, ridge + 0.05)],
                  [(0, 1, 2, 3)], shade(roof, 0.9 if side < 0 else 1.05))
    if not steeple:
        chimney = p(random.uniform(-d * 0.5, d * 0.5), w * 0.45, 0)
        box(walls, (chimney[0] - 0.35, y + h, chimney[2] - 0.35), (chimney[0] + 0.35, y + ridge + 1.0, chimney[2] + 0.35), srgb('8c7e74'))
    # Windows on the long walls and a door on the lakeside end.
    for side in (-1, 1):
        n = max(1, int(depth // 2.2))
        for k in range(n):
            a = -d + (k + 0.5) * depth / n
            for level in ([1.0] if h < 4 else [1.0, h - 1.7]):
                s = side * (w + 0.04)
                glass.add([p(a - 0.4, s, level), p(a + 0.4, s, level), p(a + 0.4, s, level + 0.9), p(a - 0.4, s, level + 0.9)],
                          [(0, 1, 2, 3)], srgb('ffffff'))
    glass.add([p(d + 0.04, -0.5, 0.0), p(d + 0.04, 0.5, 0.0), p(d + 0.04, 0.5, 1.6), p(d + 0.04, -0.5, 1.6)], [(0, 1, 2, 3)], srgb('ffffff'))

def build_village():
    walls, roofs, glass, wood = Builder(), Builder(), Builder(), Builder()
    cx, cz = polar(VILLAGE['az'], VILLAGE['r'])
    lake_x, lake_z = polar(LAKE['az'], LAKE['r'])
    wall_colours = [srgb('f1e8d4'), srgb('efe0bb'), srgb('e8d2a8'), srgb('d9b48a'), srgb('f4efe6'), srgb('c98f6a')]
    roof_colours = [srgb('b0503c'), srgb('8f4535'), srgb('5b5f6e'), srgb('a35b3a'), srgb('6e4a3a')]
    placed = []
    # The church first, in the middle of the village.
    face = math.atan2(lake_z - cz, lake_x - cx)
    y = height(cx, cz)
    house(walls, roofs, glass, (cx, y, cz), 4.4, 8.0, 4.8, face, srgb('f4efe6'), srgb('5b5f6e'), steeple=True)
    tx, tz = cx - math.cos(face) * 4.6, cz - math.sin(face) * 4.6
    box(walls, (tx - 1.4, y - 1, tz - 1.4), (tx + 1.4, y + 9.5, tz + 1.4), srgb('f4efe6'))
    walls.add([(tx - 1.6, y + 9.5, tz - 1.6), (tx + 1.6, y + 9.5, tz - 1.6), (tx, y + 14.5, tz)], [(0, 1, 2)], srgb('5b5f6e'))
    walls.add([(tx + 1.6, y + 9.5, tz - 1.6), (tx + 1.6, y + 9.5, tz + 1.6), (tx, y + 14.5, tz)], [(0, 1, 2)], shade(srgb('5b5f6e'), 1.1))
    walls.add([(tx + 1.6, y + 9.5, tz + 1.6), (tx - 1.6, y + 9.5, tz + 1.6), (tx, y + 14.5, tz)], [(0, 1, 2)], srgb('5b5f6e'))
    walls.add([(tx - 1.6, y + 9.5, tz + 1.6), (tx - 1.6, y + 9.5, tz - 1.6), (tx, y + 14.5, tz)], [(0, 1, 2)], shade(srgb('5b5f6e'), 0.9))
    placed.append((cx, cz, 7.0))
    attempts = 0
    while len(placed) < 26 and attempts < 4000:
        attempts += 1
        x = cx + random.uniform(-1, 1) * VILLAGE['across']
        z = cz + random.uniform(-1, 1) * VILLAGE['across']
        if ellipse(x, z, VILLAGE) > 1.15 or ellipse(x, z, LAKE) < 1.25 or path_distance(x, z) < 2.6:
            continue
        size = random.uniform(3.0, 4.6)
        if any(math.hypot(x - px, z - pz) < (size + ps) * 0.75 for px, pz, ps in placed):
            continue
        placed.append((x, z, size))
        facing = math.atan2(lake_z - z, lake_x - x) + random.choice([0, math.pi / 2]) + random.uniform(-0.15, 0.15)
        house(walls, roofs, glass, (x, height(x, z), z), size * random.uniform(0.75, 0.95), size * random.uniform(1.1, 1.5),
              random.uniform(2.6, 4.2), facing, random.choice(wall_colours), random.choice(roof_colours))
    # A few farmhouses up the meadow and along the far shore.
    for x, z in [(118, 32), (126, -60), (150, 50), (238, 80), (226, -84), (290, -40)]:
        house(walls, roofs, glass, (x, height(x, z), z), 3.6, 5.0, 3.0, math.atan2(lake_z - z, lake_x - x),
              random.choice(wall_colours), random.choice(roof_colours))
    # A pier into the lake and two rowboats.
    px, pz = polar(-0.05, LAKE['r'] - LAKE['radial'] * 0.98)
    dirx, dirz = lake_x - px, lake_z - pz
    length = math.hypot(dirx, dirz)
    dirx, dirz = dirx / length, dirz / length
    for k in range(12):
        sx, sz = px + dirx * k * 1.0, pz + dirz * k * 1.0
        box(wood, (sx - 0.5, WATER_Y + 0.35, sz - 0.5), (sx + 0.5, WATER_Y + 0.55, sz + 0.5), srgb('8d6747'))
        if k % 3 == 0:
            box(wood, (sx - 0.15, WATER_Y - 1.0, sz - 0.15), (sx + 0.15, WATER_Y + 0.9, sz + 0.15), srgb('6f5038'))
    for bx, bz, ang, colour in [(px + dirx * 9 + 2.0, pz + dirz * 9 - 1.4, 0.4, srgb('c0523e')),
                                (lake_x + 8.0, lake_z + 30.0, 1.1, srgb('e9e2d0')), (lake_x + 18.0, lake_z - 22.0, 2.0, srgb('3f7fa0'))]:
        ux, uz = math.cos(ang), math.sin(ang)
        hull = [(-1.6, 0.0), (-0.9, 0.55), (0.9, 0.55), (1.6, 0.0), (0.9, -0.55), (-0.9, -0.55)]
        top = [(bx + ux * a - uz * b, WATER_Y + 0.35, bz + uz * a + ux * b) for a, b in hull]
        bottom = [(bx + ux * a * 0.7 - uz * b * 0.5, WATER_Y - 0.2, bz + uz * a * 0.7 + ux * b * 0.5) for a, b in hull]
        wood.add(top + bottom, [(k, (k + 1) % 6, 6 + (k + 1) % 6, 6 + k) for k in range(6)], colour)
        wood.add(top, [(0, 1, 2, 3), (0, 3, 4, 5)], srgb('7a5a40'))
    walls.build('VillageWalls', smooth=False)
    roofs.build('VillageRoofs', smooth=False)
    glass.build('WindowLights', smooth=False)
    wood.build('Pier', smooth=False)

def add_preview_camera():
    data = bpy.data.cameras.new('WindowView')
    data.angle = math.radians(65.0)
    data.clip_end = 1500.0
    camera = bpy.data.objects.new('WindowView', data)
    camera.location = to_blender(10.0, 3.27, -7.0)
    camera.rotation_euler = (math.radians(90.0), 0.0, math.radians(-90.0))
    preview.objects.link(camera)
    bpy.context.scene.camera = camera
    sun = bpy.data.lights.new('Sun', 'SUN')
    sun.energy = 3.0
    light = bpy.data.objects.new('Sun', sun)
    light.rotation_euler = (math.radians(40.0), 0.0, math.radians(150.0))
    preview.objects.link(light)

# --- build -----------------------------------------------------------------------------------
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in list(bpy.data.meshes):
    bpy.data.meshes.remove(block)
build_terrain()
build_lake()
build_yard()
build_village()
build_plants()
add_preview_camera()
try:
    bpy.context.scene.render.engine = 'BLENDER_EEVEE'
except TypeError:
    pass
DEST.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(DEST))
print('OUTDOOR_BUILT:', DEST)
