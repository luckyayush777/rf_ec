"""Make an alternate rounded 710 study from the saved GPU, retaining service parts.

blender --background <unstyled-gpu.blend> --python scripts/blender/stylize_gpu.py -- --render
Writes models/gpu-rounded.blend and .glb; never writes the production GPU source.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_gpu import export_gpu


def rgba(hex_color):
    def linear(value):
        value /= 255
        return value / 12.92 if value <= .04045 else ((value + .055) / 1.055) ** 2.4
    return (*[linear(int(hex_color[i:i + 2], 16)) for i in (0, 2, 4)], 1)


def material(name, color, metallic=0, roughness=.5):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    if not mat.use_nodes:
        mat.use_nodes = True
    shader = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    shader.inputs['Base Color'].default_value = rgba(color)
    shader.inputs['Metallic'].default_value = metallic
    shader.inputs['Roughness'].default_value = roughness
    mat.diffuse_color = rgba(color)
    return mat


def assign(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def extents(obj):
    return tuple((min(v.co[i] for v in obj.data.vertices),
                  max(v.co[i] for v in obj.data.vertices)) for i in range(3))


def bevel(obj, width):
    for mod in list(obj.modifiers):
        if mod.type in {'BEVEL', 'WEIGHTED_NORMAL'}:
            obj.modifiers.remove(mod)
    mod = obj.modifiers.new('Rounded edge highlights', 'BEVEL')
    mod.width = width
    mod.segments = 4
    mod = obj.modifiers.new('Broad smooth faces', 'WEIGHTED_NORMAL')
    mod.keep_sharp = True


def replace_mesh(obj, vertices, faces):
    mats = list(obj.data.materials)
    data = bpy.data.meshes.new(obj.name + '-rounded')
    data.from_pydata(vertices, [], faces)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    obj.data = data
    for mat in mats:
        data.materials.append(mat)


def rounded_prism(obj, radius, axes=(0, 1, 2), size=None):
    """Round the silhouette independently of the thin board/component thickness."""
    bounds = extents(obj)
    centre = [(a + b) / 2 for a, b in bounds]
    dims = size or [b - a for a, b in bounds]
    a, b, c = axes
    half_a, half_b = dims[a] / 2, dims[b] / 2
    radius = min(radius, half_a, half_b)
    outline = []
    for ca, cb, start in ((half_a - radius, half_b - radius, 0),
                          (-half_a + radius, half_b - radius, 90),
                          (-half_a + radius, -half_b + radius, 180),
                          (half_a - radius, -half_b + radius, 270)):
        for k in range(9):
            angle = math.radians(start + k * 90 / 8)
            outline.append((ca + radius * math.cos(angle), cb + radius * math.sin(angle)))
    verts = []
    for depth in (-dims[c] / 2, dims[c] / 2):
        for x, y in outline:
            v = centre.copy()
            v[a] += x
            v[b] += y
            v[c] += depth
            verts.append(v)
    n = len(outline)
    faces = [tuple(reversed(range(n))), tuple(range(n, n * 2))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    replace_mesh(obj, verts, faces)
    bevel(obj, min(dims[c] * .18, .012))


def rounded_fan_frame(obj):
    # A rounded square outside and a circular aperture. Keep the screw seats and
    # rotor opening where they were; add thickness downward, below the screw heads.
    half, radius, inner, count = 1.12, .30, 2.13 * .438, 128
    verts, faces = [], []
    for i in range(count):
        angle = i * math.tau / count
        co, si = math.cos(angle), math.sin(angle)
        lo, hi = 0, half * math.sqrt(2)
        for _ in range(25):
            t = (lo + hi) / 2
            x = max(abs(t * co) - (half - radius), 0)
            y = max(abs(t * si) - (half - radius), 0)
            if math.hypot(x, y) <= radius:
                lo = t
            else:
                hi = t
        outer = (lo + hi) / 2
        verts += [(inner * co, inner * si, -.035), (outer * co, outer * si, -.035),
                  (inner * co, inner * si, .115), (outer * co, outer * si, .115)]
    for i in range(count):
        a, b = i * 4, ((i + 1) % count) * 4
        faces += [(a, b, b + 1, a + 1), (a + 2, a + 3, b + 3, b + 2),
                  (a, a + 2, b + 2, b), (a + 1, b + 1, b + 3, a + 3)]
    replace_mesh(obj, verts, faces)
    bevel(obj, .018)


def scale_mesh(obj, factors, anchor_bottom=False):
    obj.data = obj.data.copy()
    bounds = extents(obj)
    pivot = [(a + b) / 2 for a, b in bounds]
    if anchor_bottom:
        pivot[2] = bounds[2][0]
    for vertex in obj.data.vertices:
        for i in range(3):
            vertex.co[i] = pivot[i] + (vertex.co[i] - pivot[i]) * factors[i]


def contract(objects):
    return {obj.name: {'parent': obj.parent.name if obj.parent else None,
                      'matrix': [list(row) for row in obj.matrix_basis],
                      'properties': obj.id_properties_ensure().to_dict()}
            for obj in objects}


def setup_preview(scene):
    material('Table', 'd9e2dc', 0, .88)
    world_shader = next(n for n in scene.world.node_tree.nodes if n.type == 'BACKGROUND')
    world_shader.inputs[0].default_value = (.35, .40, .38, 1)
    world_shader.inputs[1].default_value = .6
    target = Vector((0, 0, .45))
    scene.camera.location = (8, -11.5, 9)
    scene.camera.rotation_euler = (target - scene.camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera_types = [i.identifier for i in scene.camera.data.bl_rna.properties['type'].enum_items]
    if 'ORTHO' in camera_types:
        scene.camera.data.type = 'ORTHO'
        scene.camera.data.ortho_scale = 8.4
    scene.render.resolution_x, scene.render.resolution_y = 1400, 1000
    scene.render.resolution_percentage = 100
    if scene.render.engine == 'CYCLES':
        scene.cycles.samples = 40
        scene.cycles.use_denoising = True
    formats = [i.identifier for i in scene.render.image_settings.bl_rna.properties['file_format'].enum_items]
    if 'PNG' in formats:
        scene.render.image_settings.file_format = 'PNG'


def render(scene, name):
    scene.render.filepath = str(ROOT / 'artifacts' / name)
    bpy.ops.render.render(write_still=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render', action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    original_path = Path(bpy.data.filepath).resolve()
    if (bpy.context.scene.get('gpu_art_style') == 'rounded'
            or original_path == (ROOT / 'models/gpu-rounded.blend').resolve()):
        raise RuntimeError('This GPU is already rounded. Edit it directly, or open an unstyled baseline.')
    original_hash = hashlib.sha256(original_path.read_bytes()).hexdigest()
    root = bpy.data.objects['gpu']
    objects = [root, *root.children_recursive]
    scene = bpy.context.scene
    bpy.context.view_layer.update()
    before = contract(objects)
    (ROOT / 'artifacts').mkdir(exist_ok=True)
    setup_preview(scene)
    if args.render:
        render(scene, 'gpu-style-original.png')

    # Matte, warm colours distinguish the mechanical parts at ordinary play scale.
    for name, color, metal, rough in (
        ('Board', '398c85', .02, .65), ('Board edge', '1d625e', .03, .63),
        ('Aluminum', 'b7cdd0', .48, .43), ('Steel', '94a8af', .55, .43),
        ('Gold contacts', 'e7b454', .65, .34), ('Fan plastic', 'f0dfbc', .02, .47),
        ('Fan blades', '27616a', .08, .43), ('Recess', '172b35', 0, .65),
        ('Connector plastic', 'f7e7c6', 0, .5), ('Cable red', 'dc7351', 0, .52),
        ('Cable black', '294452', 0, .55), ('Worn thermal pad', 'aa98ad', 0, .75)):
        material(name, color, metal, rough)
    chip_mat = material('Rounded chip charcoal', '294452', .04, .57)
    copper = material('Rounded screw copper', 'dc8b52', .5, .38)
    cap_body = material('Rounded capacitor blue', '527f91', .18, .47)
    hub = material('Rounded hub terracotta', 'de835a', .03, .48)

    for name in ('board-substrate', 'board-top', 'board-bottom'):
        rounded_prism(bpy.data.objects[name], .24 if name == 'board-substrate' else .23)
    rounded_prism(bpy.data.objects['heatsink-base'], .20)
    fins = bpy.data.objects['heatsink-fins']
    bounds = extents(fins)
    dims = [b - a for a, b in bounds]
    dims[0] = .093
    rounded_prism(fins, .16, axes=(1, 2, 0), size=dims)
    rounded_fan_frame(bpy.data.objects['fan-housing'])

    for obj in objects:
        name = obj.name
        if name.startswith(('memory-package-', 'rear-memory-', 'power-chip-')) or name == 'gpu-package':
            rounded_prism(obj, .065 if name != 'gpu-package' else .11)
            assign(obj, chip_mat)
        elif name.startswith('capacitor-') and not name.startswith('capacitor-score-'):
            scale_mesh(obj, (1.24, 1.24, 1.22), anchor_bottom=True)
            bevel(obj, .032)
            assign(obj, cap_body)
            obj.data.materials.append(bpy.data.materials['Aluminum'])
            for face in obj.data.polygons:
                if face.normal.z > .9:
                    face.material_index = 1
            score = bpy.data.objects[name.replace('capacitor-', 'capacitor-score-')]
            score.data = score.data.copy()
            for vertex in score.data.vertices:
                vertex.co.x *= 1.2
                vertex.co.z += .29 * .22
        elif name.endswith('-head') and name.startswith(('fan-screw-', 'cooler-screw-')):
            scale_mesh(obj, (1.3, 1.3, 1))
            bevel(obj, .011)
            assign(obj, copper)
        elif '-cross-' in name and name.startswith(('fan-screw-', 'cooler-screw-')):
            scale_mesh(obj, (1.3, 1.3, 1))
        elif name.startswith('fan-blade-'):
            scale_mesh(obj, (1, 1, 1.45))
            bevel(obj, .009)
        elif name.startswith(('dvi-shell', 'hdmi-shell')):
            # The connector bodies are thin on neither axis; broad edge highlights.
            bevel(obj, .055)
        elif name in ('fan-hub', 'fan-hub-cap'):
            assign(obj, hub)
        elif obj.type == 'CURVE' and name.startswith('fan-'):
            obj.data.bevel_depth *= 1.15
        elif obj.type == 'FONT':
            if name == 'fan-brand-label':
                assign(obj, bpy.data.materials['Connector plastic'])

    after = contract(objects)
    differences = {name: {'before': before[name], 'after': after[name]}
                   for name in before if before[name] != after[name]}
    if differences:
        (ROOT / 'artifacts/gpu-rounded-contract-differences.json').write_text(
            json.dumps(differences, indent=2), encoding='utf-8')
    assert not differences, 'A component transform, parent or metadata changed'
    assert len(objects) == len([root, *root.children_recursive]), 'The component set changed'
    draft = ROOT / 'models/gpu-rounded.blend'
    scene['gpu_art_style'] = 'rounded'
    bpy.ops.wm.save_as_mainfile(filepath=str(draft))
    export_gpu(ROOT / 'models/gpu-rounded.glb')
    assert hashlib.sha256(original_path.read_bytes()).hexdigest() == original_hash
    print(f'ROUNDED_STYLE_CONTRACT_PASS: {len(objects)} objects; transforms, hierarchy and metadata retained')
    if args.render:
        render(scene, 'gpu-rounded-front.png')
        # Presentation only: restore the service assembly homes after rendering.
        cooler, fan = bpy.data.objects['cooler-assembly'], bpy.data.objects['fan-assembly']
        cooler_home, fan_home = cooler.location.copy(), fan.location.copy()
        cooler.location.z += 1.1
        fan.location.z += 1.25
        target = Vector((0, 0, 1.25))
        scene.camera.location = (7.5, -12, 10.5)
        scene.camera.rotation_euler = (target - scene.camera.location).to_track_quat('-Z', 'Y').to_euler()
        scene.camera.data.ortho_scale = 9.0
        render(scene, 'gpu-rounded-exploded.png')
        cooler.location, fan.location = cooler_home, fan_home
    (ROOT / 'artifacts/gpu-rounded-contract.json').write_text(json.dumps({
        'blender_version': bpy.app.version_string, 'source_sha256': original_hash,
        'objects': len(objects), 'unchanged_hierarchy_transforms_metadata': True,
        'source_unmodified': True, 'draft': str(draft.relative_to(ROOT)),
        'fin_count': next(m.count for m in fins.modifiers if m.type == 'ARRAY'),
    }, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
