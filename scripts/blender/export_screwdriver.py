"""Export the saved tool only, keeping editable source and preview stage intact."""
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
tool = bpy.data.objects.get('Screwdriver')
if tool is None:
    raise RuntimeError('The saved scene has no Screwdriver root')
bpy.ops.object.select_all(action='DESELECT')
for obj in [tool, *tool.children_recursive]:
    obj.select_set(True)
bpy.context.view_layer.objects.active = tool
bpy.ops.export_scene.gltf(filepath=str(ROOT / 'godot/assets/screwdriver.glb'),
                          use_selection=True, export_apply=True, export_yup=True)
