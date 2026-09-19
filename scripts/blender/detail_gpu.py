"""Add an editable PCB and connector detail pass to the existing GPU source.

Run Blender in background with models/gpu.blend and this script. Existing
assemblies, fasteners and cable curves retain their transforms and metadata.
"""
import math
from pathlib import Path
import sys
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_gpu as model
from export_gpu import export_gpu

root = bpy.data.objects['gpu']
board = bpy.data.objects['board']
model.MODEL = root.users_collection[0]
model.MATERIALS.update({name: bpy.data.materials[name] for name in model.COLORS})

def label(name, text, position, size, parent, rear=False):
    curve = bpy.data.curves.new(name, 'FONT')
    curve.body = text
    curve.size = size
    curve.extrude = .0002
    obj = bpy.data.objects.new(name, curve)
    model.place(obj, name, parent, position)
    if rear:
        obj.rotation_euler.x = math.pi
    curve.materials.append(model.MATERIALS['Connector plastic'])
    return obj

if not bpy.data.objects.get('pcb-detail'):
    detail = model.group('pcb-detail', board)
    # A die and memory packages become visible when servicing the cooler.
    model.box('gpu-package', (1.12, 1.0, .065), (-.43, 0, .102), 'Fan plastic', detail)
    model.box('gpu-die', (.60, .55, .022), (-.43, 0, .148), 'Steel', detail, bevel=.005)
    for i, (x, y) in enumerate([(-1.58, .55), (-1.58, -.55), (.68, .55), (.68, -.55)]):
        model.box(f'memory-package-{i}', (.48, .68, .065), (x, y, .101), 'Fan plastic', detail)
    for i in range(3):
        x, y = 2.20, -.77 + i * .64
        model.cylinder(f'capacitor-{i}', .125, .29, (x, y, .21), 'Aluminum', detail, vertices=20)
        model.box(f'capacitor-score-{i}', (.14, .013, .005), (x, y, .359), 'Recess', detail, bevel=0)
        model.box(f'power-chip-{i}', (.22, .20, .09), (2.72, .47+i*.27, .12), 'Fan plastic', detail)
    # Rear component population, solder pads and readable silkscreen.
    for side in (-1, 1):
        for i in range(20):
            x = -2.6 + i * .27
            y = side * 1.14
            model.box(f'smd-{side}-{i}', (.10, .055, .025), (x, y, -.08), 'Fan plastic', detail, bevel=.002)
            for offset in (-.057, .057):
                model.box(f'solder-{side}-{i}-{offset}', (.024, .062, .016), (x+offset, y, -.077), 'Aluminum', detail, bevel=.002)
    for i in range(6):
        x = -2.25 + i * .86
        model.box(f'rear-memory-{i}', (.48, .60, .045), (x, .48, -.09), 'Fan plastic', detail)
        for pin in range(6):
            for side in (-1, 1):
                model.box(f'ram-pad-{i}-{pin}-{side}', (.04, .075, .012), (x-.19+pin*.075, .48+side*.33, -.071), 'Aluminum', detail, bevel=.001)
    for i in range(26):
        x = -2.65 + i * .20
        # Thin copper-green routing strips and vias, not additional heavy meshes.
        model.box(f'pcb-trace-{i}', (.009, .36+(i%4)*.08, .002), (x, -.50, -.067), 'Board edge', detail, bevel=0)
        model.cylinder(f'pcb-via-{i}', .021, .005, (x, -.77, -.07), 'Gold contacts', detail, vertices=8)
    label('pcb-rear-title', 'BENCH  /  710', (-1.25, -.08, -.069), .19, detail, True)
    label('pcb-rear-subtitle', 'REV 01     2GB DDR3     PCI EXPRESS', (-1.25, -.32, -.069), .075, detail, True)
    label('pcb-front-marking', 'CLEAN / CARE', (1.80, 1.20, .069), .075, detail)
    label('pcb-rear-serial', 'SN  0710  2408  0031', (1.15, -.70, -.069), .065, detail, True)

    # Two recognizable connector faces replace the original placeholder port.
    bracket = bpy.data.objects['mounting-bracket']
    for child in list(bracket.children):
        if child.name not in ('bracket-top-flange', 'bracket-foot'):
            bpy.data.objects.remove(child, do_unlink=True)
    for y in (-1.375, 1.375):
        model.box('bracket-side', (.055, .065, 1.24), (0, y, 0), 'Steel', bracket)
    for z in (-.48, .48):
        model.box('bracket-rail', (.055, 2.72, .26), (0, 0, z), 'Steel', bracket)
    model.box('bracket-divider', (.055, .16, .75), (0, .35, 0), 'Steel', bracket)
    for name, y, width, height, mat in [('dvi', -.54, 1.35, .46, 'Connector plastic'), ('hdmi', .86, .63, .28, 'Recess')]:
        model.box(name+'-shell', (.42, width+.10, height+.10), (.16, y, -.04), 'Steel', bracket)
        model.box(name+'-face', (.016, width, height), (-.061, y, -.04), mat, bracket)
        if name == 'dvi':
            for row in range(3):
                for col in range(8):
                    model.box(f'dvi-pin-{row}-{col}', (.018, .065, .065), (-.073, y-.47+col*.13, -.17+row*.13), 'Recess', bracket, bevel=.008)
        else:
            model.box('hdmi-tongue', (.025, .46, .045), (-.075, y, -.04), 'Gold contacts', bracket)
    fan = bpy.data.objects['fan-assembly']
    label('fan-brand-label', '710', (-.15, -.04, .158), .15, fan)

# Keep the populated edge clear of the serviceable fan socket and cable route.
for i in range(3):
    bpy.data.objects[f'capacitor-{i}'].location.x = 2.20
    bpy.data.objects[f'capacitor-score-{i}'].location.x = 2.20
    bpy.data.objects[f'power-chip-{i}'].location.x = 2.72
    bpy.data.objects[f'power-chip-{i}'].location.y = .47+i*.27
for obj in root.children_recursive:
    if obj.type == 'FONT':
        obj.data.resolution_u = 2
        obj.data.extrude = 0

bpy.ops.wm.save_as_mainfile(filepath=str(model.ROOT / 'models/gpu.blend'))
export_gpu(model.ROOT / 'src/assets/gpu.glb')
