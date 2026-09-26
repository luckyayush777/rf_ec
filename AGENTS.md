# Codebase navigation for agents

Last map review: 2026-09-25. Paths are relative to the repository root.

## Start each run

1. Read this guide and check `git status --short` for existing work.
2. Treat Godot (`godot/`) as the destination for product work. The TypeScript browser app (`src/`) is temporary scaffolding and a behavior reference for the port; it will not be part of the final product. Follow explicit user scope for scaffold fixes or shared-asset work.
3. Use the tables below to open the owning module, its callers, and relevant tests. Prefer a small change in the existing owner over a new subsystem.
4. Check current source before relying on a documented detail. This is a navigation map, not a substitute for reading the affected code.
5. Before finishing, follow **Keep this guide current** below.

## Project and entry points

BENCH is an interactive GPU repair game being built in Godot with GDScript and the Compatibility renderer. The TypeScript/Three.js/Vite application is temporary scaffolding used to prototype and reference behavior during migration. Do not treat it as a second long-term product or require browser feature parity for new Godot work. Runtime progress is currently in memory; there is no backend, database, or saved-game system.

| Area | Start here | Further context |
| --- | --- | --- |
| Godot | [godot/project.godot](godot/project.godot) starts [godot/scenes/workbench.tscn](godot/scenes/workbench.tscn); [godot/scripts/workbench.gd](godot/scripts/workbench.gd) wires controllers in `_ready()` | [godot/README.md](godot/README.md): implemented features, pending work, commands |
| Temporary browser scaffold | [index.html](index.html) loads [src/main.ts](src/main.ts), whose `start()` builds the scene and connects controllers | [README.md](README.md): prototype controls and scope |
| Browser behavior reference | [ENGINE_PORT_HANDOFF.md](ENGINE_PORT_HANDOFF.md) | Detailed hierarchy, state, input, cleaning, scraping, and porting contract. Some historical wording predates the Godot project; verify port status in its README and source. |
| GPU authoring | [models/README.md](models/README.md) | Blender editing, export, metadata and stable object names |
| Workshop interior authoring | [models/shop-interior.blend](models/shop-interior.blend), [models/shop-interior.md](models/shop-interior.md) | Room, oscilloscope and labelled storage; instanced by `godot/scenes/shop_interior.tscn`. |
| Testing-desk authoring | [models/repair-shop.md](models/repair-shop.md) | Separate desk/board model and export workflow |

Current scope: the browser supports inspection, screws/cable, assembly removal/refit/storage, blower cleaning and pad-residue scraping. Godot supports inspection, screwdriver handling, cable/screw service with persistent screw seats, fan/heatsink assembly handling, randomized part-specific dust cleaning, a debug-only aimed Dev blower with per-part 98% completion, debug clean/disassemble shortcuts, and a testing-board/monitor flow with simulated Tetris-style FPS. The regular blower, scraping and job progression are pending. The testing board remains a visual prop in the browser. Replacement pads and electrical diagnosis are not implemented. Do not assume imported geometry implies gameplay support.

Migration direction: implement lasting gameplay and UI in Godot. Consult the scaffold to understand existing behavior and reuse suitable assets; change it only when needed for the task. Its current asset paths, rule-fixture generator and Pages deployment are transitional dependencies, not the final architecture. Before removing scaffold files, relocate any still-used asset sources and replace the TypeScript-dependent fixture generation so Godot remains independently runnable and testable. This direction does not itself request immediate deletion of the scaffold.

## Godot ownership map

All paths in this table are under `godot/`. Scene node names and controller references form a contract; inspect both when renaming nodes.

| File | Responsibility |
| --- | --- |
| `scenes/workbench.tscn` | Main composition, imported assets, camera, lights and controller nodes |
| `scenes/repair_desk.tscn`, `scenes/toolbox.tscn` | Editable native desk/holder/tray and toolbox/lid/screwdriver/Dev blower meshes |
| `scenes/test_monitor.tscn`, `scripts/test_monitor.gd`, `scripts/testing_station.gd` | Native LCD/power button, falling-block display, GPU-to-board transfer, signal cable, dust-driven rotor animation and test/fan audio |
| `scenes/shop_interior.tscn`, `scripts/shop_interior.gd` | Imported room wrapper, editor-visible unit conversion, cutaway shell and background prop layout; synced from `models/shop-interior.glb` |
| `scripts/workbench.gd` | Startup, input arbitration, controller wiring, desk alignment, obstacles and holder jaws |
| `scripts/workbench_tools.gd` | Exclusive screwdriver/Dev blower state, lid/tool animation, nozzle aim, placement and busy guards |
| `scripts/gpu_service.gd` | Cable deformation, screw progress and persistent seats, assembly lift/place/store/refit, tray transfer, exact refit, debug full disassembly and screwdriver audio |
| `scripts/gpu_inspection.gd`, `scripts/orbit_camera.gd` | Whole-card inspection and home transforms; camera presets/orbit/pan/zoom |
| `scripts/interaction_picker.gd` | Cached triangle queries, surface normals, cleaning rays through fan-hub decoration, depth-tested screw/hole/plug targets and assembly action routing |
| `scripts/gpu_cleaning.gd`, `shaders/dust_overlay.gdshader`, `shaders/dust_highlight.gdshader` | Randomized part-owned masks, fan exposed-face restriction, imported normal correction, visible low dust, debug through-part highlight and 30-second timer, aimed cleaning, debug instant completion, audio |
| `scripts/hud.gd` | Native UI, debug buttons and signals; service decisions belong in controllers/rules |
| `scripts/asset_contract.gd` | Named-part binding, parent validation, original transforms and service definitions |
| `scripts/service_rules.gd` | Pure rule evaluator; malformed graphs fail closed |
| `tools/sync-assets.mjs` | Copy source assets and generate `assets/gpu-parts.json` with part metadata and hashes |
| `tools/build-rule-fixtures.mjs` | Generate deterministic reference decisions from the browser rules into ignored `.godot/rule-fixtures.json` |
| `tests/smoke.gd`, `tests/service_flow.gd` | Rule parity, asset/picking/camera/inspection, test-board/monitor flow, tool/cable/screw/assembly round trips, dust ownership, Dev blower and debug shortcut checks; smoke invokes service flow |
| `ASSET_CREDITS.md` | Godot asset attribution |

## Temporary browser scaffold ownership map

Startup flow: `index.html` -> `main.ts` -> asset loaders + `createWorkbench()` -> `setupInteractions()`. The interaction coordinator connects inspection, repair, tools, cleaning, scraping and highlighting. Controllers own their runtime state; many also update DOM controls directly.

| File | Responsibility / entry point |
| --- | --- |
| [src/main.ts](src/main.ts) | `start()`: renderer, lights, environment, camera presets, focus mode, FPS, frame loop and cleanup |
| [index.html](index.html), [src/style.css](src/style.css) | DOM controls and IDs; layout, responsive/focus UI and reticle styling |
| [src/interactions.ts](src/interactions.ts) | `setupInteractions()`: pointer/keyboard/UI routing, controller wiring, busy guards, gestures, placement preview and contextual UI |
| [src/workbench.ts](src/workbench.ts) | `createWorkbench()`: procedural repair desk, holder jaws, tray, toolbox, tools and props; returned scene references |
| [src/workbench-tools.ts](src/workbench-tools.ts) | `createWorkbenchTools()`: exclusive equipped tool, toolbox lid, queued switching, placement/retrieval, tool animation and aiming |
| [src/gpu-inspection.ts](src/gpu-inspection.ts) | `setupGPUInspection()`: whole-card lift/return/rotation/zoom/pan, cable connection state, plug/wire motion |
| [src/gpu-repair.ts](src/gpu-repair.ts) | `setupGPURepair()`: service-part discovery, screw progress/tray, detachable assemblies, placement/storage/refit and held-part rotation |
| [src/service-rules.ts](src/service-rules.ts) | `createServiceRules()`, `gpuServiceExceptions`: pure dependency/tool decisions, no DOM or scene dependency |
| [src/gpu-cleaning.ts](src/gpu-cleaning.ts) | `setupGPUCleaning()`: blower raycast/aim, particles, sound, before comparison, completion and next-card flow |
| [src/gpu-dust.ts](src/gpu-dust.ts) | `createGPUDust()`: per-mesh surface masks, shader changes, clumps, weighted progress and remaining-dust hints |
| [src/gpu-pad-removal.ts](src/gpu-pad-removal.ts) | `setupGPUPadRemoval()`: directional scraping, residue masks, guides/highlight, mask-aware picking and reset |
| [src/interaction-highlight.ts](src/interaction-highlight.ts) | `createInteractionHighlight()`: hover feedback; honors `noHighlight` |
| [src/sound.ts](src/sound.ts) | `WorkbenchSound`: recordings, synthesized effects, air noise, mute, audio unlock and disposal |
| [src/load-gpu.ts](src/load-gpu.ts) | `loadGPU()`: GLB loading, `bench_part` metadata decoding, shadows and fixed-detail batching |
| [src/gpu.ts](src/gpu.ts) | `PartMetadata`, `createGPU()`: procedural fallback and reference hierarchy |
| [src/load-testing-desk.ts](src/load-testing-desk.ts) | Imported testing desk positioning/scaling and camera target |
| [src/vite-env.d.ts](src/vite-env.d.ts), [tsconfig.json](tsconfig.json) | Vite asset types and strict TypeScript configuration |

## Where to make common changes

| Intended change | Files to inspect together |
| --- | --- |
| Browser button, label or layout | `index.html`, `src/style.css`, and the controller querying the DOM ID (`rg -n 'the-id' src index.html`) |
| Camera, focus or touch behavior | `src/main.ts`, `src/interactions.ts`, `src/gpu-inspection.ts`; Godot: `orbit_camera.gd`, `gpu_inspection.gd`, `workbench.gd` |
| Service order, new fastener or tool restriction | Asset metadata, `src/service-rules.ts`, `src/gpu-repair.ts`, `tests/service-rules.test.mjs`; check Godot rules/fixtures if shared behavior changes |
| Tool equip/place/return | `src/workbench-tools.ts`, `src/interactions.ts`, `src/workbench.ts`, `tests/workbench-tools.test.mjs`; Godot: `workbench_tools.gd`, toolbox scene, service-flow tests |
| Godot screw seats or hole picking | `godot/scripts/gpu_service.gd`, `godot/scripts/interaction_picker.gd`, `godot/scripts/workbench.gd`, `godot/tests/service_flow.gd` |
| Cleaning speed, completion or next card | `src/gpu-cleaning.ts`; masks/appearance/progress in `src/gpu-dust.ts`; reset wiring in `src/interactions.ts` |
| Scraping or residue picking | `src/gpu-pad-removal.ts`, `src/interactions.ts`, `tests/gpu-pad-removal.test.mjs`, `scripts/blender/add_worn_pads.py` |
| Repair desk geometry | `src/workbench.ts`; Godot uses separate native `repair_desk.tscn` and `toolbox.tscn` |
| GPU geometry/materials | `models/gpu.blend` -> export -> `src/assets/gpu.glb`; review loader batching and part metadata, then sync Godot copies |
| Testing desk geometry/placement | `models/repair-shop.blend`, `models/repair-shop.md`, `src/load-testing-desk.ts`; Godot alignment in `scripts/workbench.gd` |
| Build/deployment | `package.json`, `package-lock.json`, `tsconfig.json`, `.github/workflows/deploy.yml` |

## Assets and generated files

- `models/gpu.blend` is the editable GPU source; `src/assets/gpu.glb` is its committed browser export. `models/gpu-before-service.blend` is a historical backup.
- `scripts/blender.mjs` runs Blender. `scripts/blender/build_gpu.py` generates an initial model; `export_gpu.py` exports saved edits. `upgrade_gpu.py`, `detail_gpu.py`, and `add_worn_pads.py` are targeted source upgrade scripts; inspect them before use because they can save the source and export assets.
- Prefer `npm.cmd run model:export` for existing GPU edits. `model:build` refuses an existing source unless forced; regeneration with `--force` discards manual edits. Blender 4.5+ is documented; set `$env:BLENDER_BIN` to its executable if discovery fails.
- `models/shop-interior.blend` is the meter-scale room source; `scripts/blender/export_shop_interior.py` exports saved edits to `models/shop-interior.glb`, including the hidden cutaway walls, without changing the source. The initial `build_shop_interior.py` refuses an existing source unless `--force` is explicitly supplied. See `models/shop-interior.md` for collections, previews and commands. Godot instances it through `scenes/shop_interior.tscn`; the `@tool` layout adapter preserves prop proportions, expands the shell around the playable desks and hides the cutaway ceiling/walls. The native repair-desk floor is hidden in favor of the room floor.
- `models/repair-shop.blend` exports to `models/repair-shop.glb`; `models/gpu-test-board.glb` is the standalone board export. The GPU `model:export` command does **not** export this desk. Follow `models/repair-shop.md`.
- `src/assets/` contains runtime GPU/audio assets. `sounds/` retains audio sources and license notes; preserve attribution when changing recordings.
- Run `node godot/tools/sync-assets.mjs` after changing shared GPU/desk assets or browser-sourced screwdriver/jingle audio. The Godot-specific `assets/sounds/ambient_gpu.wav`, `assets/sounds/loud_gpu.wav`, `assets/sounds/compressed_air.wav`, `clean_jingle.wav`, `assets/sounds/gpu_sounds/gpu_attach_short.wav` and `assets/button_press.ogg` are supplied directly and are not copied by this script. Commit synchronized `godot/assets/` copies and metadata together; do not hand-edit `gpu-parts.json`. Keep Godot `.import` settings and `.gd.uid` files.
- `node_modules/`, `dist/`, `artifacts/`, `godot/.godot/`, and `godot/build/` are ignored dependencies/build/cache/capture outputs. Change source rather than editing these to implement a fix. `.gitignore` is the authoritative list.

## Contracts to preserve

- Keep the named `gpu` root, assembly/fastener identities, original hierarchy and part metadata consistent. Blender properties are exported as `bench_part`; the browser decodes them into `userData.part`, while Godot uses the generated sidecar and asset adapter.
- `loadGPU()` falls back to `createGPU()` only when the asset URL is absent. A broken GLB is an error. The fallback has less detail than the primary asset.
- Rules derive service dependencies from metadata, including dynamic screw lists and cooler-before-fan refit order. Keep decision logic in the rule evaluator and animation/placement guards in controllers.
- Cable and assembly handling require empty hands; only the screwdriver turns screws. Preserve one equipped tool at a time and busy-action guards.
- Refitting restores original parent/local transforms. Dust stays attached to its own mesh through removal, placement, storage and refitting. Residue meshes must remain separate from fixed-detail batching.
- Keep the face/tile mapping in `gpu_cleaning.gd`, `dust_overlay.gdshader` and `dust_highlight.gdshader` identical; the debug highlight shares each surface's live mask texture.
- Imported GPU triangle winding is opposite the rendered vertex and picker normals. `gpu_cleaning.gd` flips the cross product before assigning mask faces; changing that convention can leave fan dust counted on the wrong side. Cleaning rays skip the decorative `fan-brand-label` and `hub-center` meshes so the dustable `fan-hub-cap` remains reachable.
- Fan dust generation excludes inward/underside faces (`outward.y < 0.6`); those surfaces can be enclosed by the mounted fan and would leave uncleanable dust. `smoke.gd` checks that generated fan masks can be cleared from visible mounted-fan triangles across randomized runs.
- Scraped holes must disappear from both rendering and raycast picking. Browser scraping requires the cooler removed and the card set down in the holder.
- Browser service completion requires at least 90% cleanliness and reassembly; reaching 99% while blowing clears the final dust. The development-only `Dev blover` must remain gated by development mode.
- Godot dust stays with each selected mesh through assembly movement. About 40% of each cleanable mesh starts dusty at random positions. Low mask values retain a visible opacity floor until erased. The debug-only `highlight dust` button toggles a through-part magenta overlay; it activates automatically 30 seconds after a Dev blower pickup if dust remains. The Dev blower removes dust only when its nozzle points at a visible part, loops the supplied air recording during a hold, and clears each part's remainder at 98% with one jingle per part. This does not yet implement browser job completion or pad scraping.
- Browser DOM IDs bind HTML to controller queries. Preserve those bindings when editing UI.
- Godot testing requires an assembled GPU with its fan cable connected and empty hands. `testing_station.gd` moves the same card to the imported board's PCIe slot and restores its original holder transform on removal. The monitor's falling-block display uses simulated presentation FPS from current cleanliness; keep BENCH's actual rendering responsive. `assets/sounds/gpu_sounds/gpu_attach_short.wav` is the supplied short attachment recording and plays once when the card finishes seating.
- Each Godot screw has a native recess marker anchored to its original parent/transform in `gpu_service.gd`. The marker remains when the screw moves to the tray; `interaction_picker.gd` exposes its empty center as `screw_hole` only from the visible side, and the same rule-checked hold action refits the associated screw.
- The debug disassembly shortcut in `gpu_service.gd` normalizes partial service into a refittable state: cable unplugged, eight screws in tray slots, fan and heatsink on the repair table. The debug clean shortcut updates every dust mask and completion flag; `workbench.gd` refreshes the connected monitor's simulated rate.
- `testing_station.gd` spins only `fan-rotor` about imported local Y and moves its sibling `fan-brand-label` around the same pivot without reparenting. Dust drives eased visual speed and quiet/loud audio blending while seated, independently of monitor power. Removal stops audio and restores authored rotor/label transforms after spin-down; the global sound toggle must keep both loops muted across updates.
- The monitor screen in `scenes/test_monitor.tscn` uses a PlaneMesh so its texture spans the entire face. Godot's BoxMesh UV atlas would crop the Tetris image to one portion of the screen.

## Validation and run commands

Run from the repository root. Prefer Node 24 (used by CI). On Windows PowerShell use `npm.cmd` to avoid the `npm.ps1` execution-policy issue; other shells can use `npm`.

```powershell
npm.cmd ci                         # Install locked dependencies when needed
npm.cmd run dev -- --port 5173     # Browser development server
npm.cmd test                       # node --test tests/*.test.mjs
npm.cmd run build                  # TypeScript check, then Vite production build
npm.cmd run preview -- --port 4173 # Preview an existing build
```

Browser tests: `tests/service-rules.test.mjs` covers dependency/tool/cable decisions and invalid graphs; `tests/workbench-tools.test.mjs` covers exclusive tools, placement and busy guards; `tests/gpu-pad-removal.test.mjs` covers partial strokes, untouched areas, picking, shader masks and reset. They import TypeScript directly with Node. Retain distinct behavioral guards when changing tests.

For browser logic changes, run tests and build. Visual/input changes also need a focused manual check of the affected desktop/touch flow; unit tests do not certify rendering. For documentation-only changes, verify referenced files/commands and `git diff --check`; a game build is unnecessary.

Godot checks (set `$godotExe` to the installed console executable; the Godot README records the version used for the port):

```powershell
$godotExe = 'C:\path\to\Godot_console.exe'
& $godotExe --headless --editor --path godot --import
node godot/tools/build-rule-fixtures.mjs
& $godotExe --headless --path godot --script res://tests/smoke.gd
```

Generate rule fixtures before smoke checks, particularly after browser-rule changes. For visual checks open `godot/project.godot` in the editor and press F5. See `godot/README.md` for rendered acceptance captures and full commands. Report checks actually run and any unavailable runtime; do not present documented checks as passing results.

`.github/workflows/deploy.yml` runs install, tests and the Vite build, then publishes `dist/` on pushes to `main` or manual dispatch. For this repo's Pages path, use `npm.cmd run build -- --base /rf_ec/` and `npm.cmd run preview -- --base /rf_ec/` together. Godot is not part of this deployment and has no Web export preset yet.

## Keep this guide current

At the end of each run, review whether the work changed navigation knowledge. Update this file in the same change when files move, ownership changes, commands change, asset generation changes, or a feature moves from pending to implemented. Correct stale entries in place; keep the map concise instead of appending a session transcript. If nothing relevant changed, leave it unchanged.

- Keep paths, symbols and commands grounded in current source. Use `rg --files` and targeted `rg -n` searches to check them.
- Update `Last map review` after reviewing the full map; a small edit should not imply a complete re-audit.
- Put detailed player instructions in `README.md`, Godot status in `godot/README.md`, and detailed behavior/port contracts in `ENGINE_PORT_HANDOFF.md`; link them here. As migration progresses, shrink/remove obsolete scaffold entries and document the standalone Godot asset/test workflows that replace them.
- Record a durable gotcha near its owning module/workflow. Keep transient logs, unverified plans and machine-specific installation paths out of this map.
- In the final response, state what changed and what was checked. Do not commit or publish solely because this guide describes deployment.
