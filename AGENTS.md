# Codebase navigation for agents

Last map review: 2026-09-27. Paths are relative to the repository root.

## Start each run

1. Read this guide and check `git status --short` for existing work.
2. BENCH is a Godot/GDScript GPU repair game. Product work belongs in `godot/`; the browser application and Node/TypeScript toolchain have been removed.
3. Check the owning module, its callers and relevant tests before editing. Prefer changes in existing owners.
4. Preserve existing user changes. Do not commit or publish unless requested.
5. Update this guide when ownership, paths, commands or implemented features change. Keep detailed player instructions in `godot/README.md` and model workflows in `models/`.

## Entry points and scope

- `godot/project.godot` starts `godot/scenes/workbench.tscn`; `godot/scripts/workbench.gd` wires the controllers.
- `README.md` is the project entry point; `godot/README.md` covers controls, features and checks.
- `models/README.md`, `models/repair-shop.md`, and `models/shop-interior.md` cover Blender assets.
- Runtime progress is in memory; there is no backend or saved-game system.
- First-person walking, GPU inspection, toolbox selection, screwdriver service, assembly removal/refit, debug blower cleaning, test-board/monitor flow, fan audio, thermal investigation, the dried-paste heat fault and repasting (spudger scrape, IPA wipe, syringe application, pressure spread and lift-test imprint) are implemented. Regular blower, paste thickness/mounting pressure, pad scraping, replacement parts, job progression and electrical diagnosis are pending.

## Godot ownership map

All paths in this table are under `godot/`. Scene node names and controller references form a contract; inspect both when renaming nodes.

| File | Responsibility |
| --- | --- |
| `scenes/workbench.tscn` | Main composition, imported assets, camera, lights and controller nodes |
| `scenes/repair_desk.tscn`, `scenes/toolbox.tscn` | Editable native desk/holder/tray and tool roll/screwdriver/Dev blower/spudger/IPA wipe/paste syringe meshes |
| `scenes/test_monitor.tscn`, `scripts/test_monitor.gd`, `scripts/testing_station.gd` | Native LCD/power button, falling-block display, GPU core sensor readout, GPU-to-board transfer, signal cable, dust-driven rotor animation and test/fan audio |
| `scenes/shop_interior.tscn`, `scripts/shop_interior.gd` | Imported room wrapper, editor-visible unit conversion, cutaway shell and background prop layout; synced from `models/shop-interior.glb` |
| `scripts/workbench.gd` | Startup, input arbitration, controller wiring, desk alignment, tool-equipped pickup versus click-to-focus routing, obstacles, placement marker and holder jaws aligned to the current GPU centre |
| `scripts/bench_closeup.gd`, `scripts/tool_roll.gd`, `shaders/closeup_backdrop.gdshader` | Live enlarged metadata-selected GPU/part and tool-bag windows with blurred room backdrop and transparent object viewport, isolated mesh proxies, direct screw/tool picking, blower surface cleaning, paste-face framing and scrape/wipe/squeeze strokes, return-tool area, view rotation/zoom, `POCKETS` table of tool pockets and rolling animation |
| `scripts/workbench_tools.gd` | Table-driven exclusive state for `TOOLS` (screwdriver, Dev blower, thermal camera, spudger, IPA wipe, paste syringe), roll/tool animation, nozzle aim, placement and busy guards; `location`/`dev_location`/`thermal_location` remain as compatibility properties |
| `scripts/held_part_pose.gd` | Shared left-hand framing for carried GPU/fan/heatsink, preserving a clear central aim and physical scale; legacy fixtures keep centred inspection |
| `scripts/gpu_service.gd` | Cable deformation, screw progress and persistent seats, assembly lift/place/store/refit, tray transfer, exact refit, debug full disassembly and screwdriver audio |
| `scripts/first_person.gd`, `scripts/gpu_inspection.gd` | Walking/collision, capture/look/reach and held-card inspection; `orbit_camera.gd` remains a legacy acceptance-fixture base only |
| `scripts/gpu_thermal.gd`, `scripts/thermal_camera.gd`, `shaders/thermal_surface.gdshader`, `scenes/thermal_camera.tscn` | Dust and die-paste heat model with core throttle limit, labelled VRAM packages, handheld camera, depth-tested low-resolution surface view and emissivity approximation |
| `scripts/gpu_paste.gd`, `shaders/paste_layer.gdshader` | Runtime `paste-die`/`paste-heatsink` grid layers (crust, film, fresh paste per cell), brushes, clean auto-finish, pressure spread on heatsink seat, lift imprint, contact quality and debug dry/fresh; created by `workbench.gd` |
| `scripts/interaction_picker.gd` | Cached triangle queries, surface normals, cleaning rays through fan-hub decoration, depth-tested screw/hole/plug targets and assembly action routing |
| `scripts/gpu_cleaning.gd`, `shaders/dust_overlay.gdshader`, `shaders/dust_highlight.gdshader` | Randomized part-owned masks, fan exposed-face restriction, imported normal correction, visible low dust, debug through-part highlight and 30-second timer, aimed cleaning, debug instant completion, audio |
| `scripts/hud.gd` | Native UI, tool selection state with keyboard focus, debug buttons and signals; `workbench.gd` owns menu capture and guarded tool switching |
| `scripts/asset_contract.gd` | Named-part binding, parent validation, original transforms, service definitions and actual-table footprint containment |
| `scripts/service_rules.gd` | Pure rule evaluator, including `check_surface` for contact-surface reach and tool choice; malformed graphs or surfaces fail closed |
| `tools/sync_assets.py` | Copy Blender GLBs from `models/` and generate `assets/gpu-parts.json` with part metadata and hashes |
| `tests/repaste_flow.gd` | Paste reach rules, paste-tool exclusivity, wipe-over-crust hint, scrape then wipe on die and heatsink base, squeeze bead, seat spread, lift imprint, dot/X/scant/flood coverage, spread timing, bare-die warning and rendered captures |
| `tests/staged_disassembly_flow.gd` | Full-to-partial-to-bare board mat placement with screwdriver retained, fan-held heatsink screw service, focus cable handling and loosened heatsink pickup |
| `tests/part_focus_flow.gd` | Fan/heatsink and metadata-defined assembly focus, tool-equipped inspection/flip, isolated cleaning, per-subject progress and tool switching |
| `tests/tool_inspection_flow.gd` | Tool-equipped E pickup/flip, backplate focus cleaning, return-tool region, forward clamp alignment and rendered before/after captures |
| `tests/placement_flow.gd` | Left-hand framing, rotation/scale, reachable placement marker, GPU/assembly landing, actual table-edge rejection and rendered captures |
| `tests/closeup_flow.gd` | Enlarged GPU GUI input, instant hole seating, pause/focus cancellation, exact refit, retained physical scale and front/rear captures |
| `tests/scale_toolbox_flow.gd` | Physical scale across inspection/rotation/test board/detachment; front toolbox access, keyboard focus, tool switching, close and rendered captures |
| `tests/first_person_flow.gd`, `tests/thermal_flow.gd` | First-person collision/capture/reach/pickup; thermal tool lifecycle, occlusion, internal dust cleaning under equal load, dried-paste core/heatsink gap and monitor readout, cooldown and rendered captures |
| `tests/smoke.gd`, `tests/service_flow.gd` | Rule parity, asset/picking/camera/inspection, test-board/monitor flow, tool/cable/screw/assembly round trips, dust ownership, Dev blower and debug shortcut checks; smoke invokes service flow |
| `ASSET_CREDITS.md` | Godot asset attribution |


## Assets and authoring

- Editable GPU source: `models/gpu.blend`; export: `models/gpu.glb`. Preserve the named `gpu` root, hierarchy, assembly/fastener names and `bench_part` metadata.
- Export saved GPU edits with Blender's `scripts/blender/export_gpu.py`; see `models/README.md`. `build_gpu.py` refuses an existing source unless `--force` is explicitly supplied. Regeneration discards manual edits.
- `upgrade_gpu.py`, `detail_gpu.py`, and `add_worn_pads.py` can modify and save source assets; inspect before use. Exporting existing edits does not save over the source.
- Testing-desk source/export: `models/repair-shop.blend` and `.glb`; standalone board export: `models/gpu-test-board.glb`. Follow `models/repair-shop.md`.
- Room source/export: `models/shop-interior.blend` and `.glb`; `scripts/blender/export_shop_interior.py` exports saved edits. The runtime layout adapter in `scripts/shop_interior.gd` closes the room for first-person play and preserves a cutaway editor view.
- Run `python godot/tools/sync_assets.py` after model exports. It copies the three GLBs and extracts part definitions and SHA-256 hashes into `godot/assets/gpu-parts.json`. Commit asset copies and metadata together; do not hand-edit generated metadata.
- Audio lives directly in `godot/assets/`; sync does not overwrite it. Preserve `godot/ASSET_CREDITS.md`, `.import` settings and `.gd.uid` files.
- `godot/tests/fixtures/service-rules.json` contains 1,024 frozen expected decisions from the retired reference implementation. Do not regenerate expected results from the implementation under test. Add focused Godot cases for new rule behavior.
- `artifacts/`, `godot/.godot/`, and `godot/build/` are ignored outputs. Do not edit caches to implement changes.

## Contracts to preserve

- Rules derive service dependencies from metadata, including dynamic screw lists and cooler-before-fan refit order. Keep decision logic in the rule evaluator and animation/placement guards in controllers.
- Cable handling and assembly detachment/refitting require empty hands; the rule action `inspect` permits holding an already-detached assembly with a tool equipped. Placing held parts retains the equipped tool, and holding a detached part does not block screw work on the board; only the screwdriver turns screws. Preserve one equipped tool at a time and busy-action guards.
- The Godot GPU root uses 0.25 scale. Inspection, detached-part rotation, screw tray transfers and testing must preserve global basis scale; orthonormalizing alone or replacing a basis with a unit rotation enlarges the card. Runtime holder resizing and testing-desk alignment belong to `workbench.gd`; the monitor remains independent of desk scaling.
- Held GPU/fan/heatsink sit on the left, leaving the centre aiming ray clear. A small green/red bench ring uses the actual placement clearance check; GPU and detached assemblies can be placed on the repair desk, and Q returns the carried GPU to its original holder. Placement checks use the authored tabletop world bounds.
- Refitting restores original parent/local transforms. Dust stays attached to its own mesh through removal, placement, storage and refitting. Residue meshes must remain separate from fixed-detail batching.
- Keep the face/tile mapping in `gpu_cleaning.gd`, `dust_overlay.gdshader` and `dust_highlight.gdshader` identical; the debug highlight shares each surface's live mask texture.
- Imported GPU triangle winding is opposite the rendered vertex and picker normals. `gpu_cleaning.gd` flips the cross product before assigning mask faces; changing that convention can leave fan dust counted on the wrong side. Cleaning rays skip the decorative `fan-brand-label` and `hub-center` meshes so the dustable `fan-hub-cap` remains reachable.
- Fan dust generation excludes inward/underside faces (`outward.y < 0.6`); those surfaces can be enclosed by the mounted fan and would leave uncleanable dust. `smoke.gd` checks that generated fan masks can be cleared from visible mounted-fan triangles across randomized runs.
- Godot dust stays with each selected mesh through assembly movement. About 40% of each cleanable mesh starts dusty at random positions. Low mask values retain a visible opacity floor until erased. The debug-only `highlight dust` button toggles a through-part magenta overlay; it activates automatically 30 seconds after a Dev blower pickup if dust remains. The Dev blower removes dust only when its nozzle points at a visible part, loops the supplied air recording during a hold, and clears each part's remainder at 98% with one jingle per part. Job completion and pad scraping are not implemented.
- Godot testing requires an assembled GPU with its fan cable connected and an empty tool hand; a held GPU can be carried directly onto the board. `testing_station.gd` moves the same card to the imported board's PCIe slot and restores its original holder transform on removal. The monitor's falling-block display uses simulated presentation FPS from current cleanliness; keep BENCH's actual rendering responsive. `assets/sounds/gpu_sounds/gpu_attach_short.wav` is the supplied short attachment recording and plays once when the card finishes seating.
- Each Godot screw has a native recess marker anchored to its original parent/transform in `gpu_service.gd`. The marker remains when the screw moves to the tray; `interaction_picker.gd` exposes its empty center as `screw_hole` only from the visible side, and a rule-checked click immediately seats the associated screw. Holding then tightens it locally; release retains progress. E on the GPU or an already-detached assembly picks it up even with a tool equipped. Focus roots, visible meshes, screw targets and dust progress come from the selected part, including future metadata-defined assemblies. A screwdriver/blower click on the GPU or R while carrying any part opens bench_closeup.gd (E also opens it when not aiming at the mat); its pointer supports screw holds and visible-surface blower cleaning, and its return-tool region keeps focus open; with empty tool hand, focus clicks can unplug the cable or lift rule-approved loosened assemblies; its isolated camera renders live proxies without changing physical transforms.
- The debug disassembly shortcut in `gpu_service.gd` normalizes partial service into a refittable state: cable unplugged, eight screws in tray slots, fan and heatsink on the repair table. The debug clean shortcut updates every dust mask and completion flag; `workbench.gd` refreshes the connected monitor's simulated rate.
- `testing_station.gd` spins only `fan-rotor` about imported local Y and moves its sibling `fan-brand-label` around the same pivot without reparenting. Dust drives eased visual speed and quiet/loud audio blending while seated, independently of monitor power. Removal stops audio and restores authored rotor/label transforms after spin-down; the global sound toggle must keep both loops muted across updates.
- Product play is first-person only. `CameraRig.legacy_test_mode` is enabled only by old smoke/service fixtures; no room-orbit controls are exposed in play; the service close-up has its own rotate/zoom camera. Room/furniture collision excludes movable GPU/tools. Proximity and busy guards apply to centred actions; Tab/Escape/focus loss release capture and cancel holds.
- `gpu_thermal.gd` models two heat faults. Dust raises core, VRAM and heatsink; dried die paste (`gpu_paste.gd` contact quality) raises only the core and slightly lowers the heatsink, so a large core-to-heatsink gap is the paste signature. The core is capped at `CORE_LIMIT` (throttling). The die is covered by `heatsink-base` when assembled, so its temperature is read from the test monitor's GPU sensor line, fed by `gpu_thermal.gd`; paste quality is not shown in normal play.
- Paste lives in two runtime layers built by `gpu_paste.gd`: `paste-die` under `gpu-die` and `paste-heatsink` under `heatsink-base`, so each travels with its part. Die cell k faces heatsink cell `mirror(k)` because the heatsink layer is flipped to face outward. Keep the RGB packing (crust, film, paste thickness) identical in `gpu_paste.gd` and `paste_layer.gdshader`. `service_rules.check_surface` owns reach (`cooler-assembly` detached) and tool choice (spudger scrapes, IPA wipe lifts film only where crust is gone, syringe applies to the die only); the frozen fixtures cover only `check`. The spudger removes crust and fresh paste but leaves film; each face auto-clears at 5% residue with one jingle. `gpu_service.gd` emits `assembly_seated`/`assembly_detached`; seating the cooler presses paste (cells over the die cap at the bond line, excess flows onto the package margin) and sets contact quality; lifting splits the pressed paste between faces and reports the imprint. Refitting over bad or missing paste is allowed; the thermal model shows the consequence. A ray that slips through the subdivided layer onto the die or heatsink base counts as that face. Test-board attachment powers the card even if the monitor is off; detaching cools it gradually. Internal fan/cooler dust dominates memory heat. Compare repairs under the same powered load. The physical thermal LCD and enlarged viewer both show the temperature and identity of the visible surface at the crosshair. The thermal viewer uses a separate world of visible mesh proxies (no through-part rendering), fixed 20-100 degrees C palette and approximate emissivity; it never replaces the live dust materials.
- The monitor screen in `scenes/test_monitor.tscn` uses a PlaneMesh so its texture spans the entire face. Godot's BoxMesh UV atlas would crop the Tetris image to one portion of the screen.


## Validation

Run from the repository root. Godot 4.7.2 with the Compatibility renderer is the verified version; no npm install or fixture generation is required. Python 3 (standard library only) is needed only for asset synchronization; Blender is needed only for authoring.

```powershell
$godotExe = 'C:\path\to\Godot_console.exe'
& $godotExe --headless --editor --path godot --import
& $godotExe --headless --path godot --script res://tests/smoke.gd
& $godotExe --headless --path godot --script res://tests/first_person_flow.gd
& $godotExe --headless --path godot --script res://tests/thermal_flow.gd
& $godotExe --headless --path godot --script res://tests/scale_toolbox_flow.gd
& $godotExe --headless --path godot --script res://tests/closeup_flow.gd
& $godotExe --headless --path godot --script res://tests/placement_flow.gd
& $godotExe --headless --path godot --script res://tests/tool_inspection_flow.gd
& $godotExe --headless --path godot --script res://tests/part_focus_flow.gd
& $godotExe --headless --path godot --script res://tests/staged_disassembly_flow.gd
& $godotExe --headless --path godot --script res://tests/repaste_flow.gd
```

Smoke includes service-flow checks and the frozen rule regressions. Run focused tests appropriate to the change. For visual/input changes, omit `--headless` and append `-- --capture` to capture rendered acceptance views; headless tests do not certify appearance or audio audibility. Report checks actually run. Documentation-only changes need referenced-path checks and `git diff --check`.

No deployment workflow or export preset is configured. The removed Pages workflow no longer publishes the old browser app.
