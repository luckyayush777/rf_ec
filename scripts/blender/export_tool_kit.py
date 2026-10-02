"""Export saved tools without their preview arrangement, floor or lights."""
from pathlib import Path
import bpy
from mathutils import Matrix

ROOT=Path(__file__).resolve().parents[2]
names=['AirBlower','DevBlower','Spudger','IpaWipe','PasteSyringe','FanOiler','Loupe','ThermalCamera','WorkTools']
roots=[bpy.data.objects[name] for name in names]
poses={root:root.matrix_world.copy() for root in roots}
hidden={obj:obj.hide_render for root in roots for obj in [root,*root.children_recursive]}
try:
    bpy.ops.object.select_all(action='DESELECT')
    for root in roots:
        root.matrix_world=Matrix.Identity(4)
        for obj in [root,*root.children_recursive]:
            obj.hide_render=False
            obj.select_set(True)
    bpy.context.view_layer.objects.active=roots[0]
    bpy.ops.export_scene.gltf(filepath=str(ROOT/'godot/assets/tool-kit.glb'),use_selection=True,export_apply=True,export_yup=True)
finally:
    for root,pose in poses.items(): root.matrix_world=pose
    for obj,hide in hidden.items(): obj.hide_render=hide
