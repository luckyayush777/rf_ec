# Editable GPU asset

`gpu.blend` is the editable source; `gpu.glb` is the exported GPU hierarchy. This is a fictional card with illustrative authoring units. Godot applies the gameplay scale.

## Edit and export

Open `models/gpu.blend`, edit and save it, then run from the repository root:

```powershell
$blenderExe = 'C:\path\to\blender.exe'
& $blenderExe --background models/gpu.blend --python scripts/blender/export_gpu.py
python godot/tools/sync_assets.py
```

Export evaluates temporary copies, preserving source modifiers and editable cable curves. It excludes the preview stage and does not rebuild or save over the Blender source. Godot reimports the copied GLB. Blender 4.5 or newer is required for authoring; Python synchronization uses only the standard library.

To generate an initial model in a separate background process:

```powershell
& $blenderExe --background --python scripts/blender/build_gpu.py
```

Generation refuses to overwrite an existing source. Only add `-- --force` when intentionally discarding saved manual edits. For an alternate draft, pass `-- --blend models/gpu-draft.blend --glb artifacts/gpu-draft.glb`. The exporter accepts `-- --output artifacts/gpu-draft.glb` for an alternate output.

## What to edit

| Change | Blender object / control |
|---|---|
| Board shape | `board-substrate`, `board-top`, `board-bottom` |
| Fin spacing or count | `heatsink-fins` → **Fin count and spacing** Array modifier |
| Fan blade shape | Edit any `fan-blade-*`; blades share mesh data |
| Spin the fan | Rotate `fan-rotor` around local **Z** |
| Cable routing | `fan-positive-wire` / `fan-ground-wire` → Edit Mode → move Bézier points |
| Plastic / metal appearance | Named materials under Material Properties |
| Move complete cooler | Select the `cooler-assembly` empty |
| Move fan and cable together | Select the `fan-assembly` empty |
| Fan screw attachment points | `fan-standoff-1` through `fan-standoff-4`, bored posts parented to the cooler |
| Preview render | Numpad 0 for camera, F12 to render |


## Service metadata

Keep `gpu` as the root and retain assembly, fastener and connector names. Parent new GPU geometry beneath that root. Empties carry `part_role`, `removal_direction`, and `requires_json`; the exporter writes `bench_part` metadata and converts Blender Z-up coordinates to glTF Y-up. The Python sync tool extracts that metadata into `godot/assets/gpu-parts.json`.

Godot's `asset_contract.gd` binds the hierarchy; `service_rules.gd` checks prerequisites and refit order. Run the Godot smoke test after metadata changes. Refit restores original parents and local transforms.

The cable moves with the fan. Unplug it, remove the four top fan screws, then lift the fan. Remove the four rear cooler screws to lift the cooler. Refit the cooler before the fan when both are detached.

`upgrade_gpu.py`, `detail_gpu.py`, and `add_worn_pads.py` are targeted source upgrades that save edits and export `models/gpu.glb`; inspect them before running. Worn-pad geometry is retained for future scraping gameplay. `gpu-before-service.blend` is a historical source backup.
