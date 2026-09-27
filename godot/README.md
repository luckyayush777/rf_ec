# BENCH - GPU repair

Open [project.godot](project.godot) in Godot and press **F5**. If the Project Manager opens, choose **Import**, select this file, then **Import & Edit**. The main scene is [scenes/workbench.tscn](scenes/workbench.tscn).

Developed and checked with **Godot 4.7.2**, using **GDScript and the Compatibility renderer** for desktop play. No external Godot plugins are required.

## Implemented

- Imported GPU, including its original component hierarchy and 12 separate worn-pad residue meshes.
- Imported workshop interior with a brick back wall, painted side wall, tiled floor, background instrument bench, oscilloscope, labelled parts bins, soldering station, stool and trolley. The runtime is enclosed for first-person play; the editor keeps a cutaway overview. The props are scenery. See [room authoring](../models/shop-interior.md).
- Native, editable repair-desk scene with mat, holder jaws, tray, canvas tool roll, simplified lamp/spare-parts props, and floor.
- Imported second testing desk, aligned beside the repair desk using tabletop bounds.
- Native LCD test monitor with a physical power button, status LED and a visible signal cable to the testing board. The assembled GPU seats in the board and returns to its repair holder; the monitor runs a deterministic Tetris-style falling-block demo at a simulated rate tied to cleaning progress (8 FPS dirty, up to 60 FPS clean). Attachment and power-on sounds are included.
- The test-board GPU fan spins with its hub label while the housing stays fixed. Dustier cards run faster and blend in `loud_gpu.wav`; clean cards settle to `ambient_gpu.wav`. Speed and sound ease toward the current cleanliness, including live debug cleaning. Removing the card stops the loops and spins the rotor down to its authored pose. Monitor power controls only the display; the seated card keeps running. These are simulated cooling responses, not measured RPM or temperature.
- First-person-only play: WASD walking, captured mouse-look, capsule collision against the room/desks, a centred interaction prompt and distance-limited picking. Tab/Escape releases the mouse; focus loss pauses active holds. Orbit poses remain only for existing automated service fixtures.
- Handheld thermal camera on the repair desk, with a live low-resolution display and RMB viewfinder. Both display the aimed surface temperature in degrees C, its name, and a spot crosshair. The fixed 20-100 degrees C palette shows visible surface heat at 9 Hz, with a spot readout and an approximation warning for reflective metal. Separate memory/core/cooler temperatures warm under test-board power and cool gradually when disconnected. Internal fan/heatsink dust is the main fault. Existing front/rear memory packages have native U1-U10 / VRAM markings.
- Surface picking, animated whole-GPU lift/set-down, independent inspection rotation/zoom, and flip.
- Holder jaws open during inspection and close when the GPU returns.
- Metadata adapter that validates named parts and original parent relationships, records original transforms, and creates service definitions.
- Animated canvas tool bag pulled toward the front of the bench, clear of the screw tray, with six stitched pockets, retaining straps, and four empty pockets. Clicking it opens a large live 3D view over the blurred room and unrolls the fabric; click a visible tool or its keyboard-accessible label. Switching returns the previous tool, and closing rolls the bag shut. The thermal camera remains on its stand and is also selectable from the footer.
- Screwdriver equip/return, automatic toolbox opening, and desk placement/retrieval with footprint and obstacle checks. Inspection can continue with the screwdriver equipped.
- Fan cable unplug/reconnect with plug animation and wire deformation. Cable handling requires empty hands; cooler screws require the cable unplugged.
- All eight screws support 1.5-second hold-to-turn removal/refit, independent paused progress, labeled tray slots, and exact original parent/transform restoration. Shallow screw seats remain visible when screws move to the tray; click an empty seat with the screwdriver to seat that screw immediately, then hold to tighten it in place. Released screws retain their progress and follow the GPU.
- Fan and heatsink/cooler assemblies can be lifted after their cable/screw requirements are met, rotated while held, placed on clear repair-table space, picked up again, stored, and refitted to their exact original mounts. The fan travels with the cooler if still attached.
- Part-owned amber dust masks on the PCB front/back, fan, heatsink, and screw heads. Each new workbench covers about 40% of each cleanable mesh in randomized patches. Fan dust is generated only on exposed upper faces, so it does not appear inside the housing or beneath blades. Cleaning one surface leaves the other parts and sides dirty, including after detachment or refit. Imported mesh winding is corrected so masks align with rendered and picked faces; decorative pieces over the fan hub do not block cleaning its cap.
- Focus works on the full card or a selected detached fan/heatsink. E picks up a detached part even with a tool equipped; R opens its focus view; E on the mat places the part while keeping your tool. Tools can be picked up or returned while holding the part. New metadata-defined assemblies share this inspection path. Detaching/refitting still requires empty hands. Holding a detached fan does not block screwdriver work on the remaining board; full, partially dismantled, and bare boards remain serviceable on the mat. After returning the tool in focus, click the cable to unplug it or a loosened assembly to lift it.
- Focus cleaning: hold LMB and sweep over visible dust; RMB drag or Flip part exposes the backplate. Only the selected part and its live dust masks appear in focus; the progress bar tracks that part. A large Return tool area puts the equipped tool away and leaves the card view open.
- Development-only **Dev blower** in the toolbox. Its nozzle follows the crosshair and must point at a visible part to remove dust. Holding the trigger plays the supplied air recording, with its steady section looped. The Tab menu shows overall and per-part cleanliness. At 98% cleanliness, that part's remaining dust clears and its jingle plays once (unless sound is muted).
- Debug builds also have **Debug: Clean GPU** and **Debug: Disassemble GPU** in the bottom panel. Clean GPU clears every dust mask and updates a connected test monitor to 60 simulated FPS immediately. Disassemble GPU unplugs the cable, moves all eight screws to their tray slots, and places the fan and heatsink on the repair table; normal refitting still works afterward. Disassembly is available when the GPU is set down and off the test board.
- Low-density dust remains visible until its mask is fully erased. In debug builds, the bottom **highlight dust** button toggles a magenta view of remaining dust through parts. If dust remains 30 seconds after equipping the Dev blower, this view turns on automatically. Rotate, flip or remove parts to expose dust before cleaning it.
- Pointer release, Escape and window focus loss pause active screw turns. Tool/cable/inspection changes are blocked during active service animations.
- Screwdriver, blower and cleaning jingles share a sound toggle; see [asset credits](ASSET_CREDITS.md).
- Service-rule evaluator, exercised against 1,024 checked-in expected decisions and used by the live cable/screw controller.

## Controls

| Action | Control |
| --- | --- |
| Walk / look | WASD / mouse; no third-person view or camera presets |
| Release/resume mouse | Tab or Escape; releasing also ends screw/blower holds |
| Interact / pick up | Aim the crosshair and press E (or click); move within reach |
| Inspect GPU | E on the card, including with a tool equipped; RMB + mouse rotates, F flips, wheel adjusts holding distance. With a part held, R opens focus; E on the mat places that part and keeps the equipped tool. |
| Place / return held card | GPU and detached parts sit in the left hand. Aim at the desk: a green ring marks a clear placement and red marks a blocked spot. E places the part while keeping your tool; Q returns the carried card to its repair holder. |
| Carry GPU to testing | With an assembled GPU and empty tool hand, E on the test board; a held card transfers directly |
| Remove tested card | E on the installed card or board; it returns to the holder |
| Monitor power | E on its physical button; monitor power does not disconnect board power |
| Select / switch tool | Click the tool bag or press E on it; wait for it to unroll, then click a tool or select its label with arrow keys + Enter. Esc rolls it closed. |
| Open GPU service window | With screwdriver or blower equipped, click the GPU/backplate, screw or empty seat. E picks up the GPU instead; R while holding it opens focus. The room blurs behind the sharp GPU. RMB drag rotates the view; wheel zooms; Flip part reveals the other side. Click Return tool to put the tool away without closing focus. Esc closes. |
| Turn/refit screw | In the service window, hold LMB on a screw or empty seat. A refit screw seats immediately; holding turns it, releasing pauses. |
| Connect fan cable | With empty tool hand, E on plug/socket/wire |
| Lift assembly | E on fan/heatsink after removing its cable/screw dependencies |
| Rotate / place / refit assembly | RMB + mouse / E on clear repair tabletop / Q; cooler refits before fan |
| Clean dust | Equip Dev blower, hold LMB and sweep over exposed surfaces; remove assemblies to reach internal dust |
| Thermal camera | E on orange camera on the repair desk; hold RMB for its larger viewfinder |
| Place / retrieve a tool | E on clear repair tabletop / E on placed tool |
| Return equipped tool | Q; thermal camera returns to its desk stand, other tools to the toolbox |
| Debug clean/disassemble and dust highlight | Tab to release mouse and open the debug cleaning menu |
| Toggle sound | M |

This controller targets desktop keyboard/mouse. The centred ray is depth-tested:
hidden screws and memory cannot be picked through another surface. Most room props
are fixed scenery; the GPU, service assemblies and three tools are the supported
pickup objects. There is no jumping or free physics throwing.

## Thermal investigation loop

Seat the dirty, assembled GPU in the test board and give it about 30-60 seconds to
warm. Take the orange thermal camera and walk around to the exposed rear VRAM
packages. Hold RMB and note their surface readings and the fixed colour scale.
Front memory covered by the cooler is occluded, just as it is in the ordinary view.

Return the camera with Q, remove the GPU, disassemble and clean internal parts,
reassemble, then repeat the **same powered test**. Fan/heatsink cleaning reduces
memory heat even if PCB dust remains. An unpowered card also cools, so a cold reading
immediately after servicing is not proof of repair. Reconnect it to compare under
load. The card retains heat for a while after removal, allowing inspection during
cooldown. The test board supplies power whenever the card is seated, independently
of the monitor switch.

This is a gameplay simulation: ambient is 24 degrees C; model memory targets are 48 degrees C clean
and 94 degrees C fully dusty, approached gradually. Surface readings differ from those
internal model values. Emissivity is simplified (0.95 for packages, lower for shiny
GPU metal); real camera calibration, reflections, per-texel heat diffusion and
hardware-specific safe limits are not simulated. Bad pads, bad contact, electrical
faults and hardware telemetry are not implemented. FPS/fan sound still use the
existing cleanliness-driven presentation model.

## Pending gameplay

The regular blower, directional pad scraping, comparison view, job progression, air particles and general interaction highlights are pending. Imported pad remnants are geometry only. Alcohol and replacement supplies have no gameplay yet. The falling-block feed simulates GPU performance; it does not measure actual rendering FPS or diagnose electrical faults.

No deployment workflow or export preset is configured.

## Where to edit

| File | Responsibility |
| --- | --- |
| `scenes/workbench.tscn` | Main composition, asset instances, camera, lighting, environment, and controller nodes. |
| `scenes/repair_desk.tscn` | Editable desk/mat/holder/tray and prop meshes. |
| `scenes/toolbox.tscn` | Screwdriver and Dev blower meshes; tool_roll.gd builds the canvas bag, pockets, straps and rolling geometry. |
| `scenes/test_monitor.tscn`, `scripts/test_monitor.gd` | Editable LCD housing, power button, sound and deterministic falling-block display. |
| `scripts/testing_station.gd` | PCIe fixture interaction, GPU transfer, monitor connection, signal cable, fan animation and cleanliness-driven fan audio. |
| `scenes/shop_interior.tscn`, `scripts/shop_interior.gd` | Imported workshop shell and props, editor-visible layout conversion and cutaway visibility. |
| `scripts/workbench.gd` | Startup, controller wiring, input arbitration, desk alignment, placement obstacles and jaw motion. |
| `scripts/bench_closeup.gd`, `scripts/tool_roll.gd` | Live GPU/tool-bag viewing windows, isolated mesh proxies, mouse picking, orbit/zoom and segmented fabric animation. |
| `scripts/workbench_tools.gd` | Exclusive screwdriver/Dev blower/thermal-camera locations, roll/tool animations and placement guards. |
| `scripts/gpu_cleaning.gd`, `shaders/dust_overlay.gdshader`, `shaders/dust_highlight.gdshader` | Randomized dust masks, aimed cleaning, visible low-density residue, debug highlight, air loop and per-part jingles. |
| `scripts/held_part_pose.gd` | Shared left-hand framing for carried GPU and detached assemblies. |
| `scripts/gpu_service.gd` | Cable state/deformation, screw progress, assembly handling/placement, exact refit and screwdriver audio. |
| `scripts/interaction_picker.gd` | Cached triangle picking, live-transform tracking, depth-tested screw/plug targets, cleaning rays through fan-hub decoration, surface normals and action routing. |
| `scripts/first_person.gd` | Runtime walking body, collision generation, mouse capture/look and reach. `orbit_camera.gd` supplies only legacy test poses. |
| `scripts/gpu_thermal.gd` | Dust-dependent heating/cooling, surface temperature/emissivity and VRAM markings. |
| `scripts/thermal_camera.gd`, `shaders/thermal_surface.gdshader`, `scenes/thermal_camera.tscn` | Pickup instrument, separate depth-tested thermal world, display, spot readout and fixed palette. |
| `scripts/gpu_inspection.gd` | Whole-GPU inspection state and exact home-transform restoration. |
| `scripts/hud.gd` | Native UI and signals; closeup provides the tool selection view, and workbench owns switching guards. |
| `scripts/asset_contract.gd` | Map source part names to imported nodes, validate parents, capture transforms. |
| `scripts/service_rules.gd` | Pure dependency/tool checks. Invalid graphs fail closed with errors. |
| `assets/gpu-parts.json` | Generated part metadata and source asset SHA-256 hashes. |
| `tools/sync_assets.py` | Copies Blender GLBs and extracts part metadata using Python standard library. |
| `tests/fixtures/service-rules.json` | Checked-in expected service decisions; no generation step or external toolchain. |
| `tests/smoke.gd` | Rule parity, malformed graphs, metadata/hierarchy, picking, camera, inspection, test-board/monitor flow, randomized dust coverage, fan mask orientation/hub cleaning, mounted-fan dust reachability, per-part completion and debug shortcut checks. |
| `tests/service_flow.gd` | Called by smoke: tool lifecycle/busy guards, cable deformation/reset, front/rear/tray picking, pause/resume/cancel, assembly placement/refit/storage, blower aim/audio/cleaning, debug highlight timing/button, and eight screw round trips. |

Godot uses ordinary imported GLB scenes; the sidecar avoids reliance on importer-specific handling of custom extras. The asset adapter preserves part metadata and captures original parents and transforms. Rule acceptance and missing-dependency lists are checked against frozen regression cases; malformed graphs fail closed.

## Asset updates

Blender exports in `../models/` are the model sources. After changing `gpu.glb`, `repair-shop.glb` or `shop-interior.glb`, run from the repository root:

```powershell
python godot/tools/sync_assets.py
```

Python 3 needs no third-party packages. Audio, including screwdriver and completion sounds, is maintained directly in `assets/`.

Godot reimports the copies in `assets/`. The supplied fan recordings `assets/sounds/ambient_gpu.wav` and `assets/sounds/loud_gpu.wav`, plus `assets/sounds/compressed_air.wav`, `assets/sounds/clean_jingle.wav`, `assets/sounds/gpu_sounds/gpu_attach_short.wav` and `assets/button_press.ogg` live directly in Godot and are not overwritten by this sync script. Commit copied assets, generated JSON, `.import` settings and `.gd.uid` files; do not commit `.godot/` caches or `build/` captures. Do not hand-edit generated metadata or copy only one of the GPU/metadata pair. Existing asset/license notes remain in [the repository README](../README.md), [the model workflow](../models/README.md) and [the Godot asset credits](ASSET_CREDITS.md).

## Command-line checks

From the repository root, point PowerShell at the downloaded executable (adjust its location if needed):

```powershell
$godotExe = 'C:\Users\user\Desktop\ayush.dev\godot\Godot_v4.7.2-stable_win64_console.exe'

# Import assets and check scripts.
& $godotExe --headless --editor --path godot --import

# Run acceptance checks using the checked-in regression fixture.
& $godotExe --headless --path godot --script res://tests/smoke.gd
& $godotExe --headless --path godot --script res://tests/first_person_flow.gd
& $godotExe --headless --path godot --script res://tests/thermal_flow.gd
& $godotExe --headless --path godot --script res://tests/scale_toolbox_flow.gd
& $godotExe --headless --path godot --script res://tests/closeup_flow.gd
& $godotExe --headless --path godot --script res://tests/placement_flow.gd
& $godotExe --headless --path godot --script res://tests/tool_inspection_flow.gd
& $godotExe --headless --path godot --script res://tests/part_focus_flow.gd
& $godotExe --headless --path godot --script res://tests/staged_disassembly_flow.gd

# Run the game, or open the editor.
& $godotExe --path godot
& $godotExe --editor --path godot
```

The first-person flow checks walking/collision, mouse release, proximity and pickup/return. The thermal flow checks physical camera pickup, placement, exclusivity, occlusion, internal cleaning under equal load and cooldown; append `-- --capture` without `--headless` for player/dirty/clean thermal PNGs.

Optional legacy rendered acceptance run: append `-- --capture` to the test command and omit `--headless`. It runs the same checks, writes repair/overview/front/back/service-tray, screw-hole and testing-monitor PNGs to ignored `build/`, then exits. Service tests tick hold progress explicitly for reproducibility and run real tool/cable/tray animations. The automated tests do not certify audible sound quality; check that manually.

The next gameplay milestone is pad-residue scraping and the remaining cleaning/job controls.

The GPU uses a 0.25 scene scale (about 30 cm wide at the room's five units per
meter). Inspection, rotation, detached assemblies, tray screws and test-board
attachment preserve that physical scale. The holder is resized to fit and aligned beneath the GPU near the front of the mat. The test
desk footprint is 25% smaller, and the test board is resized independently;
the desk height and monitor size stay unchanged. `scale_toolbox_flow.gd -- --capture`
also captures the holder, held card, test station and tool bag (open and unrolling) under `build/`. `closeup_flow.gd -- --capture` adds enlarged front/rear GPU views and verifies real GUI mouse routing; headless runs exercise the same picking/controller actions directly.

Tool-roll visual reference: [Ergodyne Arsenal roll-up organizer](https://www.ergodyne.com/arsenal-5874-roll-up-tool-bag-zipper-pockets) (pockets, webbing and cinch straps). Geometry is native procedural Godot geometry; no product imagery is bundled.
