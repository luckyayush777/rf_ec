"""Author a standalone, meter-scale BENCH workshop. Refuses to overwrite saved edits.
blender --background --factory-startup --python scripts/blender/build_shop_interior.py
Use -- --force only to intentionally rebuild this source, discarding manual edits.
"""
import math
import random
import sys
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'models/shop-interior.blend'
PREVIEW = ROOT / 'artifacts/shop-interior'
if DEST.exists() and '--force' not in sys.argv:
    raise RuntimeError('shop-interior.blend exists; edit it directly or explicitly pass --force.')
random.seed(27)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'

def collection(name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    return c

shell = collection('01 Room - visible shell')
cutaway = collection('02 Room - hide for cutaway (front right ceiling)')
furniture = collection('03 Workbench and storage')
instruments = collection('04 Oscilloscope and electronics')
props = collection('05 Labelled bins and hand tools')
stage = collection('06 Cameras and lighting')
current = shell

def material(name, rgb, rough=.6, metal=0, emission=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*rgb, 1)
    p.inputs['Roughness'].default_value = rough
    p.inputs['Metallic'].default_value = metal
    if emission:
        p.inputs['Emission Color'].default_value = (*rgb, 1)
        p.inputs['Emission Strength'].default_value = emission
    return m

ivory = material('Warm painted plaster', (.73,.76,.71))
ink = material('Graphite powder coat', (.045,.066,.073))
steel = material('Brushed steel', (.34,.4,.42), .3, .75)
wood = material('Beech worktop', (.49,.30,.14))
edge = material('Beech endgrain', (.32,.17,.075))
teal = material('Petrol blue cabinet enamel', (.055,.19,.21), .4)
mat = material('Muted jade ESD rubber', (.085,.29,.245))
blue = material('Blue polypropylene bins', (.075,.23,.40), .35)
red = material('Rust red polypropylene bins', (.52,.13,.065), .4)
paper = material('Ivory label stock', (.9,.86,.72))
case = material('Instrument ABS ivory', (.64,.68,.63), .4)
screen = material('Scope glass', (.008,.027,.029), .22)
green = material('Phosphor green', (.27,.95,.40), .4, emission=2)
amber = material('Amber indicator', (1,.42,.06), .4, emission=1)
grid = material('Screen grid', (.055,.19,.16), .7, emission=.3)
light = material('Warm diffuser', (1,.85,.58), .3, emission=3)
mortar = material('Warm mortar', (.28,.26,.225))
bricks = [material('Fired brick %d'%i, c) for i,c in enumerate([
    (.39,.16,.09),(.48,.21,.12),(.34,.13,.08),(.43,.19,.12),(.53,.26,.16)])]
floor = [material('Floor tile %d'%i,(.28+i*.008,.31+i*.008,.30+i*.008)) for i in range(4)]

def put(obj, name, matl=None):
    obj.name = name
    for c in list(obj.users_collection): c.objects.unlink(obj)
    current.objects.link(obj)
    if matl: obj.data.materials.append(matl)
    return obj

def box(name, loc, dims, matl, bevel=.008):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = put(bpy.context.object,name,matl)
    o.dimensions = dims
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new('Soft manufactured edges','BEVEL'); mod.width=bevel; mod.segments=2
        o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    return o

def cylinder(name, loc, radius, depth, matl, axis='Z', vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc)
    o=put(bpy.context.object,name,matl)
    if axis=='Y': o.rotation_euler.x=math.pi/2
    if axis=='X': o.rotation_euler.y=math.pi/2
    mod=o.modifiers.new('Edge radius','BEVEL'); mod.width=.003; mod.segments=2
    o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return o

def text(name, body, loc, size, matl=ink, rotation=(math.pi/2,0,0)):
    data=bpy.data.curves.new(name,'FONT'); data.body=body; data.size=size
    data.align_x='CENTER'; data.align_y='CENTER'; data.extrude=.0002
    obj=bpy.data.objects.new(name,data); current.objects.link(obj)
    obj.location=loc; obj.rotation_euler=rotation; data.materials.append(matl)
    return obj

def line(name, points, radius, matl):
    data=bpy.data.curves.new(name,'CURVE'); data.dimensions='3D'
    data.bevel_depth=radius; data.bevel_resolution=2
    spline=data.splines.new('POLY'); spline.points.add(len(points)-1)
    for p,co in zip(spline.points,points): p.co=(*co,1)
    obj=bpy.data.objects.new(name,data); current.objects.link(obj); data.materials.append(matl)
    return obj

def aim(obj, target): obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()

# 6 x 4.8 m room, 3 m high. Front and right walls + ceiling remain editable.
box('floor-slab',(0,0,-.095),(6.2,5,.19),ink)
for x in range(10):
    for y in range(8):
        box('vinyl-tile-%02d-%02d'%(x,y),(-2.7+x*.6,-2.1+y*.6,.007),(.595,.595,.014),random.choice(floor),.001)
box('back-wall-mortar',(0,2.45,1.5),(6.2,.16,3),mortar,0)
# Join the brick courses to one mesh to keep game import practical.
brick_objects=[]
for row in range(25):
    for col in range(24):
        x=-3.0+col*.265+(row%2)*.1325
        if x > 2.95: continue
        o=box('brick',(x,2.348, .063+row*.12),(.253,.045,.108),random.choice(bricks),0)
        brick_objects.append(o)
bpy.ops.object.select_all(action='DESELECT')
for o in brick_objects: o.select_set(True)
bpy.context.view_layer.objects.active=brick_objects[0]
bpy.ops.object.join(); bpy.context.object.name='brick-wall-running-bond'
mod=bpy.context.object.modifiers.new('Rounded fired edges','BEVEL'); mod.width=.004; mod.segments=1
box('left-plaster-wall',(-3.06,0,1.5),(.12,4.8,3),ivory)
box('left-skirting',(-2.978,0,.075),(.035,4.8,.15),teal)
box('back-skirting',(0,2.3,.075),(6,.035,.15),teal)
current=cutaway
box('right-plaster-wall',(3.06,0,1.5),(.12,4.8,3),ivory)
box('front-wall-left',(-1.7,-2.46,1.5),(2.6,.12,3),ivory)
box('front-wall-right',(1.9,-2.46,1.5),(2.2,.12,3),ivory)
box('front-door-header',(.2,-2.46,2.6),(1.2,.12,.8),ivory)
box('ceiling',(0,0,3.07),(6.2,5,.14),ivory)
cutaway.hide_render=True
cutaway.hide_viewport=True
current=shell
# Door on the visible left wall: inlaid inset, frame, lever.
box('store-door',(-2.984,-1.25,1.05),(.035,.9,2.1),teal)
for y in [-1.74,-.76]: box('door-frame',(-2.95,y,1.08),(.08,.055,2.16),paper)
box('door-lintel',(-2.95,-1.25,2.17),(.08,1.04,.06),paper)
cylinder('door-handle',(-2.89,-.92,1),.018,.16,steel,'Y')
text('door-sign','STORES',(-2.955,-1.25,1.65),.075,paper,(math.pi/2,0,math.pi/2))
box('shop-sign',(0,2.285,2.62),(2.7,.07,.38),ink)
text('shop-title','B E N C H',(0,2.24,2.67),.20,paper)
text('shop-subtitle','ELECTRONICS  /  SERVICE & REPAIR',(0,2.24,2.53),.049,paper)

current=furniture
box('main-worktop',(0,1.77,.9),(5.25,.98,.075),wood,.02)
box('front-worktop-edge',(0,1.277,.888),(5.25,.026,.075),edge)
for x in [-2.38,2.38]:
    box('drawer-cabinet',(x,1.8,.455),(.42,.8,.82),teal)
    for i in range(4):
        z=.17+i*.185
        box('drawer-front',(x,1.389,z),(.385,.035,.165),teal)
        box('drawer-pull',(x,1.355,z+.025),(.17,.028,.019),steel)
    for y in [1.49,2.10]: cylinder('cabinet-foot',(x,y,.045),.03,.065,ink)
box('underbench-stretcher',(0,2.12,.25),(4.5,.06,.07),ink)
box('esd-work-mat',(-.1,1.62,.944),(1.35,.62,.013),mat,.016)
text('mat-print','BENCH  /  ESD',(-.53,1.36,.952),.032,paper,(0,0,0))
for x in [-2.3,0,2.3]:
    box('shelf-upright',(x,2.23,1.70),(.04,.045,1.40),ink)
box('upper-supply-shelf',(0,2.035,2.08),(5.1,.48,.045),wood)
box('task-light-diffuser',(0,1.965,2.05),(3.2,.04,.022),light)
box('tool-board',(-.05,2.28,1.56),(1.45,.025,.70),teal)
for i in range(15):
    for j in range(6):
        cylinder('pegboard-hole',(-.70+i*.095,2.262,1.28+j*.10),.006,.003,ink,'Y',8)
for x in [-1.0,1.25]:
    box('power-rail',(x,2.27,1.05),(.75,.04,.085),paper)
    for k in range(4):
        for dx in [-.012,.012]: box('outlet-slot',(x-.27+k*.18+dx,2.246,1.05),(.006,.008,.022),ink,.001)

current=instruments
# A distinctive bench oscilloscope with inset display, grid, knobs and two probes.
sx,sy,sz=-1.55,1.865,1.19
box('oscilloscope-body',(sx,sy,sz),(.84,.39,.46),case,.035)
box('oscilloscope-front',(sx,sy-.205,sz),(.79,.035,.40),paper,.017)
box('scope-display-bezel',(sx-.16,sy-.232,sz+.02),(.44,.028,.30),ink,.012)
box('scope-display-glass',(sx-.16,sy-.25,sz+.02),(.39,.008,.255),screen,.003)
for i in range(9):
    x=sx-.345+i*.046
    line('scope-grid-v',[(x,sy-.257,sz-.092),(x,sy-.257,sz+.13)],.0006,grid)
for i in range(6):
    z=sz-.092+i*.044
    line('scope-grid-h',[(sx-.345,sy-.257,z),(sx+.025,sy-.257,z)],.0006,grid)
line('scope-waveform',[(sx-.345+i*.0037,sy-.260,sz+.02+.067*math.sin(i*.17)) for i in range(101)],.0016,green)
text('scope-readout','CH1  2.00V    500us',(sx-.16,sy-.262,sz+.111),.014,green)
text('scope-brand','BENCH / DS-2016',(sx-.14,sy-.228,sz+.18),.023,ink)
for row in range(3):
    for col in range(3):
        x=sx+.12+col*.09; z=sz+.12-row*.085
        cylinder('scope-knob',(x,sy-.25,z),.024 if row==0 else .018,.029,ink,'Y')
        box('knob-tick',(x,sy-.266,z+.009),(.003,.002,.009),paper,.0005)
for i,m in enumerate([amber,green]):
    x=sx+.13+i*.15
    cylinder('scope-bnc-jack',(x,sy-.25,sz-.15),.026,.024,steel,'Y')
    cylinder('scope-channel-ring',(x,sy-.268,sz-.15),.018,.012,m,'Y')
    line('scope-probe-lead',[(x,sy-.28,sz-.15),(x,1.40,1.01),(x+.18,1.25,.967),(x+.55,1.39,.967),(x+.66,1.64,.965)],.009,ink)
    cylinder('scope-probe-tip',(x+.66,1.68,.965),.011,.12,steel,'Y')
for i in range(11): box('scope-vent',(sx+.426,sy-.12+i*.025,sz+.08),(.004,.008,.15),ink,.001)
for x in [sx-.3,sx+.3]: box('scope-foot',(x,sy,.955),(.08,.25,.04),ink)
line('scope-carry-handle',[(sx-.31,sy,sz+.24),(sx-.31,sy,sz+.31),(sx+.31,sy,sz+.31),(sx+.31,sy,sz+.24)],.019,ink)

# Solder station, supply, loose PCB and tool rack.
box('solder-station',(.85,1.72,1.04),(.28,.30,.20),teal,.018)
box('solder-display',(.85,1.563,1.075),(.17,.009,.055),screen)
text('solder-temperature','350 C',(.85,1.556,1.075),.031,amber)
cylinder('solder-control',(.85,1.547,.999),.024,.025,ink,'Y')
box('iron-stand',(1.2,1.58,.967),(.17,.28,.055),ink)
line('iron-cradle',[(1.2,1.65,.97),(1.2,1.72,1.1),(1.2,1.66,1.15)],.018,steel)
line('solder-iron',[(1.2,1.72,1.17),(1.2,1.57,1.10)],.020,teal)
line('solder-tip',[(1.2,1.57,1.10),(1.2,1.44,1.045)],.006,steel)
line('iron-cord',[(1.2,1.74,1.18),(1.35,1.93,.96),(.96,2.03,.96),(.85,1.86,1.03)],.009,ink)
box('bench-power-supply',(-1.78,2.00,2.30),(.5,.31,.39),case,.02)
box('supply-display',(-1.78,1.837,2.37),(.35,.012,.10),screen)
text('supply-reading','12.00 V',(-1.78,1.826,2.37),.052,green)
for x,m in [(-1.89,red),(-1.69,ink)]: cylinder('supply-terminal',(x,1.81,2.20),.025,.033,m,'Y')
box('spare-pcb',(-.12,1.67,.968),(.36,.23,.022),teal,.003)
for i in range(5): box('pcb-chip',(-.25+i*.065,1.66,.988),(.04,.07,.022),ink,.002)
for i in range(5):
    x=-.5+i*.19
    line('hanging-driver-shaft',[(x,2.22,1.43),(x,2.22,1.60)],.009,steel)
    cylinder('hanging-driver-grip',(x,2.22,1.66),.028,.13,red if i%2 else ink)

current=props
def bin(name, x,y,z, color, w=.39,d=.34,h=.23):
    box(name+'-bottom',(x,y,z+.012),(w,d,.024),color)
    for dx in [-w/2+.012,w/2-.012]: box(name+'-side',(x+dx,y,z+h/2),(.024,d,h),color)
    box(name+'-back',(x,y+d/2-.012,z+h/2),(w,.024,h),color)
    box(name+'-front',(x,y-d/2+.012,z+h*.30),(w,.024,h*.60),color)
    box(name+'-label',(x,y-d/2-.004,z+h*.31),(w*.78,.005,h*.28),paper,.002)
    text(name+'-text',name.upper(),(x,y-d/2-.008,z+h*.31),min(.034,w*.105),ink)
    # A few recognisable spare components inside the open bin.
    for i in range(4):
        xx=x+random.uniform(-w*.3,w*.3); yy=y+random.uniform(-d*.24,d*.24)
        cylinder(name+'-contents',(xx,yy,z+.045),.015,.045,steel)

for i,name in enumerate(['SCREWS','FAN PLUGS','CAPACITORS']): bin(name,1.15+i*.46,2.00,.94,blue)
for i,name in enumerate(['THERMAL PADS','FANS','CABLES','HEATSHRINK','SPARES']):
    bin(name,-.84+i*.66,2.03,2.105,blue if i%2 else red,w=.57,d=.38,h=.30)
# labelled lidded boxes stacked at the left of the desk
for i,name in enumerate(['M2 / M3','WASHERS']):
    box('organizer-'+name,(-2.2,1.60,.984+i*.10),(.32,.28,.08),case)
    box('organizer-lid',(-2.2,1.60,1.028+i*.10),(.34,.30,.014),paper)
    text('organizer-label',name,(-2.2,1.452,.99+i*.10),.025,ink)
cylinder('solder-spool',(.60,1.82,.99),.055,.08,blue)
cylinder('solder-wire',(.60,1.82,.99),.057,.043,steel)

current=furniture
# Small rolling stool in the clear working aisle.
cylinder('stool-seat',(-.45,.30,.58),.27,.085,ink)
cylinder('stool-column',(-.45,.30,.31),.037,.46,steel)
for i in range(5):
    a=i*math.tau/5
    p=(-.45+.32*math.cos(a),.30+.32*math.sin(a),.085)
    line('stool-spoke',[(-.45,.30,.13),p],.022,ink)
    cylinder('stool-castor',p,.048,.04,ink,'X')
# Secondary trolley creates a useful foreground silhouette.
for x in [1.95,2.55]:
    for y in [-.15,.53]:
        box('cart-upright',(x,y,.46),(.035,.035,.77),ink)
        cylinder('cart-wheel',(x,y,.07),.055,.04,ink,'X')
for z in [.20,.50,.84]: box('cart-tray',(2.25,.19,z),(.69,.77,.035),teal)
current=props
bin('AWAITING TEST',2.25,.19,.86,red,w=.58,d=.59,h=.17)
box('service-manual',(2.25,.19,.545),(.39,.44,.055),paper)
text('manual-title','SERVICE NOTES',(2.25,.19,.578),.044,ink,(0,0,0))
current=shell
box('noticeboard',(-2.965,.20,1.65),(.04,.86,.65),wood)
for y,body in [(-.03,'REPAIR QUEUE'),(.36,'CHECK / TEST')]:
    box('pinned-job-sheet',(-2.937,y,1.65),(.008,.32,.44),paper,.001)
    text('job-sheet-title',body,(-2.930,y,1.78),.025,ink,(math.pi/2,0,math.pi/2))

current=stage
def area(name, loc, target, power, color, size):
    data=bpy.data.lights.new(name,'AREA'); data.energy=power; data.shape='DISK'; data.size=size; data.color=color
    obj=bpy.data.objects.new(name,data); current.objects.link(obj); obj.location=loc; aim(obj,target)
    return obj
area('Large soft daylight',(1,-3.8,6),(0,1,0),1150,(.79,.87,1),5)
area('Warm shop overhead',(-1,.3,4.1),(0,1,.3),850,(1,.83,.64),4)
area('Workbench task lighting',(0,1.85,2.035),(0,1.7,.9),85,(1,.91,.74),2.3)
world=bpy.data.worlds.new('Workshop world'); scene.world=world; world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.19,.22,.26,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.4
def camera(name,loc,target,ortho=None):
    data=bpy.data.cameras.new(name); obj=bpy.data.objects.new(name,data); current.objects.link(obj)
    obj.location=loc; aim(obj,target)
    if ortho: data.type='ORTHO'; data.ortho_scale=ortho
    else: data.lens=48
    return obj
overview=camera('Overview - cutaway',(7,-9,7),(0,.35,1.05),8.5)
closeup=camera('Workbench detail',(.6,-1.5,2.55),(-.50,1.8,1.42))
scene.camera=overview
scene.render.engine='CYCLES'; scene.cycles.samples=32; scene.cycles.use_denoising=True
scene.render.resolution_x=1600; scene.render.resolution_y=1200; scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
for screen_data in bpy.data.screens:
    for a in screen_data.areas:
        if a.type=='VIEW_3D':
            a.spaces.active.region_3d.view_perspective='CAMERA'
            a.spaces.active.clip_end=100
scene['asset_notes']='Meters, Blender Z-up. Toggle collection 02 to close room. Native editable labels/curves. Visual props only.'
scene['reference']='https://badar.tech/2023/04/30/electronics-lab-bench-setup-guide/'
PREVIEW.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(DEST))
for cam,name in [(overview,'overview'),(closeup,'workbench-detail')]:
    scene.camera=cam; scene.render.filepath=str(PREVIEW/(name+'.png'))
    bpy.ops.render.render(write_still=True)
print('SHOP_INTERIOR_READY:',DEST)
