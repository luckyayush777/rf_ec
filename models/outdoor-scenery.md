# Outdoor scenery authoring

`models/outdoor-scenery.blend` is the view out of the shop window: a cozy alpine valley.
Godot loads its export, `godot/assets/outdoor-scenery.glb`, in `godot/scripts/outdoor_scenery.gd`.

## Contents, near to far

| Object | What it is |
| --- | --- |
| `Terrain` | One polar heightfield (433k vertices) centred on the window: the flat lawn yard, the flower meadow falling to the lake, the far-shore slope with the village terraces, forested hills and the snow-capped range. Colours (lawn, meadow, forest floor, alpine turf, rock, snow, sand, dirt path) are painted into the `Col` vertex colour attribute. |
| `Lake` | Flat water surface at `WATER_Y`; Godot replaces its material with `shaders/water.gdshader`. |
| `Forest` | About 10,000 low-poly pines scattered on the hills and lower mountain slopes, larger with distance so they read as texture. |
| `Foliage`, `YardBark` | Soft clump-canopy pines and round broadleaf trees framing the window, shrubs and meadow trees. Foliage normals lean toward each crown, so every tree shades as one rounded mass. |
| `Flowers` | Wildflower patches on the lawn edges and the meadow. |
| `YardStones`, `Fence` | Stepping stones, boulders and the rustic post-and-rail fence with its gate. |
| `VillageWalls`, `VillageRoofs`, `WindowLights`, `Pier` | The lakeside village: gabled houses, church and steeple, farmhouses, a pier and rowboats. `WindowLights` are separate quads that Godot turns from dark glass by day to warm lamplight at night. |

The `Preview (not exported)` collection holds a `WindowView` camera at the room's view of the window and a sun lamp.

## Coordinates

Everything is authored in Godot world units (1 unit = 0.2 m). Godot +X (out of the window) is Blender +X, Godot +Y (up) is Blender +Z, and Godot +Z is Blender -Y. The window wall is at x = 34; the yard runs to the fence at x = 77. Keep every vertex within `DOME_RADIUS` (600) of `DOME_CENTRE` (34, 0, -7); `tests/outside_flow.gd` checks this, the lawn's flatness, terrain orientation (no folds) and the presence of snow.

Godot assigns materials by object name (`LOOKS` in `outdoor_scenery.gd`). Keep the object names, or add the new name there. The Blender material only displays the vertex colours.

## Edit and export

Edit the saved file directly in Blender (move houses, repaint vertex colours, sculpt the terrain), then export and sync:

```powershell
$blenderExe = 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'
& $blenderExe --background models/outdoor-scenery.blend --python scripts/blender/export_outdoor_scenery.py
python godot/tools/sync_assets.py
python godot/tools/check.py --suite outside --import --capture
```

`scripts/blender/build_outdoor_scenery.py` regenerates the whole file from its layout constants (`LAKE`, `VILLAGE`, `PEAKS`, `PATH`, `TREE_LINE`, `SNOW_LINE`, palette in `terrain_colour`). It refuses to overwrite the existing file unless you pass `-- --force`, which discards manual edits:

```powershell
& $blenderExe --background --factory-startup --python scripts/blender/build_outdoor_scenery.py -- --force
```

The build takes about a minute. The Godot import keeps full-precision vertices (`force_disable_compression`) and skips LODs, tangents and shadow meshes for this asset; see `godot/assets/outdoor-scenery.glb.import`.
