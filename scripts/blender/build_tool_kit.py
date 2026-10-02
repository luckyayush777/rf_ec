"""Round the existing tool geometry while retaining working points and proportions.

Initial conversion reads artifacts/tool-kit-baseline.json, captured from the native scenes.
Later edits use the saved Blender source and export_tool_kit.py instead.
"""
from pathlib import Path
import json
import math
import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'models/tool-kit.blend'
if SOURCE.exists():
    raise RuntimeError('Tool source already exists. Edit/export the saved source instead.')
baseline = json.loads((ROOT / 'artifacts/tool-kit-baseline.json').read_text())
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def material(name, color, roughness=.5, metallic=0, alpha=1):
    result = bpy.data.materials.new(name)
    channels = [int(color[i:i+2],16)/255 for i in (0,2,4)]
    linear = tuple(c/12.92 if c<.04045 else ((c+.055)/1.055)**2.4 for c in channels)
    result.diffuse_color = (*linear,alpha)
    result.use_nodes = True
    node = next(n for n in result.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    node.inputs['Base Color'].default_value = (*linear,1)
    node.inputs['Roughness'].default_value = roughness
    node.inputs['Metallic'].default_value = metallic
    node.inputs['Alpha'].default_value = alpha
    return result

mats = {name: material('Kit '+name,*args) for name,args in {
    'rubber':('293b42',.73), 'ivory':('eddec3',.48),
    'steel':('aabcc4',.28,.8), 'air':('bd654b',.40),
    'dev':('8c739e',.42), 'nylon':('426485',.48),
    'ipa':('648faa',.42), 'cloth':('f0eee4',.95),
    'paste':('9faaa8',.55), 'barrel':('d3dfe0',.28,0,.38),
    'oil':('dfa947',.38,0,.88), 'glass':('b6d8df',.08,0,.20),
    'ir':('dc8246',.40), 'irglass':('323a50',.18,.55),
}.items()}

def choose(tool,name):
    if tool=='AirBlower':
        return mats['air'] if name=='Body' else mats['steel'] if name in ['Nozzle','Switch'] else mats['rubber']
    if tool=='DevBlower':
        return mats['dev'] if name=='Motor' else mats['steel'] if name in ['Collar','Nozzle'] else mats['rubber']
    if tool=='Spudger': return mats['rubber'] if name=='Grip' else mats['nylon']
    if tool=='IpaWipe': return mats['ipa'] if name=='Bottle' else mats['cloth'] if name=='Pad' else mats['ivory']
    if tool=='PasteSyringe':
        return mats['barrel'] if name=='Barrel' else mats['paste'] if name=='Paste' else mats['ir'] if name=='Nozzle' else mats['ivory'] if name=='Thumb' else mats['rubber']
    if tool=='FanOiler': return mats['steel'] if name=='Needle' else mats['oil']
    if tool=='Loupe': return mats['glass'] if name=='Lens' else mats['ivory'] if name=='Ring' else mats['steel'] if name=='Neck' else mats['rubber']
    return mats['ir'] if name=='Body' else mats['irglass'] if name=='LensGlass' else mats['rubber']

def soften(obj, width, smooth=True):
    if width>0:
        bevel=obj.modifiers.new('Rounded edge highlights','BEVEL')
        bevel.width=width
        bevel.segments=3
        methods=[i.identifier for i in bevel.bl_rna.properties['limit_method'].enum_items]
        bevel.limit_method=next(i for i in methods if i=='ANGLE')
        bevel.angle_limit=math.radians(28)
    for polygon in obj.data.polygons: polygon.use_smooth=smooth
    normals=obj.modifiers.new('Weighted highlight normals','WEIGHTED_NORMAL')
    normals.keep_sharp=True

def root(name):
    node=bpy.data.objects.new(name,None)
    bpy.context.collection.objects.link(node)
    node['art_style']='rounded tool kit'
    return node

def gd_to_blender(v): return Vector((v[0],-v[2],v[1]))

roots={}
for name,parts in baseline.items():
    parent=root(name)
    roots[name]=parent
    for part in parts:
        if part['name']=='Display': continue  # Keep the native quad and its screen UVs.
        position=gd_to_blender(part['position'])
        vertices=[gd_to_blender(v)-position for v in part['points']]
        data=bpy.data.meshes.new(name+'__'+part['name'])
        data.from_pydata(vertices,[],[tuple(range(i,i+3)) for i in range(0,len(vertices),3)])
        bm=bmesh.new()
        bm.from_mesh(data)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bmesh.ops.dissolve_limit(bm,angle_limit=.0001,verts=list(bm.verts),edges=list(bm.edges))
        bm.to_mesh(data)
        bm.free()
        obj=bpy.data.objects.new(name+'__'+part['name'],data)
        bpy.context.collection.objects.link(obj)
        obj.parent=parent
        obj.location=position
        data.materials.append(choose(name,part['name']))
        minimum=min(max(v[i] for v in vertices)-min(v[i] for v in vertices) for i in range(3))
        width=min(.08,minimum*.18)
        if part['name'] in ['Lens','LensGlass','Ring']: width=min(width,.01)
        if part['name'] in ['Blade','Needle','Nozzle']: width=min(width,.006)
        soften(obj,width)

def box(parent,name,at,size,mat,bevel):
    bpy.ops.mesh.primitive_cube_add(size=1,location=gd_to_blender(at))
    obj=bpy.context.object
    obj.name=parent.name+'__'+name
    obj.scale=(size[0],size[2],size[1])
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    obj.parent=parent
    obj.data.materials.append(mat)
    soften(obj,bevel)
    return obj

# Broad inserts, softened caps and small functional details make the silhouettes readable.
box(roots['AirBlower'],'GripInset',(-.525,.565,0),(.60,.010,.12),mats['ivory'],.004)
for index in range(5):
    box(roots['AirBlower'],'RearSlot%d'%index,(-1.162,0,(index-2)*.078),(.004,.30,.016),mats['steel'],.001)
box(roots['DevBlower'],'GripInsert',(-.65,-.306,0),(.70,.025,.23),mats['rubber'],.01)
box(roots['Spudger'],'EndStripe',(-.62,0,0),(.075,.109,.198),mats['ivory'],.018)
box(roots['IpaWipe'],'Fold',(.62,.061,-.035),(.56,.024,.38),mats['cloth'],.01)
box(roots['IpaWipe'],'FoldEdge',(.62,.072,.15),(.53,.010,.015),mats['ivory'],.004)
box(roots['PasteSyringe'],'FingerRest',(-.47,0,0),(.06,.18,.30),mats['ivory'],.025)
for index in range(7):
    box(roots['PasteSyringe'],'Graduation%d'%index,(-.32+index*.105,.121,0),(.012,.006,.10 if index%2==0 else .065),mats['rubber'],.002)
box(roots['FanOiler'],'GripInsert',(-.35,.154,0),(.40,.010,.08),mats['ivory'],.004)
box(roots['Loupe'],'GripInsert',(-.40,.080,0),(.48,.009,.055),mats['ivory'],.004)
box(roots['ThermalCamera'],'GripInsert',(0,-.68,.219),(.30,.49,.015),mats['ivory'],.006)
box(roots['ThermalCamera'],'Shutter',(.33,.365,0),(.18,.045,.22),mats['rubber'],.016)

# The surface-work versions share these shapes at their existing contact coordinates.
work=root('WorkTools')
roots['WorkTools']=work
box(work,'SpudgerBlade',(-3.5,.2,0),(7,.4,5),mats['nylon'],.085)
box(work,'WipeSheet',(0,.35,0),(7,.7,6),mats['cloth'],.14)
fold=box(work,'WipeFold',(0,.95,-1.4),(6.4,.6,2.6),mats['cloth'],.12)
fold.rotation_euler.x=.15
bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=1,depth=11,location=gd_to_blender((-12.5,.2,0)))
handle=bpy.context.object
handle.name='WorkTools__SpudgerGrip'
handle.rotation_euler.y=math.pi/2
handle.parent=work
handle.data.materials.append(mats['rubber'])
soften(handle,.34)

# Export roots at the origin; preview layout is kept in the editable source only.
bpy.ops.object.select_all(action='DESELECT')
for parent in roots.values():
    parent.select_set(True)
    for child in parent.children_recursive: child.select_set(True)
bpy.context.view_layer.objects.active=roots['AirBlower']
bpy.ops.export_scene.gltf(filepath=str(ROOT/'godot/assets/tool-kit.glb'),use_selection=True,export_apply=True,export_yup=True)
work.hide_render=True
for child in work.children_recursive: child.hide_render=True

# Lay out all eight tools at the same physical scale for a single style sheet.
names=list(baseline)
for index,name in enumerate(names):
    parent=roots[name]
    lowest=min(point[1] for part in baseline[name] for point in part['points'])
    parent.location=( (index%4-1.5)*3.65, (0.5-index//4)*1.85, -.57-lowest+.018)
floor=material('Preview background','34464c',.9)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.57))
bpy.context.object.name='Preview floor'
bpy.context.object.data.materials.append(floor)
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.samples=48
scene.cycles.use_denoising=True
scene.render.resolution_x=2000
scene.render.resolution_y=1000
scene.render.resolution_percentage=100
formats=[i.identifier for i in scene.render.image_settings.bl_rna.properties['file_format'].enum_items]
scene.render.image_settings.file_format=next(i for i in formats if i=='PNG')
scene.world.color=(.1,.1,.1)
for name,at,power,size in [('Soft key',(-4,-3,10),1600,8),('Rim',(5,4,8),1200,7),('Fill',(0,-4,5),450,6)]:
    data=bpy.data.lights.new(name,'AREA')
    data.energy=power
    data.size=size
    node=bpy.data.objects.new(name,data)
    bpy.context.collection.objects.link(node)
    node.location=at
    node.rotation_euler=(-node.location).to_track_quat('-Z','Y').to_euler()
data=bpy.data.cameras.new('Style camera')
camera=bpy.data.objects.new('Style camera',data)
bpy.context.collection.objects.link(camera)
camera.location=(1,-7,15)
camera.rotation_euler=(-camera.location).to_track_quat('-Z','Y').to_euler()
data.type='ORTHO'
data.ortho_scale=15.1
scene.camera=camera
scene.render.filepath=str(ROOT/'artifacts/tool-kit-style.png')
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
bpy.ops.render.render(write_still=True)
print('ROUNDED_TOOL_KIT_EXPORTED')
