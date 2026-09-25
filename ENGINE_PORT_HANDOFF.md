# Engine port handoff: GPU repair workbench

This document maps the existing browser prototype for an agent porting it to Godot. Paths are relative to this repository root. The browser implementation and bundled GPU GLB were inspected on 2026-09-25, including the testing-desk additions in the working tree.

The runnable Godot port now lives in [godot/project.godot](godot/project.godot), with inspection, screwdriver handling, cable motion and resumable screw service implemented. See [godot/README.md](godot/README.md) for its implemented features, pending work, and validation commands. The behavior described below remains the browser reference contract; it is not a claim that every feature is already ported.

## Start here

Read these in order:

1. [README.md](README.md): player controls and the current feature scope.
2. [src/main.ts](src/main.ts): startup, scene composition, cameras, focus mode, and frame loop.
3. [src/interactions.ts](src/interactions.ts): the central interaction coordinator and input routing.
4. [src/service-rules.ts](src/service-rules.ts) and [tests/service-rules.test.mjs](tests/service-rules.test.mjs): service legality and dependency behavior.
5. [src/gpu-repair.ts](src/gpu-repair.ts): screws, detachable assemblies, placement, and reassembly.
6. The cleaning, scraping, and asset sections below before recreating those systems.

The prototype is a TypeScript/Three.js application bundled by Vite. There is no backend, database, saved-game system, or engine project. Runtime state lives in controller closures and scene objects. Most controllers also update HTML directly, so the port needs to separate behavior from that presentation code.

## What currently works

The player inspects a fictional GPU, disconnects its fan cable, removes and reinstalls screws, detaches the fan or cooler, places or stores parts, blows away dust, and scrapes old thermal-pad residue. The toolbox contains a screwdriver, blower, and plastic scraper. Development builds also expose a faster purple blower, labeled **Dev blover** in the UI.

There are two work areas. The original repair desk is interactive. The second testing desk and its GPU test board are visual props: there is no insertion, power, electrical diagnosis, or testing logic. The alcohol bottle and empty spare-parts box are also props. Replacement pads, replacement supplies, varied card models, and a broader job/economy system are not implemented.

The model is an illustrative, 710-inspired GPU, not a dimensionally accurate hardware reference. Handling and placement use scripted transforms and bounding-box checks rather than rigid-body simulation.

## File map and behavior ownership

| File | Responsibility / useful entry points |
| --- | --- |
| [index.html](index.html) | Canvas and HTML controls: camera views, equipment, service actions, cleaning progress, focus actions, sound, and status. DOM IDs are the binding contract for the TypeScript controllers. |
| [src/style.css](src/style.css) | Layout, responsive UI, focus-mode presentation, and blower reticle. |
| [src/main.ts](src/main.ts) | `start()`: renderer, environment, lighting, GPU/workbench/testing-desk loading, camera presets, focus visibility, FPS, lifecycle cleanup. |
| [src/workbench.ts](src/workbench.ts) | `createWorkbench()`: procedural repair desk, mat, PCB holder and animated jaws, parts tray, toolbox/lid, all tools, lamp, alcohol, and spare-parts box. Returns references and tool home positions. |
| [src/load-testing-desk.ts](src/load-testing-desk.ts) | Loads the complete testing-desk GLB, removes its floor, scales it by 5, aligns tabletop heights, and positions it to the repair desk's right with a 2.5-unit gap. Returns a camera target. |
| [src/load-gpu.ts](src/load-gpu.ts) | `loadGPU()`: loads the named GPU root, parses metadata, enables shadows, batches fixed meshes. Uses the procedural GPU only if the asset URL is absent; a broken GLB is a load error. |
| [src/gpu.ts](src/gpu.ts) | `PartMetadata` and `createGPU()`: original procedural GPU fallback and readable construction/reference hierarchy. The detailed GLB is the primary asset; the fallback is not a full replacement for its detail and residue. |
| [src/interactions.ts](src/interactions.ts) | `setupInteractions()`: connects controllers, routes pointer/keyboard/UI actions, arbitrates busy states and camera controls, creates placement preview, and updates contextual UI. |
| [src/workbench-tools.ts](src/workbench-tools.ts) | `createWorkbenchTools()`: exclusive equipped-tool state, toolbox lid, queued tool switching, grab/return/place animations, held pose and blower aiming. |
| [src/gpu-inspection.ts](src/gpu-inspection.ts) | `setupGPUInspection()`: lift/set down the entire GPU, camera-relative rotation/zoom/pan, cable connection state, plug movement and wire deformation. |
| [src/gpu-repair.ts](src/gpu-repair.ts) | `setupGPURepair()`: discover service parts, capture original transforms, evaluate actions, hold-to-turn screws, tray placement, detach/pick up/store/refit assemblies, and held-part rotation. |
| [src/service-rules.ts](src/service-rules.ts) | `createServiceRules()`: engine-independent dependency evaluator. Takes part definitions and current facts, returns `{ allowed, missing, reason }`. No scene or DOM dependency. |
| [src/gpu-cleaning.ts](src/gpu-cleaning.ts) | `setupGPUCleaning()`: blower aim/raycast, dust updates, bounded particles, air sound, before comparison, service completion and next-job flow. |
| [src/gpu-dust.ts](src/gpu-dust.ts) | `createGPUDust()`: surface masks, shader modification, clumps, persistent per-mesh dirt, weighted progress, and remaining-dust hints. |
| [src/gpu-pad-removal.ts](src/gpu-pad-removal.ts) | `setupGPUPadRemoval()`: directional scraper strokes, residue masks, active-pad guides/highlight, mask-aware picking, progress and reset. |
| [src/interaction-highlight.ts](src/interaction-highlight.ts) | Hover feedback on interactive surfaces; excludes objects tagged `noHighlight`. |
| [src/sound.ts](src/sound.ts) | `WorkbenchSound`: sampled screwdriver/jingle audio, synthesized mechanical effects and air noise, mute/unlock/disposal. |
| [src/vite-env.d.ts](src/vite-env.d.ts), [tsconfig.json](tsconfig.json) | Browser/build typing and TypeScript configuration. |
| [package.json](package.json), [package-lock.json](package-lock.json) | Commands, dependencies, and locked installation. |
| [.github/workflows/deploy.yml](.github/workflows/deploy.yml) | Node 24 CI: install, tests, build with repository base path, publish `dist/` to GitHub Pages. |

`dist/` is generated browser output; `node_modules/` is installed dependencies. `artifacts/` is for generated/reference outputs, not the runtime source of behavior.

## Assets and authoring workflow

| Path | Purpose |
| --- | --- |
| [models/gpu.blend](models/gpu.blend) | Editable primary GPU source. |
| [src/assets/gpu.glb](src/assets/gpu.glb) | Actual GPU loaded at runtime. Contains separate service parts, custom metadata, and 12 residue meshes across four memory chips. Contains no animation clips. |
| [models/gpu-before-service.blend](models/gpu-before-service.blend) | Historical model backup from before the service upgrade. |
| [models/repair-shop.blend](models/repair-shop.blend) | Editable second desk and test-board source. Despite its name, this is not the source for the procedural interactive repair desk. |
| [models/repair-shop.glb](models/repair-shop.glb) | Complete second desk plus testing board; loaded by `load-testing-desk.ts`. |
| [models/gpu-test-board.glb](models/gpu-test-board.glb) | Separate board export for future use; not independently loaded by current startup. |
| [models/README.md](models/README.md) | GPU editing/export details and object names. |
| [models/repair-shop.md](models/repair-shop.md) | Second desk collections and manual re-export instructions. |
| [scripts/blender.mjs](scripts/blender.mjs) | Blender command runner; supports `BLENDER_BIN`, build, and export. |
| [scripts/blender/build_gpu.py](scripts/blender/build_gpu.py) | Initial GPU generator; protects an existing source unless explicitly forced. |
| [scripts/blender/export_gpu.py](scripts/blender/export_gpu.py) | Exports only the GPU hierarchy with metadata, evaluating temporary mesh copies of curves, fonts, and modifiers. |
| [scripts/blender/upgrade_gpu.py](scripts/blender/upgrade_gpu.py) | Earlier service-detail upgrade. |
| [scripts/blender/detail_gpu.py](scripts/blender/detail_gpu.py) | PCB/connector detail pass. |
| [scripts/blender/add_worn_pads.py](scripts/blender/add_worn_pads.py) | Adds separately editable/exported worn-pad remnants. |
| [src/assets/manual-screwdriver.wav](src/assets/manual-screwdriver.wav) | Runtime screwdriver recording. Original and attribution are under `sounds/screwdriver/`. |
| [src/assets/cleaning-complete.ogg](src/assets/cleaning-complete.ogg) | Runtime cleaning jingle; source MIDI is `sounds/winjingle-source.mid`. |

Preserve audio attribution from the README and bundled license notes when copying assets. Other files under `sounds/`, including box-opening and electric-screwdriver samples, are not necessarily runtime audio; check `sound.ts` imports.

Normal GPU iteration is **edit/save `models/gpu.blend` -> `npm run model:export` -> reload**. Export does not rebuild or save over the Blender source. `model:build` is initial generation, not the normal editing command. `model:export` does not update the testing-desk assets.

Blender source coordinates are Z-up; the GPU exporter converts to Y-up glTF coordinates. Custom metadata vectors are explicitly converted as `[x, z, -y]`. Units are illustrative. The browser also offsets the GPU and scales/aligns the testing desk at runtime; importing the GLBs alone will not reproduce the complete workbench arrangement.

## Startup and controller connections

```text
index.html -> src/main.ts
  loadGPU() -> GPU GLB + metadata + fixed-detail batching
  createWorkbench(scene, gpu) -> procedural repair scene and tools
  loadTestingDesk(tabletop) -> second desk and camera target
  WorkbenchSound
  setupInteractions(...)
    inspection <-> repair -> service-rules
    tools -> workbench objects
    cleaning -> gpu-dust
    padRemoval
    hover highlight + placement preview
  render loop -> interactions.update(now) -> camera controls -> render
```

`interactions.ts` supplies callbacks between controllers: repair reads cable state from inspection and tool state from tools; inspection asks repair to check cable actions; scraping reads whether the cooler is removed; cleaning reads whether all removed parts are refitted and the cable is connected. Controllers have additional movement/busy guards beyond the service rules.

Each frame updates tools, inspection, repair, PCB-holder jaws, camera-control eligibility, cleaning, and contextual controls. Rendering runs continuously while the page is visible. Hidden-page/window-blur handling stops active input actions. Development builds expose `window.__bench` with scene, camera, renderer, workbench, interactions, sounds, and cleaning for inspection.

## GPU hierarchy and metadata contract

The following is an abbreviated hierarchy verified in the bundled GLB. Omitted meshes include fixed component detail, housing, blades, and screw geometry.

```text
gpu
  board
    pcb-detail
      memory-residue-<chip>-<piece> ...
  board-fan-socket
  edge-connector
  mounting-bracket
  cooler-assembly
    heatsink
    fan-assembly
      fan-rotor
      fan-cable
        fan-plug
        fan-positive-wire
        fan-ground-wire
    fan-screw-1 ... fan-screw-4
  cooler-screw-1 ... cooler-screw-4
```

Blender properties `part_role`, `removal_direction`, `requires_json`, and `attachment` are exported into a JSON string in glTF extras named `bench_part`. The loader parses it into `object.userData.part`:

```ts
type PartMetadata = {
  role: 'assembly' | 'fixed' | 'removable' | 'fastener';
  assembledPosition: number[];
  removalDirection?: number[];
  requires?: string[];
  attachment?: string;
};
```

Keep these names/relationships or provide an explicit mapping. Many lookups still use literal names, even though service fasteners are discovered by role and dependencies. The root `gpu` has an assembly role but is excluded from detachable-part discovery. Referenced removable objects such as `fan-plug` become connectors in the service evaluator.

The repair controller captures the original **parent, local position, quaternion, and scale** at setup. Refit restores those exact values. `assembledPosition` alone is not the reassembly implementation, and exported `removalDirection` is not a universal animation driver: screw motion and cable deformation contain their own axes/coordinates.

Only fixed `pcb-detail` and `mounting-bracket` meshes are batched by material/attributes. `memory-residue-*` is explicitly excluded. Do not merge independently removable, cleanable, or scrapable surfaces into an undifferentiated mesh without replacing their identity/mask system.

## State and service rules to preserve

| Owner | State |
| --- | --- |
| Tools | Toolbox `open`, `lidProgress`, per-tool location (`toolbox`, `held`, `desk`), derived equipped tool, pending switch and motion. Only one tool is held. |
| Inspection | Whole GPU `held`, `moving`, `cableConnected`; inspection zoom/pan and cable animation. |
| Repair | `heldPart`, `moving`, `removed[]`, `stored[]`; independent paused screw-turn progress and original transforms. |
| Cleaning | `blowing`, `complete`, `celebrated`, `before`, `job`, `targetPart`; dust data remains on each captured mesh. |
| Scraping | Per-residue mask and remaining cells; active stroke plane/direction. Independent of dust progress. |
| Main | Camera view/transition, focus mode, saved camera, frame/lifecycle state. |

Service evaluator rules:

- Screws require the screwdriver. Cable handling and assembly remove/pickup/refit require empty hands. Blowers and scraper do not bypass these checks.
- Fan removal requires disconnected `fan-plug` and all screws in the fan assembly's `requires` list removed.
- Cooler removal requires disconnected `fan-plug` and all screws in the cooler assembly's `requires` list removed. It does **not** require the fan to be separately removed; an attached fan travels with the cooler hierarchy.
- A declared exception also requires unplugging the fan cable **before removing cooler screws**. Fan screws do not have that extra prerequisite.
- Refitting an assembly requires its parent assembly installed: when both are detached, cooler before fan.
- Refitting a screw requires the assembly that lists it as a requirement to be seated.
- Reconnecting the cable requires both dependent assemblies seated. This check does not itself require all screws tightened; finishing the service does.
- Screw counts come from metadata. Adding a cooler screw to the declared requirements should inherit the relevant checks.
- Duplicate IDs, unknown requirements, cycles, invalid part actions, and unknown parts are errors, not silently accepted states.

Movement guards belong to the controllers. Equipping a blower is allowed while carrying a detached part so it can be cleaned; equipping a screwdriver or scraper in that state is blocked. Inspection of the whole GPU can coexist with an equipped tool. Putting down, storing, or refitting a detached part requires returning the tool.

Screw turns take 1.5 seconds of accumulated hold time. Releasing pauses progress, and another hold resumes it. Removed screws move to separate labeled fan/cooler tray rows. Focus mode offers a hold-to-refit button, selecting eligible cooler screws before fan screws. Reduced motion shortens transition animations but does not eliminate the screw hold requirement.

Detached parts are reparented with their world pose preserved. Held parts rotate near the camera; placed parts return to their captured upright orientation. Placement tests the complete bounding box, including the cable, against desk limits and obstacles. The current limits/tray coordinates are hard-coded for the procedural repair desk; make these authored anchors/surfaces in the port. Storage hides the same object and retains its cleaning state; it does not refit or recreate it.

## Input, picking, and cameras

Picking raycasts the scene and walks ancestors for `userData.action`: `gpu`, `assembly`, `screw`, `cable`, `residue`, `desk`, `toolbox`, or a tool ID. Hidden objects and dust visuals are skipped. Enlarged invisible screw/plug targets improve touch access. Pointer actions and UI buttons call the same controller methods.

Preserve input arbitration, not just individual click handlers:

- Empty-hand dragging normally orbits the camera. With a held GPU/part it rotates that item instead. Middle-drag pans the normal camera; wheel/pinch zooms.
- A screwdriver press on a screw begins a hold action; release/cancel/blur ends the active turn.
- A blower press on the GPU or a part starts cleaning. While holding an item, right-drag or two fingers turns it; pinch/wheel zooms. Touch aim is offset 46 pixels above the finger.
- A scraper drag owns the gesture and prevents rotation. The GPU must be set down in its PCB holder; the cooler must be removed. The set-down guard is in `interactions.ts`, while the cooler guard is in `gpu-pad-removal.ts`.
- A second pointer cancels an active scrape, blow, or screw turn before the two-finger gesture takes over.
- Escape first pauses an active screw; otherwise it returns the equipped tool, refits a held detached part, or sets down the held GPU, in that order.

Camera presets are **Both desks**, **Repair**, **Testing**, and **Top**. Focus mode saves the camera, hides most workbench objects, and presents either the GPU or the currently held detached assembly. It supplies Store part and Refit screw controls so touch users need not place/pick tiny objects on the full desk. Exiting restores the saved camera. The PCB-holder jaws open while the GPU is lifted/moving and close after it returns.

## Dust cleaning and job completion

`gpu-dust.ts` selects cleanable meshes by exact names/patterns: board top/bottom, fan housing/blades/hub cap, heatsink base/fins, and screw heads. Ownership is captured before detachment, using the nearest assembly/fastener ancestor. Screw heads have their own progress ownership; the three main summary labels do not enumerate every screw.

Each surface has six local planar face masks, arranged as 48 x 48 tiles in a 144 x 96 texture. Front and back are independent. Coverage is derived from geometry; shader changes blend amber dust into material color/roughness/metalness. Small instanced clumps shrink with remaining dust. Progress is weighted remaining dust mass, not a simple average of object percentages.

Cleaning raycasts captured mesh references, so detached parts remain targets. Other solid objects block the air stream. Invisible pick targets and visual effects are excluded from cleaning hits. Masks and clumps follow their mesh through rotation, removal, placement, storage, and refit.

Regular blower updates use `dt * 1.5` and radius `.47`; the developer blower uses `dt * 30` and radius `1.1`. The particle pool is bounded to 48. These are current tuning values in browser units, not physical air simulation. Initial dust and next-card variation use unseeded randomness.

- **Compare before** shows the original masks without overwriting cleaned data and prevents blowing during comparison.
- At 99% overall cleanliness while blowing, the final dust is cleared, progress becomes 100%, and the completion jingle plays once for that job.
- **Finish service** requires at least 90% dust cleanliness, every removed assembly and screw refitted, cable connected, and no repair/inspection motion in progress.
- Pad-removal progress is **not** part of the finish condition. Do not accidentally introduce that requirement during a behavior-preserving port.
- **Next card** reuses the same GPU, resets dust and job flags, increments the job number, and dispatches `bench-next-job`; scraping listens to that event and restores residue masks. The next button is shown after finishing, while the handler itself checks assembled state.

## Thermal-pad scraping

Residue meshes must match `memory-residue-<number>-<number>`. Each uses a 64 x 64 one-channel mask mapped over its local X/Z bounds. Begin a stroke in the outer band of the remaining rectangle: the inner rectangle is 55% of its width/height. The selected piece glows light red and displays both guide rectangles.

The start chooses the dominant X or Z direction; only movement inward toward the opposite edge erases material. A stroke clears a strip with radius 18% of the smaller piece dimension. Untouched material retains its position and size. At 2% remaining or less, the final cells clear and the piece is hidden.

The shader discards cleared fragments, and the custom raycast also rejects hits in cleared mask cells. Reproducing only the visible hole is insufficient: a cleared region must stop intercepting input. `end()` removes temporary guides/highlights; `reset()` restores all masks. There is no new-pad placement behavior.

## Suggested engine organization

Keep the same behavior boundaries while replacing Three.js, DOM, browser audio, and pointer plumbing with engine equivalents. For a Godot port, a possible scene/script layout is:

```text
Workbench scene
  Camera rig
  Repair desk / placement surfaces / holder / tray anchors
  Testing desk (visual)
  GPU instance
  Toolbox / tool instances
  Interaction coordinator
  UI
  Audio

Scripts or resources
  Service part definitions + service rule evaluator
  Tool inventory/controller
  GPU inspection controller
  GPU repair controller
  Dust surface data + material/shader
  Cleaning/job controller
  Residue data + scraper controller
```

This is a proposed organization, not a claim about automatic GLB metadata import. Verify how the chosen engine/importer exposes glTF extras and preserve `bench_part` in explicit part definitions if needed. Cache original local transforms and parent identity before any gameplay reparenting. Keep input arbitration in one place, expose controller actions to both world picking and UI, and send state-change notifications to the UI rather than letting behavior scripts depend on HTML IDs.

The GLBs provide geometry/materials and hierarchy. Recreate service animations, tool handling, dust shaders, masks, picking, placement rules, and UI in engine code. A direct model import alone supplies none of those browser behaviors. Port the pure service evaluator first; preserve its tests as acceptance cases before adding presentation polish.

Suggested implementation order:

1. Import/validate the GPU hierarchy and metadata, establish desk/holder/tray anchors, and reproduce basic camera framing.
2. Implement tool exclusivity, picking, whole-GPU inspection, and cable state.
3. Implement service validation, resumable screws, detach/place/store/refit, and transform restoration.
4. Implement persistent per-surface dust and job completion, then residue masks and directional scraping.
5. Add focus/touch controls, status feedback, audio, hover/placement feedback, and reduced-motion behavior.

## Verification and reference commands

From this repository root on Windows PowerShell, use `npm.cmd` if the `npm.ps1` shim is blocked:

```powershell
npm.cmd ci
npm.cmd run dev -- --port 5173
npm.cmd test
npm.cmd run build
```

Use the address printed by Vite. Existing assets are included; Blender is not needed to run the browser reference. The repository documents Node 22.12+ or 24, and CI uses Node 24. The build runs TypeScript checking followed by Vite. Tests use `node --test tests/*.test.mjs`.

Current test sources contain 15 cases:

| Test file | Behavior covered |
| --- | --- |
| [tests/service-rules.test.mjs](tests/service-rules.test.mjs) | Nine cases: tool/cable constraints, assembly dependencies, refit ordering, dynamic screw counts, invalid graphs, supplied connector state, and restrictions for blower/dev blower/scraper. |
| [tests/workbench-tools.test.mjs](tests/workbench-tools.test.mjs) | Five cases: exclusive switching, blower placement/retrieval, busy guards, scraper lifecycle, and developer blower lifecycle. |
| [tests/gpu-pad-removal.test.mjs](tests/gpu-pad-removal.test.mjs) | One case: cooler/start/direction guards, partial strips, untouched regions, mask-aware picking, shader mask, guides, reset, and disposal. |

These are targeted logic tests, not full rendering or input coverage. For the engine port, manually verify:

- Remove/refit the fan; remove/refit the cooler with its fan still attached; detach both and enforce cooler-before-fan reassembly.
- Try forbidden tool/cable/assembly actions and confirm useful status feedback with no state mutation.
- Pause and resume screws; repeat complete disassembly/reassembly without transform drift.
- Clean both sides and detached/stored parts; confirm their dust survives every move and solid objects block the blower.
- Scrape partial strips while the GPU sits in the holder; verify cleared areas no longer intercept picking and untouched areas remain.
- Check 90% service completion, 99%-to-100% cleanup, comparison mode, and next-card dust/residue reset.
- Check desktop and touch/focus controls, blocked desk placement, tool switching, input cancellation, and sound/reduced-motion behavior.

This handoff was checked against source and GLB metadata. It does not certify visual parity in an engine; use the running browser prototype as the behavioral reference.
