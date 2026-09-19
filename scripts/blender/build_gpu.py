"""Create an editable, simplified GPU and a separate preview stage in Blender 4.5+.

Run: npm run model:build
Existing .blend files are protected unless --force is supplied. Export edits with
model:export instead of regenerating. This script runs in a fresh background process.
"""
import argparse
import json
import math
from pathlib import Path
import sys

import bpy
import bmesh
from mathutils import Vector, Quaternion

sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_gpu import export_gpu

ROOT = Path(__file__).resolve().parents[2]

# Generation knobs. After generation, all objects can also be edited normally in Blender.
FIN_COUNT = 25
BLADE_COUNT = 9
FAN_SIZE = 2.13
BOARD_LENGTH = 5.95
BOARD_DEPTH = 2.68
HEATSINK_WIDTH = 4.43
COLORS = {
    'Board': ('355b49', 0.08, 0.68),
    'Board edge': ('728365', 0.0, 0.8),
    'Aluminum': ('c3c7c4', 0.83, 0.37),
    'Steel': ('919995', 0.83, 0.29),
    'Gold contacts': ('c5a55b', 0.7, 0.34),
    'Fan plastic': ('111613', 0.08, 0.47),
    'Fan blades': ('1b211d', 0.13, 0.36),
    'Recess': ('121814', 0.05, 0.72),
    'Connector plastic': ('d9d4b8', 0.0, 0.56),
    'Cable black': ('202623', 0.0, 0.58),
    'Cable red': ('a64e3f', 0.0, 0.56),
    'Table': ('292f27', 0.0, 0.93),
}
MATERIALS = {}
MODEL = None


def linear(value):
    value /= 255
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def make_materials():
    for name, (color, metal, rough) in COLORS.items():
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        rgba = tuple(linear(int(color[i:i + 2], 16)) for i in (0, 2, 4)) + (1,)
        mat.diffuse_color = rgba
        shader = mat.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Base Color'].default_value = rgba
        shader.inputs['Metallic'].default_value = metal
        shader.inputs['Roughness'].default_value = rough
        MATERIALS[name] = mat


def place(obj, name, parent=None, position=(0, 0, 0), collection=None):
    obj.name = name
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    (collection or MODEL).objects.link(obj)
    obj.parent = parent
    obj.location = position
    return obj


def part(obj, role, direction=None, requires=None, attachment=None):
    obj['part_role'] = role
    if direction is not None:
        obj['removal_direction'] = direction
    if requires is not None:
        obj['requires_json'] = json.dumps(requires)
    if attachment:
        obj['attachment'] = attachment
    return obj


def group(name, parent=None, position=(0, 0, 0), role='fixed', **metadata):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = 'PLAIN_AXES'
    obj.empty_display_size = 0.17
    return part(place(obj, name, parent, position), role, **metadata)


def finish(obj, mat, bevel=0):
    obj.data.materials.append(MATERIALS[mat])
    if bevel:
        modifier = obj.modifiers.new('Soft manufactured edges', 'BEVEL')
        modifier.width = bevel
        modifier.segments = 3
    return obj


def box(name, size, position, mat, parent=None, bevel=0.015, collection=None):
    bpy.ops.mesh.primitive_cube_add(size=1)
    obj = bpy.context.object
    # Scale mesh data, leaving object transforms clean for editing/animation.
    for vertex in obj.data.vertices:
        vertex.co.x *= size[0]
        vertex.co.y *= size[1]
        vertex.co.z *= size[2]
    place(obj, name, parent, position, collection)
    return finish(obj, mat, min(bevel, min(size) * 0.3))


def cylinder(name, radius, depth, position, mat, parent=None, vertices=40):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth)
    obj = place(bpy.context.object, name, parent, position)
    for polygon in obj.data.polygons:
        polygon.use_smooth = len(polygon.vertices) == 4
    return finish(obj, mat, min(0.008, depth * 0.15))


def mesh(name, vertices, faces, mat, parent=None, position=(0, 0, 0), bevel=0):
    data = bpy.data.meshes.new(name + '-mesh')
    data.from_pydata(vertices, [], faces)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(name, data)
    place(obj, name, parent, position)
    return finish(obj, mat, bevel)


def screw(name, position, parent, rear=False):
    root = group(name, parent, position, role='fastener', direction=(0, 0, -1 if rear else 1))
    if rear:
        root.rotation_euler.x = math.pi
    cylinder(name + '-head', 0.065, 0.044, (0, 0, 0), 'Steel', root, vertices=24)
    length = 0.30 if rear else 0.25
    cylinder(name + '-shaft', 0.029, length, (0, 0, -length / 2 - 0.012), 'Steel', root, vertices=16)
    box(name + '-cross-a', (0.075, 0.017, 0.003), (0, 0, 0.023), 'Recess', root, bevel=0.001)
    box(name + '-cross-b', (0.017, 0.075, 0.003), (0, 0, 0.023), 'Recess', root, bevel=0.001)
    return root


def make_fan_support(name, x, y, cooler):
    # A bored post from the heatsink base to the fan mounting sleeve; the screw
    # tip enters the metal post instead of hanging in space above the fins.
    count, vertices, faces = 32, [], []
    for i in range(count):
        angle = i * math.tau / count
        for radius, z in ((.028, .26), (.075, .26), (.028, .86), (.075, .86)):
            vertices.append((radius*math.cos(angle), radius*math.sin(angle), z))
    for i in range(count):
        a, b = i*4, (i+1) % count*4
        faces.extend([(a, b, b+1, a+1), (a+2, a+3, b+3, b+2),
                      (a, a+2, b+2, b), (a+1, b+1, b+3, a+3)])
    return mesh(name, vertices, faces, 'Aluminum', cooler, position=(x, y, 0))


def make_fan_housing(parent):
    count, half, inner, height = 96, FAN_SIZE / 2, FAN_SIZE * 0.438, 0.115
    vertices, faces = [], []
    for i in range(count):
        angle = i * math.tau / count
        c, s = math.cos(angle), math.sin(angle)
        outer = half / max(abs(c), abs(s))
        vertices.extend([(inner*c, inner*s, 0), (outer*c, outer*s, 0),
                         (inner*c, inner*s, height), (outer*c, outer*s, height)])
    for i in range(count):
        a, b = i * 4, (i + 1) % count * 4
        faces.extend([(a, b, b+1, a+1), (a+2, a+3, b+3, b+2),
                      (a, a+2, b+2, b), (a+1, b+1, b+3, a+3)])
    return mesh('fan-housing', vertices, faces, 'Fan plastic', parent, bevel=0.012)


def bezier(a, b, c, d, count=10):
    return [tuple((1-t)**3*a[k] + 3*(1-t)**2*t*b[k] + 3*(1-t)*t*t*c[k] + t**3*d[k]
                  for k in (0, 1)) for t in [i / count for i in range(count)]]


def make_rotor(parent):
    rotor = group('fan-rotor', parent, (0, 0, 0.026), attachment='fan-assembly')
    # A curved blade outline with actual thickness; shared mesh data for easy edits.
    outline = bezier((.24, -.06), (.44, -.12), (.69, -.09), (.85, .07))
    outline += bezier((.85, .07), (.89, .14), (.88, .21), (.79, .32))
    outline += bezier((.79, .32), (.61, .16), (.40, .11), (.23, .10))
    scale = FAN_SIZE / 2.13
    vertices = [(x*scale, -y*scale, z) for z in (0, .033) for x, y in outline]
    n = len(outline)
    faces = [tuple(range(n-1, -1, -1)), tuple(range(n, n*2))]
    faces += [(i, (i+1)%n, (i+1)%n+n, i+n) for i in range(n)]
    blade = mesh('fan-blade-1', vertices, faces, 'Fan blades', rotor, bevel=.005)
    for i in range(1, BLADE_COUNT):
        copy = blade.copy()
        place(copy, f'fan-blade-{i+1}', rotor)
        copy.rotation_euler.z = i * math.tau / BLADE_COUNT
    cylinder('fan-hub', .287*scale, .15, (0, 0, .035), 'Fan plastic', rotor)
    cylinder('fan-hub-cap', .237*scale, .007, (0, 0, .114), 'Fan blades', rotor)
    cylinder('hub-center', .04*scale, .008, (0, 0, .12), 'Steel', rotor, vertices=24)
    return rotor


def make_cable(fan):
    # Local origin cancels the fan offset so the control-point coordinates stay legible.
    cable = group('fan-cable', fan, (.43, 0, -.935), attachment='fan-assembly')
    start_x = -.43 + FAN_SIZE / 2 - .04
    points = [(start_x, -.86, .986), (.84, -1.17, .90), (1.29, -1.23, .56),
              (2.17, -1.15, .27), (2.59, -.86, .205), (2.54, -.39, .205)]
    for index, mat in enumerate(('Cable black', 'Cable red')):
        curve = bpy.data.curves.new(mat + '-path', 'CURVE')
        curve.dimensions = '3D'
        curve.resolution_u = 12
        curve.bevel_depth = .023
        curve.bevel_resolution = 3
        curve.use_fill_caps = True
        spline = curve.splines.new('BEZIER')
        spline.bezier_points.add(len(points) - 1)
        for point, (x, y, z) in zip(spline.bezier_points, points):
            point.co = (x, y, z + index*.039)
            point.handle_left_type = point.handle_right_type = 'AUTO'
        obj = bpy.data.objects.new('fan-positive-wire' if index else 'fan-ground-wire', curve)
        place(obj, obj.name, cable)
        curve.materials.append(MATERIALS[mat])
    plug = group('fan-plug', cable, (2.54, -.29, .202), role='removable',
                 direction=(0, -1, 0), attachment='board-fan-socket')
    box('plug-body', (.21, .24, .17), (0, 0, 0), 'Connector plastic', plug)
    box('plug-tab', (.09, .09, .026), (0, -.01, .095), 'Connector plastic', plug, bevel=.006)


def make_gpu():
    root = group('gpu', position=(0, 0, .14), role='assembly')
    board = group('board', root)
    box('board-substrate', (BOARD_LENGTH, BOARD_DEPTH, .115), (0, 0, 0), 'Board edge', board)
    box('board-top', (BOARD_LENGTH-.02, BOARD_DEPTH-.02, .008), (0, 0, .061), 'Board', board)
    box('board-bottom', (BOARD_LENGTH-.02, BOARD_DEPTH-.02, .008), (0, 0, -.061), 'Board', board)

    edge = group('edge-connector', root)
    for name, length, x in [('short', .51, -1.76), ('long', 2.99, .12)]:
        box('connector-' + name, (length, .34, .105), (x, -1.43, -.005), 'Board edge', edge)
    for i in range(35):
        x = -1.965 + i*.103
        if -1.53 < x < -1.34:
            continue
        for side in (-1, 1):
            box(f'gold-contact-{i}-{side}', (.071, .265, .009), (x, -1.447, side*.054), 'Gold contacts', edge, bevel=.003)

    bracket = group('mounting-bracket', root, (-3.035, 0, .52))
    # Rails and ribs leave real openings without destructive boolean operations.
    box('bracket-top-flange', (.25, 2.81, .055), (.097, 0, .64), 'Steel', bracket)
    box('bracket-foot', (.16, 2.80, .045), (.064, 0, -.637), 'Steel', bracket)
    for y in (-1.375, 1.375):
        box('bracket-side', (.055, .065, 1.24), (0, y, 0), 'Steel', bracket)
    for z in (-.49, .49):
        box('bracket-vent-rail', (.055, 1.40, .30), (0, -.66, z), 'Steel', bracket)
    for i in range(7):
        box(f'bracket-vent-rib-{i}', (.055, .10, .70), (0, -1.22+i*.215, 0), 'Steel', bracket, bevel=.006)
    for z in (-.45, .39):
        box('bracket-port-rail', (.055, 1.33, .38), (0, .68, z), 'Steel', bracket)
    for y in (.17, 1.20):
        box('bracket-port-side', (.055, .29, .46), (0, y, -.04), 'Steel', bracket)
    box('display-port-shell', (.30, .73, .37), (.19, .69, -.06), 'Aluminum', bracket)
    box('display-port-interior', (.018, .58, .245), (-.016, .69, -.06), 'Recess', bracket)

    cooler = group('cooler-assembly', root, role='assembly', direction=(0, 0, 1),
                   requires=['fan-plug'] + [f'cooler-screw-{i+1}' for i in range(4)])
    sink = group('heatsink', cooler, (-.22, 0, .19), attachment='cooler-assembly')
    box('heatsink-base', (HEATSINK_WIDTH, 2.26, .14), (0, 0, 0), 'Aluminum', sink, bevel=.025)
    spacing = (HEATSINK_WIDTH - .21) / (FIN_COUNT - 1)
    fin = box('heatsink-fins', (.065, 2.20, .535), (-(HEATSINK_WIDTH-.21)/2, 0, .337), 'Aluminum', sink, bevel=.01)
    array = fin.modifiers.new('Fin count and spacing', 'ARRAY')
    array.count = FIN_COUNT
    array.use_relative_offset = False
    array.use_constant_offset = True
    array.constant_offset_displace = (spacing, 0, 0)

    fan = group('fan-assembly', cooler, (-.43, 0, .935), role='assembly', direction=(0, 0, 1),
                requires=['fan-plug'] + [f'fan-screw-{i+1}' for i in range(4)])
    make_fan_housing(fan)
    make_rotor(fan)
    mount = FAN_SIZE / 2 - .135
    for i in range(4):
        x = (-1 if i < 2 else 1)*mount
        y = (1 if i % 2 else -1)*mount
        cylinder(f'fan-mount-{i+1}', .095, .145, (x, y, -.077), 'Fan plastic', fan, vertices=24)
        make_fan_support(f'fan-standoff-{i+1}', x-.43, y, cooler)
        screw(f'fan-screw-{i+1}', (x-.43, y, 1.077), cooler)
        x = (-1 if i < 2 else 1)*1.72 - .22
        y = (1 if i % 2 else -1)*.89
        cylinder(f'cooler-standoff-{i+1}', .085, .07, (x, y, .092), 'Aluminum', root, vertices=24)
        screw(f'cooler-screw-{i+1}', (x, y, -.117), root, rear=True)
    make_cable(fan)

    socket = group('board-fan-socket', root, (2.54, -.135, .19))
    box('socket-base', (.30, .23, .10), (0, 0, -.053), 'Connector plastic', socket)
    box('socket-back', (.30, .055, .21), (0, .10, 0), 'Connector plastic', socket)
    for side in (-1, 1):
        box(f'socket-side-{side}', (.038, .21, .17), (side*.135, 0, -.005), 'Connector plastic', socket, bevel=.008)
    return root


def make_stage(scene):
    stage = bpy.data.collections.new('STAGE — excluded from GPU export')
    scene.collection.children.link(stage)
    box('worktable', (40, 40, .36), (0, 0, -.18), 'Table', collection=stage)
    target = Vector((0, 0, .45))
    camera_data = bpy.data.cameras.new('Preview camera')
    camera = bpy.data.objects.new('Preview camera', camera_data)
    place(camera, camera.name, position=(8, -11.5, 9), collection=stage)
    camera.rotation_euler = (target - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera_data.lens = 48
    scene.camera = camera
    for name, position, energy, size, color in [
        ('Key softbox', (-3, -4, 8), 1600, 5, (1, .91, .78)),
        ('Fill softbox', (4, 5, 4), 950, 4, (.80, .9, 1)),
        ('Rim softbox', (-3, 5, 4), 1100, 3, (1, 1, .90)),
    ]:
        data = bpy.data.lights.new(name, 'AREA')
        data.energy, data.shape, data.size, data.color = energy, 'DISK', size, color
        light = bpy.data.objects.new(name, data)
        place(light, name, position=position, collection=stage)
        light.rotation_euler = (target - light.location).to_track_quat('-Z', 'Y').to_euler()
    world = bpy.data.worlds.new('Workbench world')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs[0].default_value = (.19, .22, .17, 1)
    world.node_tree.nodes['Background'].inputs[1].default_value = .45
    scene.world = world
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 1400, 1000
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = 'AgX'
    return stage


def main():
    global MODEL
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--blend', type=Path, default=ROOT / 'models/gpu.blend')
    parser.add_argument('--glb', type=Path, default=ROOT / 'src/assets/gpu.glb')
    parser.add_argument('--force', action='store_true', help='Regenerate and overwrite an existing .blend file')
    parser.add_argument('--render', type=Path, help='Optional preview PNG path')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    args.blend, args.glb = args.blend.resolve(), args.glb.resolve()
    if args.blend.exists() and not args.force:
        raise RuntimeError(f'{args.blend} already exists. Use model:export to preserve edits, or --force to regenerate.')
    if not bpy.app.background:
        raise RuntimeError('Run via npm run model:build in a separate Blender background process.')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.name = 'BENCH — GPU study'
    scene.unit_settings.system = 'NONE'
    MODEL = bpy.data.collections.new('GPU — export this hierarchy')
    scene.collection.children.link(MODEL)
    make_materials()
    root = make_gpu()
    make_stage(scene)
    bpy.context.view_layer.update()
    root['asset_notes'] = 'Illustrative viewer units, not manufacturing dimensions. Z-up in Blender; Y-up on GLB export.'
    root['service_order'] = 'Unplug fan → remove four fan screws → lift fan; optionally remove rear cooler screws → lift cooler. Refit in reverse order.'
    text = bpy.data.texts.new('START HERE')
    text.write('BENCH GPU\n\nEdit meshes normally. The heatsink fin count is an Array modifier.\n'
               'The two fan wires are editable Bezier curves. Fan blades share mesh data.\n'
               'Select fan-rotor to spin it around local Z; select assembly empties to move whole parts.\n'
               'Save this file, then run npm run model:export from the project.\n'
               'Do not run model:build -- --force after manual edits unless you want to replace them.\n'
               'The STAGE collection is for preview only and is excluded from browser exports.\n')
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    bpy.context.view_layer.objects.active = root
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                area.spaces.active.region_3d.view_distance = 10
                area.spaces.active.region_3d.view_location = (0, 0, .5)
                area.spaces.active.region_3d.view_rotation = Quaternion((.87, .36, .14, .29)).normalized()
                area.spaces.active.shading.type = 'MATERIAL'
                area.spaces.active.overlay.show_extras = False
    args.blend.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(args.blend))
    export_gpu(args.glb)
    if args.render:
        args.render.parent.mkdir(parents=True, exist_ok=True)
        scene.render.filepath = str(args.render.resolve())
        scene.render.image_settings.file_format = 'PNG'
        bpy.ops.render.render(write_still=True)
    print(f'GPU_CREATED: {args.blend}')


if __name__ == '__main__':
    main()
