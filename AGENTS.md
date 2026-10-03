# Codebase navigation for agents

Last map review: 2026-10-03. Paths are relative to the repository root.

## Start each run

1. Read this guide once per run and check `git status --short` for existing work. During the same run, retain guidance and inspect its diff after updates rather than rereading unchanged files.
2. BENCH is a Godot/GDScript GPU repair game. Product work belongs in `godot/`; the browser application and Node/TypeScript toolchain have been removed.
3. Use the task router to check the owning module, its callers, relevant contracts and tests before editing. Prefer changes in existing owners. Batch independent searches/reads; narrow symbols before opening whole controllers.
4. Preserve existing user changes. Do not commit or publish unless requested.
5. Update this router and the linked architecture/contracts when ownership, paths, commands or implemented features change. Keep detailed player instructions in `godot/README.md` and model workflows in `models/`.
6. Use verified paths in `godot/tools/LOCAL_ENVIRONMENT.md` before searching installations. Keep helper output in UTF-8. Complete post-fix checks; when blocked, report the exact failed/pending command and reason. Test reports describe the code at run time, not subsequent edits.

## Task router

Choose the owner below, then search its symbols and callers with `rg -n` and read
bounded sections. Paths in the next table are under `godot/` unless prefixed `models/`.
Read the matching rows in [ARCHITECTURE.md](godot/ARCHITECTURE.md) and relevant
paragraphs in [CONTRACTS.md](godot/CONTRACTS.md) before editing.

| Request or symptom | Start here; follow these callers | Focused check suite |
| --- | --- | --- |
| Dust/scraping/IPA speed or Escape menu | `scripts/hud.gd` (`build_menu_section`), `scripts/workbench.gd` (`set_debug_repair_speed`), `scripts/gpu_paste.gd`, `scripts/gpu_cleaning.gd`, `scripts/gpu_bearing.gd` | `menu`; `paste` for stroke behavior |
| Focus clicks, missing proxies, screw seating | `scripts/bench_closeup.gd`, `scripts/interaction_picker.gd`, `scripts/gpu_service.gd`; input wiring in `scripts/workbench.gd` | `focus`; `smoke` for service changes |
| Tool selection, T/Q, equip/return | `scripts/workbench_tools.gd`, `scripts/bench_closeup.gd`, `scripts/tool_roll.gd`; input wiring in `scripts/workbench.gd` | `tools` |
| Tool shapes or proportions | `models/screwdriver.md` or `models/tool-kit.md`; saved Blender source -> export script -> `tools/import_screwdriver.gd` or `tools/import_tool_kit.gd` -> native scenes | `tools` with rendered captures |
| Paste removal/application/contact | `scripts/gpu_paste.gd`, `shaders/paste_layer.gdshader`, `scripts/bench_closeup.gd`; seating signals from `scripts/gpu_service.gd` | `paste` |
| Dust, airflow, freewheeling fan | `scripts/gpu_cleaning.gd`, dust shaders, `scripts/dust_puffs.gd`, `scripts/testing_station.gd` | `dust`; `bearing` for service guards |
| Fan sticker/shaft/oiling | `scripts/gpu_bearing.gd`, `scripts/service_rules.gd`, `scripts/testing_station.gd`, `scripts/bench_closeup.gd` | `bearing` |
| Carrying, table placement, assembly refit | `scripts/gpu_service.gd`, `scripts/gpu_inspection.gd`, `scripts/held_part_pose.gd`, `scripts/asset_contract.gd`; desk wiring in `scripts/workbench.gd` | `placement`; `smoke` for service changes |
| Temperature, performance, test monitor/audio | `scripts/gpu_thermal.gd`, `scripts/testing_station.gd`, `scripts/test_monitor.gd`, `scripts/thermal_camera.gd` | `thermal`; `smoke` for test-board changes |
| Jobs, clients, bills, ratings, GPU brands, packaging | `scripts/repair_jobs.gd`, `scripts/bill_of_materials.gd`, `scripts/gpu_style.gd`, `scripts/delivery_box.gd`, `scripts/shop_computer.gd`; `park_delivery_box` in `scripts/workbench.gd` | `jobs` |
| PCIe fingers, link dropouts, loupe | `scripts/gpu_connector.gd`, `scripts/testing_station.gd`, `scripts/test_monitor.gd`, `scripts/bench_closeup.gd` | `connector` |
| Walking/collision or room layout | `scripts/first_person.gd`, `scripts/shop_interior.gd`, `scenes/shop_interior.tscn`; `models/shop-interior.md` | `walking`; `placement` for table changes |
| Window view, trees/shrubs, day/night, delivery hatch, parcel carrying, exit door | `scripts/day_cycle.gd`, `scripts/outdoor_scenery.gd`, `scripts/outdoor_vegetation.gd` (+ `shaders/sky_backdrop.gdshader`, `shaders/scenery.gdshader`), `scripts/delivery_window.gd`, `scripts/delivery_box.gd`, window/door in `scripts/shop_interior.gd`; parcel input and `end_day` in `scripts/workbench.gd`; clock in `scripts/repair_jobs.gd` | `outside`; `jobs` for delivery changes |

Suites are defined in `godot/tools/check.py`; use `--list` for their exact tests.
For shared asset authoring/sync, use the Assets section below and `models/README.md`.

## Entry points and scope

- `godot/project.godot` starts `godot/scenes/workbench.tscn`; `godot/scripts/workbench.gd` wires the controllers.
- `README.md` is the project entry point; `godot/README.md` covers controls, features and checks.
- `models/README.md`, `models/repair-shop.md`, and `models/shop-interior.md` cover Blender assets.
- Runtime progress (balance, jobs, ledger) is in memory; there is no backend or saved-game system.
- The repair-job loop is implemented: shop-computer portal (job board, one-card bench queue, ledger) clicked in the world, job-queue display, the parcel arriving through the window delivery hatch about 2.5 s after accepting and carried to the repair desk, delivery box opened with one click, randomly rolled faults per card (`fault_odds` geometric distribution), tech referrals (symptoms, posted pay, handwritten green/yellow/red fault tag) and customers (handwritten note, itemised bill of diagnosis + labour at an adjustable rate + bill of materials, star rating on turnaround and price), a shop clock (0.5 shop min/s; 09:00-21:00 is 24 real minutes) driving a day/night cycle, the front door ending the day (next 09:00), return with payment only for a fully working card, and the thermal camera still sealed in its box in play. Spending money, purchases/unlocks, more bench slots and saving are pending.
- Edge-connector damage is implemented for diagnosis only (debug-set, never rolled by jobs, no repair yet): oxidised/lifted/torn gold fingers drawn on the imported contacts, PCIe link width and dropouts on the test monitor, the wiggle test (rock the seated card) and the jeweller's loupe in the tool roll with a magnifying focus view.
- The outside is view-only: a right-wall window over a central-China mountain valley (yard, windswept pines, shrub clusters, ledge plants and two connected detailed stylized mountain ranges as geometry, distant ridgelines drawn by direction on a sky dome), sky/sun/moon/stars/haze from the clock, an afternoon window sunbeam and night room dimming.
- First-person walking, GPU inspection, toolbox selection, screwdriver service, assembly removal/refit, airflow-weighted dust thickness with lit felt shading, the shop air blower (narrow jet, dust cloud, motor, air-spun fan), debug Dev blower cleaning, test-board/monitor flow, fan audio, thermal investigation, the dried-paste heat fault, repasting (spudger scrape, IPA wipe, syringe application, pressure spread and lift-test imprint) and the dry fan-bearing grind with its oiling service (sticker peel, rotor pull, shaft wipe, oil drops, rotor refit) are implemented. Volumetric dust (shells/felt clumps), fan wear from overspinning, paste thickness/mounting pressure, pad scraping, replacement parts, economy progression and electrical diagnosis are pending.

## Assets and authoring

- Editable GPU source: `models/gpu.blend`; export: `models/gpu.glb`. Preserve the named `gpu` root, hierarchy, assembly/fastener names and `bench_part` metadata.
- The active `models/gpu.blend` / `.glb` use the rounded 710 art: softer board/frame silhouettes, rounded fins, exaggerated capacitors/screw heads and a teal/cream/copper palette. `models/gpu-rounded.blend` and `.glb` retain the style study; original component set, transforms and service metadata are preserved. `scripts/blender/stylize_gpu.py` converts an unstyled baseline and refuses already-rounded inputs. See `models/README.md` for authoring and preview details.
- Export saved GPU edits with Blender's `scripts/blender/export_gpu.py`; see `models/README.md`. `build_gpu.py` refuses an existing source unless `--force` is explicitly supplied. Regeneration discards manual edits.
- `upgrade_gpu.py`, `detail_gpu.py`, and `add_worn_pads.py` can modify and save source assets; inspect before use. Exporting existing edits does not save over the source.
- Testing-desk source/export: `models/repair-shop.blend` and `.glb`; standalone board export: `models/gpu-test-board.glb`. Follow `models/repair-shop.md`.
- Room source/export: `models/shop-interior.blend` and `.glb`; `scripts/blender/export_shop_interior.py` exports saved edits. The runtime layout adapter in `scripts/shop_interior.gd` closes the room for first-person play and preserves a cutaway editor view.
- Run `python godot/tools/sync_assets.py` after model exports. It copies the three GLBs and extracts part definitions and SHA-256 hashes into `godot/assets/gpu-parts.json`. Commit asset copies and metadata together; do not hand-edit generated metadata.
- Audio lives directly in `godot/assets/`; sync does not overwrite it. Preserve `godot/ASSET_CREDITS.md`, `.import` settings and `.gd.uid` files.
- `godot/tests/fixtures/service-rules.json` contains 1,024 frozen expected decisions from the retired reference implementation. Do not regenerate expected results from the implementation under test. Add focused Godot cases for new rule behavior.
- `artifacts/`, `godot/.godot/`, and `godot/build/` are ignored outputs. Do not edit caches to implement changes.

## Validation

Run from the repository root. Godot 4.7.2 with the Compatibility renderer is the verified version; no npm install or fixture generation is required. Python 3 (standard library only) is needed only for asset synchronization; Blender is needed only for authoring.

Verified executable paths, environment overrides and log locations are in
[LOCAL_ENVIRONMENT.md](godot/tools/LOCAL_ENVIRONMENT.md). From the repository root:

```powershell
python godot/tools/check.py --list
python godot/tools/check.py --suite menu
python godot/tools/check.py --suite focus --import
python godot/tools/check.py --suite tools --capture
python godot/tools/check.py --suite smoke
```

Choose the suites appropriate to the task and inspect the final result. The runner
writes UTF-8 logs plus a JSON report under ignored `godot/build/checks/`. Individual
Godot commands remain documented in `godot/README.md`.

Smoke includes service-flow checks and the frozen rule regressions. Run focused tests appropriate to the change. For visual/input changes, omit `--headless` and append `-- --capture` to capture rendered acceptance views; headless tests do not certify appearance or audio audibility. Play opens a 1920x1080 window over a 1280x800 base viewport (`canvas_items`, `expand`); `workbench.gd` shrinks capture runs to `CAPTURE_SIZE` (1280x800) so PNGs stay comparable. Report checks actually run. Documentation-only changes need referenced-path checks and `git diff --check`.

No deployment workflow or export preset is configured. The removed Pages workflow no longer publishes the old browser app.
