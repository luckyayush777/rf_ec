"""Rounded screwdriver study. Exact original length, grip envelope and shaft length.

Run in a separate Blender process; the saved source retains editable bevels.
"""
from pathlib import Path
import math
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'models/screwdriver.blend'
EXPORT = ROOT / 'godot/assets/screwdriver.glb'
OUTPUT = ROOT / 'artifacts/screwdriver-style.png'

if SOURCE.exists():
    raise RuntimeError('Source exists; edit the saved screwdriver instead of regenerating it.')

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def material(name, hex_color, roughness, metallic=0):
    color = tuple(int(hex_color[i:i+2], 16) / 255 for i in (0, 2, 4))
    # Blender node colours are scene-linear; convert authoring sRGB colours.
    linear = tuple(c / 12.92 if c < .04045 else ((c + .055) / 1.055)**2.4 for c in color)
    result = bpy.data.materials.new(name)
    result.diffuse_color = (*linear, 1)
    result.use_nodes = True
    shader = next(n for n in result.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    shader.inputs['Base Color'].default_value = (*linear, 1)
    shader.inputs['Roughness'].default_value = roughness
    shader.inputs['Metallic'].default_value = metallic
    return result

orange = material('Tool enamel - burnt orange', 'dc8246', .36)
rubber = material('Tool grip - charcoal', '293b42', .73)
cream = material('Tool end cap - ivory', 'eddec3', .48)
steel = material('Tool shaft - satin steel', 'aabcc4', .28, .8)
bit = material('Tool bit - hardened steel', '52616b', .36, .75)

tool = bpy.data.objects.new('Screwdriver', None)
bpy.context.collection.objects.link(tool)
tool['art_style'] = 'rounded tool study'
tool['length'] = 2.4
tool['grip_length'] = .88
tool['shaft_length'] = 1.28

def mesh(name, vertices, faces, mat, bevel=0):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.parent = tool
    data.materials.append(mat)
    for polygon in data.polygons:
        polygon.use_smooth = True
    if bevel:
        modifier = obj.modifiers.new('Soft edge bevel', 'BEVEL')
        modifier.width = bevel
        modifier.segments = 3
    weighted = obj.modifiers.new('Weighted highlight normals', 'WEIGHTED_NORMAL')
    weighted.keep_sharp = True
    return obj

def profile(name, rings, mat, sections=48, lobes=0, bevel=0):
    vertices = []
    for x, radius in rings:
        for index in range(sections):
            angle = index * math.tau / sections
            r = radius * (1 - lobes * (1 - math.cos(6 * angle)) * .5)
            vertices.append((x, r * math.cos(angle), r * math.sin(angle)))
    faces = [tuple(reversed(range(sections)))]
    for row in range(len(rings)-1):
        for index in range(sections):
            nxt = (index + 1) % sections
            faces.append((row*sections+index, row*sections+nxt, (row+1)*sections+nxt, (row+1)*sections+index))
    faces.append(tuple((len(rings)-1)*sections+index for index in range(sections)))
    return mesh(name, vertices, faces, mat, bevel)

# The grip stays within the original [-1.11, -.23] / radius .201 envelope.
profile('Grip', [(-1.11,.140),(-1.095,.165),(-1.06,.185),(-1.0,.195),
                (-.90,.201),(-.75,.201),(-.52,.195),(-.40,.178),
                (-.32,.155),(-.255,.145),(-.23,.125)], orange, lobes=.035, bevel=.006)
profile('EndCap', [(-1.109,.131),(-1.095,.151),(-1.08,.155),(-1.065,.15)], cream, bevel=.005)
profile('EndCapInset', [(-1.111,.088),(-1.108,.101),(-1.104,.101)], rubber, bevel=.002)
profile('Neck', [(-.325,.153),(-.305,.158),(-.25,.148),(-.23,.125)], rubber, bevel=.006)
profile('Collar', [(-.23,.11),(-.222,.124),(-.10,.124),(-.08,.109),(-.07,.075)], steel, bevel=.004)
shaft = profile('Shaft', [(-.11,.046),(-.10,.046),(1.15,.046),(1.17,.043)], steel, bevel=.002)
# Maintain the original Shaft node's local centre for picking and authoring.
for vertex in shaft.data.vertices: vertex.co.x -= .53
shaft.location.x = .53

# Three broad, recessed rubber pads follow the handle's barrel instead of sharp bands.
for index in range(3):
    centre = index * math.tau / 3 + math.pi / 2
    xs = [(-.94,.184, .22),(-.91,.194,.34),(-.84,.196,.36),
          (-.57,.191,.36),(-.49,.186,.34),(-.45,.179,.22)]
    vertices = []
    for x, radius, half_angle in xs:
        for j in range(9):
            angle = centre + (j / 8 * 2 - 1) * half_angle
            vertices.append((x, radius * math.cos(angle), radius * math.sin(angle)))
    faces = []
    for row in range(len(xs)-1):
        for j in range(8):
            faces.append((row*9+j,row*9+j+1,(row+1)*9+j+1,(row+1)*9+j))
    panel = mesh('GripPanel%d' % index, vertices, faces, rubber)
    thickness = panel.modifiers.new('Inset pad thickness', 'SOLIDIFY')
    thickness.thickness = .012
    thickness.offset = 1
    bevel = panel.modifiers.new('Rounded pad perimeter', 'BEVEL')
    bevel.width = .007
    bevel.segments = 3

# A tapered cruciform Phillips bit, not a flat rectangular blade.
cross = [(1,.30),(.30,.30),(.30,1),(-.30,1),(-.30,.30),(-1,.30),
         (-1,-.30),(-.30,-.30),(-.30,-1),(.30,-1),(.30,-.30),(1,-.30)]
vertices = []
for x, radius in [(1.14,.043),(1.19,.043),(1.265,.021),(1.29,.009)]:
    vertices.extend((x,y*radius,z*radius) for y,z in cross)
faces = [tuple(reversed(range(12)))]
for row in range(3):
    for index in range(12):
        nxt = (index+1)%12
        faces.append((row*12+index,row*12+nxt,(row+1)*12+nxt,(row+1)*12+index))
faces.append(tuple(36+index for index in range(12)))
mesh('Tip', vertices, faces, bit, .0015)

# Export just the tool; stage and lights remain in the editable source only.
bpy.ops.object.select_all(action='DESELECT')
tool.select_set(True)
for obj in tool.children: obj.select_set(True)
bpy.context.view_layer.objects.active = tool
EXPORT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(EXPORT), use_selection=True,
                          export_apply=True, export_yup=True)

scene = bpy.context.scene
try:
    scene.render.engine = 'CYCLES'
except TypeError:
    pass
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.resolution_x = 1600
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
formats = [item.identifier for item in scene.render.image_settings.bl_rna.properties['file_format'].enum_items]
scene.render.image_settings.file_format = next(value for value in formats if value == 'PNG')
transforms = [item.identifier for item in scene.view_settings.bl_rna.properties['view_transform'].enum_items]
if 'AgX' in transforms: scene.view_settings.view_transform = 'AgX'
scene.world.color = (.08,.08,.08)
floor_material = material('Preview backdrop', '34464c', .85)
bpy.ops.mesh.primitive_plane_add(size=200, location=(0,0,-.215))
floor = bpy.context.object
floor.name = 'Preview floor'
floor.data.materials.append(floor_material)

def light(name, at, energy, size):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy = energy
    data.shape = 'DISK'
    data.size = size
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = at
    obj.rotation_euler = (Vector((0,0,0))-obj.location).to_track_quat('-Z','Y').to_euler()

light('Soft key', (-1,-2.5,4), 280, 3)
light('Long rim', (1,2,2.5), 200, 2.2)
light('Fill', (2,-1,1.5), 65, 2)
camera_data = bpy.data.cameras.new('Style camera')
camera = bpy.data.objects.new('Style camera', camera_data)
bpy.context.collection.objects.link(camera)
camera.location = (1.5,-4.5,3.8)
camera.rotation_euler = (Vector((.05,0,0))-camera.location).to_track_quat('-Z','Y').to_euler()
camera_data.type = 'ORTHO'
camera_data.ortho_scale = 3.1
scene.camera = camera
scene.render.filepath = str(OUTPUT)
SOURCE.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
bpy.ops.render.render(write_still=True)
print('SCREWDRIVER_STYLE_EXPORTED', EXPORT)
