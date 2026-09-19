# Editable GPU asset

The model has a native Blender source, separate assemblies, editable cable curves, named materials, and a browser export. This is a simplified fictional card, not an accurate GT 710 or a manufacturing model.

## Run the browser scene

```sh
cd /Users/ayushkumar/ayush.dev/repair_shop
npm install
npm run dev -- --port 5173
```

Open **http://127.0.0.1:5173/** and keep the terminal running. Ctrl+C stops it. Blender is not required to view the included GPU asset. Click the toolbox to open it, then click the screwdriver to grab it. Click a clear area of the desk to place it, or press Esc to return it. Drag to orbit and scroll to zoom.

For a production preview:

```sh
npm run build
npm run preview -- --port 4173
```

Open **http://127.0.0.1:4173/**. Use the actual URL Vite prints if a port is already occupied.

## Edit and re-export the existing model

After installing Blender in Applications on macOS:

```sh
cd /Users/ayushkumar/ayush.dev/repair_shop
open -a Blender models/gpu.blend
```

Save your changes in Blender, then run this in another terminal while the browser server stays running:

```sh
cd /Users/ayushkumar/ayush.dev/repair_shop
npm run model:export
```

Refresh the browser. If using the temporary Blender copy from the initial setup and its disk image is still mounted, select it explicitly instead:

```sh
BLENDER_BIN=/private/tmp/bench-blender-mount/Blender.app/Contents/MacOS/Blender npm run model:export
```

The browser desk, lamp, and toolbox are authored in `src/workbench.ts`; they are separate from the GPU asset and its Blender preview stage.

In the browser, click the GPU or **Inspect GPU** to lift it, drag to rotate it, and press Esc to set it down. Click the cable plug to unplug/reconnect it. Pick up the screwdriver and click the four fan screws to remove them into the labeled tray. Return the tool, lift the fan, then click a clear area of the desk to place it. **Refit fan**, followed by clicking the tray screws with the screwdriver, reverses the process. The cable stays with the fan and can reconnect once the assemblies are seated. Yellow halos identify hovered parts. These interactions do not modify the saved Blender source.

## First generation

Install [Blender 4.5 LTS or newer](https://www.blender.org/download/). The runner finds Blender on PATH or at `/Applications/Blender.app/Contents/MacOS/Blender`. For a different location:

```sh
export BLENDER_BIN="/path/to/blender"
```

From the project directory:

```sh
npm run model:build
```

This produces:

- `models/gpu.blend` — editable source, with a table, preview camera, and lights.
- `src/assets/gpu.glb` — GPU hierarchy only, loaded automatically by the browser viewer.

Generation refuses to overwrite an existing `.blend` file. To intentionally replace the source and discard manual edits, use `npm run model:build -- --force`.

## Normal iteration

1. Open `models/gpu.blend` in Blender.
2. Edit the model and save it.
3. Run `npm run model:export`.
4. Refresh the browser viewer. Re-run `npm run build` when preparing a production build.

**Export does not rebuild or save over your Blender file.** It evaluates temporary copies of the model, so the source retains its modifiers and editable curves. Save your Blender edits before exporting. The table, camera, and lights are excluded from the GLB.

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

The board sits on the table with the cooler facing upward. Blender uses Z-up; the exporter converts to the browser's Y-up coordinates. Units are illustrative viewer units, not meters or manufacturing dimensions.

Keep `gpu` as the root name and keep the assembly / fastener names stable. Newly added model objects must be parented beneath `gpu` to be exported. The stage belongs in its separate collection. Empties carry `part_role`, `removal_direction`, and dependency properties; the exporter converts these into browser metadata. The browser repair controller implements the servicing constraints and restores the original parent and transform when refitting a part.

The cable is parented to the fan, and its plug must be unplugged before moving either assembly. The browser animates the plug and bends the nearby wire vertices during disconnection; the native curves remain editable. Fan removal order: fan plug → four top fan screws → fan assembly → desk. The cooler can separately be removed after its four rear screws are out. Refit the cooler before the fan when both have been detached.

The second model pass adds four bored metal posts from the heatsink base into the fan mounting sleeves. The fan screw shafts enter these posts. Both the procedural fallback and Blender generator include them. `scripts/blender/upgrade_gpu.py` applies this update to an existing source without regenerating its meshes or curves; the original model is preserved as `models/gpu-before-service.blend`.

## Optional commands

```sh
# Generate a different draft without overwriting the main source or browser asset.
npm run model:build -- --blend models/gpu-draft.blend --glb artifacts/gpu-draft.glb

# Export an edited alternate source to the browser asset.
npm run model:export -- --blend models/gpu-draft.blend

# Generate a preview image during the initial build.
npm run model:build -- --render artifacts/blender-preview.png
```

Generation parameters and the starting material palette are at the top of `scripts/blender/build_gpu.py`. Regular artistic edits should happen in the `.blend` file; the build script is the reproducible starting point.

Implementation uses Blender's [background Python execution](https://docs.blender.org/manual/en/latest/advanced/command_line/arguments.html) and [glTF exporter](https://docs.blender.org/api/current/bpy.ops.export_scene.html).
