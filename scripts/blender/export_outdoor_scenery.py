"""Export the saved outdoor scenery without changing its editable Blender source.
blender --background models/outdoor-scenery.blend --python scripts/blender/export_outdoor_scenery.py
Then run `python godot/tools/sync_assets.py` to copy the GLB into Godot.
"""
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
if 'Outdoor scenery' not in bpy.data.collections:
    raise RuntimeError('Open models/outdoor-scenery.blend before exporting.')
bpy.ops.object.select_all(action='DESELECT')
for obj in bpy.data.collections['Outdoor scenery'].all_objects:
    if obj.type == 'MESH':
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
# Vertex colours carry all the painting; Godot replaces the placeholder material by object name.
bpy.ops.export_scene.gltf(filepath=str(ROOT / 'models/outdoor-scenery.glb'), export_format='GLB',
    use_selection=True, export_yup=True, export_normals=True, export_vertex_color='ACTIVE',
    export_cameras=False, export_lights=False, export_animations=False, export_extras=False)
print('OUTDOOR_EXPORTED: models/outdoor-scenery.glb')
