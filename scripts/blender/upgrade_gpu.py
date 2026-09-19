"""Add fan screw supports to the saved model, preserving its editable geometry.
Run Blender in background with models/gpu.blend and this script. A backup is kept.
"""
from pathlib import Path
import json
import shutil
import sys
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_gpu as model
from export_gpu import export_gpu

source = Path(bpy.data.filepath)
backup = source.parent / (source.stem + '-before-service.blend')
if not backup.exists():
    shutil.copy2(source, backup)
objects = bpy.context.scene.objects
cooler = objects['cooler-assembly']
model.MODEL = cooler.users_collection[0]
model.MATERIALS.update({name: bpy.data.materials[name] for name in model.COLORS})
for i in range(1, 5):
    name = f'fan-standoff-{i}'
    if name not in objects:
        screw = objects[f'fan-screw-{i}']
        model.make_fan_support(name, screw.location.x, screw.location.y, cooler)
objects['fan-assembly']['requires_json'] = json.dumps(['fan-plug'] + [f'fan-screw-{i}' for i in range(1, 5)])
objects['gpu']['service_order'] = 'Unplug fan → remove four fan screws → lift fan; optionally remove rear cooler screws → lift cooler. Refit in reverse order.'
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(source))
export_gpu(model.ROOT / 'src/assets/gpu.glb')
print('GPU_UPDATED: four bored fan mounting posts; original source backed up at', backup)
