"""Add removable worn thermal-pad remnants to the editable GPU source."""
from pathlib import Path
import sys
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_gpu as model
from export_gpu import export_gpu

root = bpy.data.objects['gpu']
detail = bpy.data.objects['pcb-detail']
model.MODEL = root.users_collection[0]
model.MATERIALS.update({name: bpy.data.materials[name] for name in model.COLORS})
if 'Worn thermal pad' not in bpy.data.materials:
    worn = bpy.data.materials.new('Worn thermal pad')
    worn.diffuse_color = (.28, .25, .19, 1)
    worn.use_nodes = True
    worn.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (.28, .25, .19, 1)
    worn.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = .93
else:
    worn = bpy.data.materials['Worn thermal pad']
model.MATERIALS['Worn thermal pad'] = worn

# Each chip keeps three separate pieces, so the browser can scrape them away.
for i, (x, y) in enumerate([(-1.58, .55), (-1.58, -.55), (.68, .55), (.68, -.55)]):
    for j, (dx, dy, width, depth) in enumerate([
        (-.12, -.12, .20, .25), (.105, -.09, .18, .22), (-.015, .17, .30, .18),
    ]):
        name = f'memory-residue-{i}-{j}'
        if name not in bpy.data.objects:
            model.box(name, (width, depth, .024), (x + dx, y + dy, .146),
                      'Worn thermal pad', detail, bevel=.006)

bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(model.ROOT / 'models/gpu.blend'))
export_gpu(model.ROOT / 'src/assets/gpu.glb')
