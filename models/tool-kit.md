# Rounded tool kit

`tool-kit.blend` contains the air blower, Dev blower, spudger, IPA bottle/pad,
paste syringe, fan oiler, loupe, thermal camera and close-up scraper/wipe shapes.
It shares the screwdriver's rounded edges, charcoal grips and ivory accents,
with individual body colours. The screwdriver keeps its separate source.

Edit and save the Blender source, then run from the repository root:

```powershell
$blenderExe = 'C:\path\to\blender.exe'
$godotExe = 'C:\path\to\Godot_console.exe'
& $blenderExe --background models/tool-kit.blend --python scripts/blender/export_tool_kit.py
& $godotExe --headless --path godot --editor --import --quit
& $godotExe --headless --path godot --script res://tools/import_tool_kit.gd
& $godotExe --headless --path godot --script res://tests/tool_art_flow.gd
```

Export writes only the tools to `godot/assets/tool-kit.glb`, temporarily restoring
each root to the origin so the preview layout is not imported into play. It restores
the source poses afterwards and does not save over the source. Baking bundles mesh
resources into the individual native scenes instanced by `scenes/toolbox.tscn`.
Keep the source, GLB/import settings and baked scenes together.

Preserve root names and the `ToolName__PartName` object names. Part centres and the
blower's +X working direction are retained. Original tool envelopes are frozen in
`godot/tests/fixtures/tool-proportions.json`; do not regenerate them from the new art.
The thermal camera keeps its native `Display` QuadMesh, screen UVs and brand label
when baked. `WorkTools` supplies rounded geometry at the existing contact positions
for the pressed spudger and soiled wipe in `bench_closeup.gd`.

`build_tool_kit.py` is the initial conversion, reading geometry captured from the
earlier native scenes. It refuses an existing source. Use the saved source/export
workflow for subsequent edits. F12 renders the style sheet with all eight tools at
the same scale; the initial preview is `artifacts/tool-kit-style.png`.

The normal GPU/shop `sync_assets.py` does not overwrite this tool set.
