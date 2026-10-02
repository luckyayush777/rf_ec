# Rounded screwdriver study

The tool bag instances `godot/scenes/screwdriver.tscn`. The editable source is
`models/screwdriver.blend`, with bevel modifiers and a separate render stage.
The study preserves the earlier tool's 2.4 overall length, 0.88 grip length,
1.28 shaft length and grip envelope. The native root retains direct
`Grip`, `Collar`, `Shaft` and `Tip` paths for existing picking/tool controls.

The shape language is a gently lobed orange barrel, broad charcoal rubber inserts,
an ivory end cap, soft collar edges and a tapered cruciform Phillips bit.
The remaining tools now share this style; see [tool-kit authoring](tool-kit.md).

Edit and save the Blender source, then export and bake from the repository root:

```powershell
$blenderExe = 'C:\path\to\blender.exe'
$godotExe = 'C:\path\to\Godot_console.exe'
& $blenderExe --background models/screwdriver.blend --python scripts/blender/export_screwdriver.py
& $godotExe --headless --path godot --editor --import --quit
& $godotExe --headless --path godot --script res://tools/import_screwdriver.gd
& $godotExe --headless --path godot --script res://tests/scale_toolbox_flow.gd
```

Export writes only the tool to `godot/assets/screwdriver.glb`; it does not save over
the Blender source or export the preview floor/lights. Baking bundles the imported
geometry into a native scene, so the live tool does not refer to editor caches.
Keep the source, intermediate GLB/import settings and native scene together.
`sync_assets.py` covers the shared GPU/shop models and does not overwrite this tool.

`scripts/blender/build_screwdriver.py` creates the initial study and refuses an
existing source. For later edits, use the saved source and export workflow above.
F12 in Blender renders the saved style view; the initial PNG is
`artifacts/screwdriver-style.png`. A rendered `scale_toolbox_flow.gd -- --capture`
also saves the bag and equipped tool views under `godot/build/`.
