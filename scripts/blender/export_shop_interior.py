"""Export the saved shop interior without changing its editable Blender source.
blender --background models/shop-interior.blend --python scripts/blender/export_shop_interior.py
"""
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
if '01 Room - visible shell' not in bpy.data.collections:
    raise RuntimeError('Open models/shop-interior.blend before exporting.')
# Evaluate editable text, curves and bevels only into temporary export objects.
temporary = bpy.data.collections.new('__shop_export__')
bpy.context.scene.collection.children.link(temporary)
original_names = {}
meshes = []
hidden = {}
try:
    root = bpy.data.objects.new('shop-interior', None)
    temporary.objects.link(root)
    for col in list(bpy.context.scene.collection.children):
        if not col.name[:2] in ['01','02','03','04','05']: continue
        hidden[col] = col.hide_viewport
        col.hide_viewport = False
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for col in hidden:
        group = bpy.data.objects.new(col.name[3:], None)
        temporary.objects.link(group)
        group.parent = root
        group['cutaway_shell'] = col.name.startswith('02')
        for obj in list(col.objects):
            if obj.type not in {'MESH','CURVE','FONT'}: continue
            mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph),depsgraph=depsgraph)
            meshes.append(mesh)
            name = obj.name
            original_names[obj] = name
            obj.name = '__source__'+name
            copy = bpy.data.objects.new(name,mesh)
            temporary.objects.link(copy)
            copy.parent=group
            copy.matrix_world=obj.matrix_world.copy()
    bpy.ops.object.select_all(action='DESELECT')
    for obj in temporary.objects: obj.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=str(ROOT/'models/shop-interior.glb'),
        export_format='GLB',use_selection=True,export_yup=True,export_extras=True,
        export_cameras=False,export_lights=False,export_animations=False)
finally:
    for obj in list(temporary.objects): bpy.data.objects.remove(obj,do_unlink=True)
    bpy.data.collections.remove(temporary)
    for mesh in meshes:
        if mesh.users==0: bpy.data.meshes.remove(mesh)
    for obj,name in original_names.items(): obj.name=name
    for col,value in hidden.items(): col.hide_viewport=value
print('SHOP_EXPORTED: models/shop-interior.glb')
