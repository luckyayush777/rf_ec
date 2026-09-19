"""Export the edited GPU hierarchy, without rebuilding it or exporting the stage.

Run through `npm run model:export`, or import export_gpu from build_gpu.py.
The native file keeps curves/modifiers; only temporary copies are converted.
"""
import argparse
import json
from pathlib import Path
import sys

import bpy

ROOT = Path(__file__).resolve().parents[2]


def hierarchy(root):
    return [root, *root.children_recursive]


def web_vector(vector):
    # Blender Z-up -> glTF / Three.js Y-up. Custom properties aren't auto-converted.
    return [float(vector[0]), float(vector[2]), -float(vector[1])]


def export_gpu(filepath):
    root = bpy.context.scene.objects.get('gpu')
    if root is None:
        raise RuntimeError('The active scene must contain the named root object "gpu".')
    original_objects = hierarchy(root)
    selected = list(bpy.context.selected_objects)
    active = bpy.context.view_layer.objects.active
    duplicates = {}
    temporary_meshes = []
    temporary = bpy.data.collections.new('__gpu_export__')
    bpy.context.scene.collection.children.link(temporary)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    try:
        for obj in original_objects:
            if obj.type not in {'EMPTY', 'MESH', 'CURVE'}:
                raise RuntimeError(f'Unsupported GPU object: {obj.name} ({obj.type})')
            copy = obj.copy() if obj.type != 'CURVE' else None
            if obj.type in {'MESH', 'CURVE'}:
                # Evaluate bevels, arrays, and editable cable curves into export-only meshes.
                mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph), depsgraph=depsgraph)
                temporary_meshes.append(mesh)
                if obj.type == 'CURVE':
                    copy = bpy.data.objects.new(obj.name + '-export', mesh)
                    copy.matrix_world = obj.matrix_world.copy()
                    for key in obj.keys():
                        copy[key] = obj[key]
                else:
                    copy.data = mesh
                    copy.modifiers.clear()
            temporary.objects.link(copy)
            duplicates[obj] = copy

        for obj, copy in duplicates.items():
            copy.parent = duplicates.get(obj.parent)
            copy.matrix_parent_inverse = obj.matrix_parent_inverse.copy()
            copy.matrix_basis = obj.matrix_basis.copy()
            if 'part_role' in obj:
                part = {
                    'role': obj['part_role'],
                    'assembledPosition': web_vector(obj.location),
                }
                if 'removal_direction' in obj:
                    part['removalDirection'] = web_vector(obj['removal_direction'])
                if 'requires_json' in obj:
                    part['requires'] = json.loads(obj['requires_json'])
                if 'attachment' in obj:
                    part['attachment'] = obj['attachment']
                copy['bench_part'] = json.dumps(part)

        # Give copies the canonical names for export, then restore originals in finally.
        original_names = {obj: obj.name for obj in original_objects}
        for obj in original_objects:
            obj.name = '__source__' + original_names[obj]
        for obj, copy in duplicates.items():
            copy.name = original_names[obj]
        bpy.ops.object.select_all(action='DESELECT')
        for copy in duplicates.values():
            copy.hide_set(False)
            copy.select_set(True)
        bpy.context.view_layer.objects.active = duplicates[root]
        Path(filepath).parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.export_scene.gltf(
            filepath=str(filepath), export_format='GLB', use_selection=True,
            export_yup=True, export_extras=True, export_apply=False,
            export_animations=False, export_cameras=False, export_lights=False,
        )
    finally:
        for copy in duplicates.values():
            bpy.data.objects.remove(copy, do_unlink=True)
        for mesh in temporary_meshes:
            if mesh.users == 0:
                bpy.data.meshes.remove(mesh)
        bpy.data.collections.remove(temporary)
        if 'original_names' in locals():
            for obj, name in original_names.items():
                obj.name = name
        bpy.ops.object.select_all(action='DESELECT')
        for obj in selected:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = active
    print(f'GPU_EXPORTED: {filepath}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'src/assets/gpu.glb')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    export_gpu(args.output.resolve())
