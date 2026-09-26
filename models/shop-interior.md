# Workshop interior

Open `shop-interior.blend` in Blender. Godot instances this room through `godot/scenes/shop_interior.tscn` in the main
workbench scene. It surrounds the existing playable repair and testing desks.

The room is 6 x 4.8 meters with 3-meter walls. Blender uses Z-up; the GLB exporter
converts to Y-up. The Godot wrapper uses a uniform 5x prop scale and expands only the architectural
shell in X/Z to fit the existing gameplay units. `godot/scripts/shop_interior.gd`
places the background bench and aisle props and hides the cutaway shell. The same
layout runs in the editor via `@tool`; Blender source proportions remain intact.

## Contents and editing

- `01 Room - visible shell`: brick back wall, painted left wall, floor, store door,
  skirting, noticeboard and BENCH sign.
- `02 Room - hide for cutaway (front right ceiling)`: full-height right wall,
  front wall with a doorway, and ceiling. Hidden in viewport and renders for the
  overview; enable both collection visibility flags to close the room.
- `03 Workbench and storage`: worktop, drawers, shelf, tool board, ESD mat, stool
  and rolling trolley.
- `04 Oscilloscope and electronics`: oscilloscope with waveform, grid, knobs,
  connectors and probes; bench supply; soldering station; tools and loose PCB.
- `05 Labelled bins and hand tools`: labelled open bins, lidded organizers,
  solder spool and service manual. Label text remains editable FONT objects.
- `06 Cameras and lighting`: `Overview - cutaway` and `Workbench detail`
  cameras, with preview lighting. These are excluded from export.

All instruments and tools are visual props. The oscilloscope trace is static.
The front doorway is open; the visible left-wall door represents a store room.

## Export saved edits

Set `$blenderExe` to your installed executable, then run from the repository root:

```powershell
& $blenderExe --background models/shop-interior.blend --python-exit-code 1 --python scripts/blender/export_shop_interior.py
```

After exporting, run `node godot/tools/sync-assets.mjs` from the repository root
to copy the asset into Godot and update the source hash manifest.

This writes `models/shop-interior.glb` with the **entire room**, including hidden
cutaway walls. It evaluates bevels, curves and labels into temporary export meshes
without saving over the Blender source. Geometry is grouped beneath `shop-interior`;
the cutaway group has `cutaway_shell` metadata. Preview lighting is not baked.

For ordinary edits, save the `.blend` and export it. The initial generator is:

```powershell
& $blenderExe --background --factory-startup --python-exit-code 1 --python scripts/blender/build_shop_interior.py
```

It refuses to overwrite an existing source. Passing `-- --force` intentionally
rebuilds the model and discards manual edits. Initial generation also writes two
1600 x 1200 previews to ignored `artifacts/shop-interior/`: `overview.png` and
`workbench-detail.png`. Use the named cameras and F12 to render later edits.

## Visual references

The layout draws on the instrument placement, labelled storage and clear working
area in [Badar Jahangir Kayani's electronics bench](https://badar.tech/2023/04/30/electronics-lab-bench-setup-guide/)
and the electronics workbench at [Leigh Works](https://leigh.works/).
Geometry, materials, labels and waveform were authored for this project;
no reference photos or third-party models are embedded in the asset.

Validated with Blender 5.2.2: saved source reopened for export, both rendered
views inspected, and exported GLB checked for room, scope, waveform and labels.
Godot rendered acceptance checks cover placement and the existing service flows.
Use **Both desks** to see the room. Props are scenery, with no service interactions
or player collision system.
