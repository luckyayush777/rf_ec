# BENCH - GPU repair

Open [project.godot](project.godot) in Godot and press **F5**. If the Project Manager opens, choose **Import**, select this file, then **Import & Edit**. The main scene is [scenes/workbench.tscn](scenes/workbench.tscn).

Developed and checked with **Godot 4.7.2**, using **GDScript and the Compatibility renderer** for desktop play. No external Godot plugins are required.

## Implemented

- **Repair jobs**: play opens on an empty bench. Take a job on the shop computer's internal portal, open the delivery box on the repair desk, diagnose and fix the card, then return it from the portal to get paid. See [Repair jobs](#repair-jobs).
- Rounded, stylized 710 / 2GB DDR3 GPU with rounded fins and larger capacitors/screw heads, retaining its original component hierarchy and 12 separate worn-pad residue meshes. Delivered cards use one of three consistent brand palettes: **Lotac** (teal, cream and orange), **Vsus** (navy and mint), or **CSI** (charcoal, plum and red). Each brand has matching printed retail packaging; components, specifications and repair behaviour are shared.
- Imported workshop interior with a brick back wall, painted side wall, tiled floor, background instrument bench, oscilloscope, labelled parts bins, soldering station, stool and trolley. The runtime is enclosed for first-person play; the editor keeps a cutaway overview. The props are scenery. See [room authoring](../models/shop-interior.md).
- Native, editable repair-desk scene with mat, holder jaws, tray, canvas tool roll, simplified lamp/spare-parts props, and floor.
- Imported second testing desk, aligned beside the repair desk using tabletop bounds.
- Native LCD test monitor with a physical power button, status LED and a visible signal cable to the testing board. The assembled GPU seats in the board and returns to its repair holder; the monitor runs a deterministic pseudo-3D racing demo whose simulated rate follows the card's core clock. The clock holds 1905 MHz below 70 degrees C and drops in 15 MHz bins to 600 MHz at the 105 degrees C limit (60 FPS at full clock, down to 8 FPS fully throttled); a throttling card also stutters with uneven frame pacing and hitches. Hot VRAM does not slow the feed; it shows memory errors as sparkling pixels, garbage blocks and torn rows. The monitor lists the lap time, core **MHZ** and **GPU °C**. The game plays through the monitor speakers: an engine whose pitch follows the car's speed, road roar, tyre squeal in tight bends and a whoosh when passing. Its sound breaks up with the card: at low frame rates the engine pitch moves in steps, a hitched frame loops the last fraction of a second into a stuttering buzz, and hot VRAM adds crackles. Attachment and power-on sounds are included.
- The test-board GPU fan spins with its hub label while the housing stays fixed. Dustier cards run faster and blend in `loud_gpu.wav`; clean cards settle to `ambient_gpu.wav`. Speed and sound ease toward the current cleanliness, including live debug cleaning. Removing the card stops the loops and spins the rotor down to its authored pose. Monitor power controls only the display; the seated card keeps running. These are simulated cooling responses, not measured RPM or temperature.
- First-person-only play: WASD walking, captured mouse-look, capsule collision against the room/desks, a centred interaction prompt and distance-limited picking. Tab/Escape releases the mouse; focus loss pauses active holds. Orbit poses remain only for existing automated service fixtures.
- Handheld thermal camera on the repair desk. In play it is still **sealed in its box** for now, so it cannot be picked up; automated fixtures keep it on its stand. It has a live low-resolution display and RMB viewfinder. Both display the aimed surface temperature in degrees C, its name, and a spot crosshair. The fixed 20-100 degrees C palette shows visible surface heat at 9 Hz, with a spot readout and an approximation warning for reflective metal. Separate memory/core/cooler temperatures warm under test-board power and cool gradually when disconnected. Internal fan/heatsink dust is the main fault. Existing front/rear memory packages have native U1-U10 / VRAM markings.
- Surface picking, animated whole-GPU lift/set-down, independent inspection rotation/zoom, and flip.
- Holder jaws open during inspection and close when the GPU returns.
- Metadata adapter that validates named parts and original parent relationships, records original transforms, and creates service definitions.
- Animated canvas tool bag pulled toward the front of the bench, clear of the screw tray, with eight stitched pockets and retaining straps; the air blower and then the jeweller's loupe fill the last pockets. Clicking it opens a large live 3D view over the blurred room and unrolls the fabric; click a visible tool or its keyboard-accessible label. Switching returns the previous tool, and closing rolls the bag shut. When unboxed, the thermal camera stays on its stand and is also selectable from the footer; while boxed, its button is hidden.
- Screwdriver equip/return, automatic toolbox opening, and desk placement/retrieval with footprint and obstacle checks. Inspection can continue with the screwdriver equipped.
- The tools share rounded shapes, charcoal grips, ivory accents and beveled edges, with individual colours for the blowers, spudger, IPA bottle, paste syringe, fan oiler and thermal camera. Working tips and proportions are retained. The syringe has a finger rest and graduation marks, the wipe has folded edges, and the scraper/wipe shown on the paste face match the kit. See [tool-kit authoring](../models/tool-kit.md) and [screwdriver authoring](../models/screwdriver.md).
- Fan cable unplug/reconnect with plug animation and wire deformation. Cable handling requires empty hands; cooler screws require the cable unplugged.
- All eight screws support 1.5-second hold-to-turn removal/refit, independent paused progress, labeled tray slots, and exact original parent/transform restoration. Shallow screw seats remain visible when screws move to the tray; click an empty seat with the screwdriver to seat that screw immediately, then hold to tighten it in place. Released screws retain their progress and follow the GPU.
- Fan and heatsink/cooler assemblies can be lifted after their cable/screw requirements are met, rotated while held, placed on clear repair-table space, picked up again, stored, and refitted to their exact original mounts. The fan travels with the cooler if still attached.
- Part-owned dust masks on the PCB front/back, fan, heatsink, and screw heads. Each mask stores thickness: a grey film covers about 85% of each cleanable mesh in clumpy, randomized cloud, and builds into lighter, opaque felt where air and gravity deposit it: fin tops under the fan's blade sweep, fan blades toward the hub, upward faces, and the board just outside the cooler where fin exhaust spills. The lit dust shader adds fibre grain, relief and a soft sheen at grazing angles, and feathers patch edges. Fan dust is generated only on exposed upper faces, so it does not appear inside the housing or beneath blades. Cleaning one surface leaves the other parts and sides dirty, including after detachment or refit. Imported mesh winding is corrected so masks align with rendered and picked faces; decorative pieces over the fan hub do not block cleaning its cap.
- Focus works on the full card or a selected detached fan/heatsink. E picks up a detached part even with a tool equipped; R opens its focus view; E on the mat places the part while keeping your tool. Tools can be picked up or returned while holding the part. New metadata-defined assemblies share this inspection path. Detaching/refitting still requires empty hands. Holding a detached fan does not block screwdriver work on the remaining board; full, partially dismantled, and bare boards remain serviceable on the mat. After returning the tool in focus, click the cable to unplug it or a loosened assembly to lift it.
- Focus cleaning: hold LMB and sweep over visible dust; RMB drag or Flip part exposes the backplate. Only the selected part and its live dust masks appear in focus; the progress bar tracks that part. A large Return tool area puts the equipped tool away and leaves the card view open.
- Shop **air blower** (electric duster) in the tool bag's last pocket. It works in focus: hold LMB and sweep its narrow jet. Thick felt lifts quickly in clumps; the last thin film clings and needs steady air. Air also carries a little way past the aimed surface into faces turned toward it, such as fin gaps or the fins under the fan. Cleaned dust leaves as a soft cloud with falling flakes. Its motor (a synthesized placeholder until `assets/sounds/air_blower.wav` is supplied) winds up on the trigger and coasts down after release. Blowing on an idle fan's rotor freewheels it, then it coasts to a stop; a dry bearing grinds while it spins, and the rotor cannot be serviced until it stops.
- Development-only **Dev blower** in the toolbox. Its nozzle follows the crosshair and must point at a visible part to remove dust. Holding the trigger plays the supplied air recording, with its steady section looped. The Tab menu shows overall and per-part cleanliness. At 98% cleanliness, that part's remaining dust clears and its jingle plays once (unless sound is muted).
- The Escape menu opens with collapsed sections: **Dust & diagnostics**, **Assembly**, **Fault setup**, **Repair speeds**, and **Sound**. Click a header to expand or collapse its subpanel; expanded groups scroll inside the menu when needed. The four debug sections appear only in debug builds.
- Debug builds have **Clean GPU** under **Dust & diagnostics** and **Disassemble GPU** / **Reassemble GPU** under **Assembly**. Clean GPU clears every dust mask; a connected test monitor recovers as the card cools (dried paste still throttles it). Disassemble GPU unplugs the cable, moves all eight screws into their tray rows, and lays the heatsink and fan out on the mat just left of the card; normal refitting still works afterward. Disassembly is available when the GPU is set down and off the test board.
- Low-density dust remains visible until its mask is fully erased. In debug builds, the bottom **highlight dust** button toggles a magenta view of remaining dust through parts. If dust remains 30 seconds after equipping the Dev blower, this view turns on automatically. Rotate, flip or remove parts to expose dust before cleaning it.
- Pointer release, Escape and window focus loss pause active screw turns. Tool/cable/inspection changes are blocked during active service animations.
- Screwdriver, blowers and cleaning jingles share a sound toggle; see [asset credits](ASSET_CREDITS.md).
- **Repair status overlay** (debug builds, developer aid): expand **Escape → Dust & diagnostics** and switch on **Repair status overlay**; the choice is remembered. It lists the Job (including the rolled faults the customer only hints at), then Dust, Thermal paste, Fan bearing, Assembly and the live Test run readout, each red (broken or untouched), yellow (in progress) or green (done), with hidden truth such as paste contact percentage. It stays visible during play and above focus views.
- **Repair speeds (debug)**: expand **Escape → Repair speeds** and adjust **Dust clearing**, **IPA wiping**, or **Paste scraping**. Each multiplier ranges from 0.1x to 20x; 1x is the original speed and higher values remove material faster. Changes apply immediately and persist in `user://bench_repair_speeds.cfg`. **Reset repair speeds to 1x** restores the baseline. Dust affects both blowers; IPA affects paste residue and fan-shaft gunk. Brush sizes, scrape-before-wipe rules and paste application stay the same. Release builds always use the original rates. Automated fixtures start at 1x regardless of saved play tuning.
- **Sound mix**: expand **Escape → Sound** for a Master slider and one slider per sound (fan quiet/loud loops, bearing grind, air blower motor, Dev blower air, screwdriver, clean jingle, GPU seating, monitor button, racing game, sticker peel, spudger scrape, IPA wipe, shop PC keys and mouse), from silent to 200%. Changes apply live. Run from the editor, they save into `default_bus_layout.tres`, so they can be committed and are also editable in the editor's bottom **Audio** tab; exported builds save them to user settings.
- Service-rule evaluator, exercised against 1,024 checked-in expected decisions and used by the live cable/screw controller.

## Controls

| Action | Control |
| --- | --- |
| Walk / look | WASD / mouse; no third-person view or camera presets |
| Release/resume mouse | Tab or Escape; releasing also ends screw/blower holds |
| Interact / pick up | Aim the crosshair and press E (or click); move within reach |
| Shop computer | E or click on the beige PC by the front wall (screen, cabinet or keyboard). The camera settles on the CRT and the cursor is freed: click tabs and buttons on the screen, or press F1 / F2 / F3 for the job board, bench and ledger. Esc or Tab steps away. Set held parts down first. Sitting down types a quick burst on the clacky keyboard; page keys and stepping away clack too, and every mouse press and release clicks (recorded CC0 sounds, see [asset credits](ASSET_CREDITS.md)). |
| Open the delivery box | E or click on the box on the repair desk; the card lifts out into its holder |
| Return a card | Portal **My bench** tab: **Return card to customer**. The card must be reassembled with its fan cable connected and set down. |
| Inspect GPU | E on the card, including with a tool equipped; RMB + mouse rotates, F flips, wheel adjusts holding distance. With a part held, R opens focus; E on the mat places that part and keeps the equipped tool. |
| Place / return held card | GPU and detached parts sit in the left hand. Aim at the desk: a green ring marks a clear placement and red marks a blocked spot. E places the part while keeping your tool; Q returns the carried card to its repair holder. |
| Carry GPU to testing | With an assembled GPU and empty tool hand, E on the test board; a held card transfers directly |
| Remove tested card | E on the installed card or board; it returns to the holder |
| Wiggle test | Aim at the seated card, hold LMB and move the mouse side to side: the card rocks in its slot (the view stays put). Watch the monitor for dropouts. |
| Loupe | Take the loupe from the tool roll and click the GPU: focus opens on the gold fingers under a round lens. Click a spot to centre and double the magnification; the wheel zooms much deeper than other tools allow. |
| Monitor power | E on its physical button; monitor power does not disconnect board power |
| Switch tool (anywhere) | **T**: opens the tool bag from anywhere, including while holding a part or inside a service close-up. Pick a tool (or Empty hands) and you return to where you were; from a close-up it reopens on the same part, framed for the new tool. T or Esc closes the bag. |
| Select / switch tool | Click the tool bag or press E on it; wait for it to unroll, then click a tool or select its label with arrow keys + Enter. Esc rolls it closed. |
| Open GPU service window | With screwdriver, a blower or a paste tool equipped, click the GPU/backplate, screw or empty seat. E picks up the GPU instead; R while holding it opens focus. The room blurs behind the sharp GPU. RMB drag rotates the view; wheel zooms; Flip part reveals the other side. Click Return tool to put the tool away without closing focus. Esc closes. |
| Turn/refit screw | In the service window, hold LMB on a screw or empty seat. A refit screw seats immediately; holding turns it, releasing pauses. |
| Connect fan cable | With empty tool hand, E on plug/socket/wire |
| Lift assembly | E on fan/heatsink after removing its cable/screw dependencies |
| Rotate / place / refit assembly | RMB + mouse / E on clear repair tabletop / Q; cooler refits before fan |
| Clean dust | Equip the air blower, click a part for focus, hold LMB and sweep the jet over exposed surfaces; remove assemblies to reach internal dust. Debug builds also have the wide-footprint Dev blower. |
| Thermal camera | Boxed in play for now. When unboxed: E on the orange camera on the repair desk; hold RMB for its larger viewfinder |
| Repaste | With the heatsink removed, equip spudger / IPA wipe / paste syringe and click the GPU or detached heatsink. Hold LMB on the framed die or base to scrape, wipe or squeeze. See [Repasting](#repasting). |
| Oil the fan bearing | In focus on the detached fan: click the hub sticker, then the hub to pull the rotor. Hold LMB along the shaft with the IPA wipe, then on the bearing with the fan oiler. Click the rotor to refit it. See [Fan bearing](#fan-bearing). |
| Place / retrieve a tool | E on clear repair tabletop / E on placed tool |
| Return equipped tool | Q, also inside a service close-up (the part stays in hand and the close-up stays open). With a part in one hand and a tool in the other, Q returns the tool first; press Q again to return or refit the part. The thermal camera returns to its desk stand, other tools to the toolbox. |
| Debug clean/disassemble and dust highlight | Tab to release mouse and open the debug cleaning menu |
| Toggle sound | M |

This controller targets desktop keyboard/mouse. The centred ray is depth-tested:
hidden screws and memory cannot be picked through another surface. Most room props
are fixed scenery; the GPU, service assemblies and three tools are the supported
pickup objects. There is no jumping or free physics throwing.

## Repair jobs

Play opens on an empty bench with **$100**. The loop:

1. **Take a job.** Walk to the shop computer, a beige 486 with a green-phosphor CRT on
   the desk by the front wall, and click its screen. The internal **BENCHWORKS REPAIR-NET**
   portal has three pages (F1-F3): **Job board** (open
   requests: customer, complaint in their own words, and pay), **My bench** (the
   accepted card, its status and the return button) and **Ledger** (balance and
   returned jobs). **Accept job** puts the request on your bench.
2. **Unbox it.** A branded retail box drops onto the repair desk, between the card holder
   and the screw tray. One click breaks the seal, opens the hinged lid and lifts the
   card out of its foam cradle and silver anti-static sleeve into the holder. The open,
   empty package slides to a clear spot beside the mat and stays until the job is returned.
3. **Diagnose and repair** with the existing tools. The complaint describes symptoms
   only. Runs hot, roars and shows coloured sparkles: dust. Slows down after warming
   up, with no artifacts: dried paste. Grinding: the fan bearing.
4. **Return it** from **My bench** once it is reassembled, with its fan cable
   connected, and set down. The courier takes it. If nothing is wrong with the card,
   the customer pays the listed amount. Otherwise they report what is still wrong
   and pay nothing. This includes problems you caused, such as refitting the
   heatsink over too little paste.

The bench holds **one card** at a time (`MAX_QUEUE` in `scripts/repair_jobs.gd`). The
**job-queue display**, on a stand behind the repair desk, shows each slot with its
customer, branded model, pay, status (in the box / on the bench) and complaint, plus the balance and
the last result.

Jobs choose brands from a shuffled bag of Lotac, Vsus and CSI, so the board starts with
one of each. Brand palettes are fixed: another Lotac card always uses the same complete
scheme. Brand changes recolour the PCB, housing, blades, hub, screw heads, chips,
capacitors, cable and heatsink; gold contacts and repair residue keep their diagnostic colours.

**How many faults a card has.** With *n* fault types (three for now: dust, dried paste,
dry bearing), a card has *k* faults with probability

P(k) = (1 − r) · r^(k−1) / (1 − r^n),  for k = 1 … n,

so each extra fault is *r* times as likely as one fewer. Choosing
r = (1 + √37) / 18 ≈ 0.3935 puts three faults at exactly 10 in 100:

| Faults | 1 | 2 | 3 |
| --- | --- | --- | --- |
| Chance | 64.6% | 25.4% | 10.0% |

Which faults is uniform. Adding a fault type keeps the same *r*, so many-fault cards
get rarer still (with four types: 62.1 / 24.5 / 9.6 / 3.8%). Every card has at least
one fault, and everything not rolled starts healthy: clean, freshly pasted, oiled.
Pay is a $20 diagnosis fee plus $40 for dust, $60 for paste and $45 for the bearing.
Progress lives in memory only; there is no save yet. Spending money, more bench
slots and unlocking the boxed thermal camera are not implemented yet.

## Thermal investigation loop

Seat the dirty, assembled GPU in the test board and give it about 6 seconds to
warm. While the thermal camera is boxed, read the monitor's **GPU °C**, MHZ and
artifacts. With the camera unboxed (automated fixtures), take the orange thermal camera and walk around to the exposed rear VRAM
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
hardware-specific safe limits are not simulated. Bad pads and electrical faults are
not implemented. Fan sound still follows cleaning progress. The racing feed follows the model:
the core clock (and so FPS) drops from 70 degrees C, and VRAM above 80 degrees C shows memory
errors that are fully visible by 92 degrees C.

### Dried die paste

A card can arrive with dried thermal paste between the GPU die and heatsink. The
die sits under the heatsink, so the thermal camera cannot see it; its sensor reading
appears as **GPU °C** on the powered test monitor. Compare that reading with the
heatsink on the thermal camera. Dust heats both. Dried paste traps heat in the die,
so the core runs hot (throttling at 105 degrees C) while the heatsink stays *cooler*
than healthy. Model targets with clean parts are core 53 / heatsink 38 degrees C with
fresh paste, and about 80 / 33 with dried paste. VRAM heat is unaffected by paste, so
a paste fault throttles the racing feed (lower MHZ/FPS) without memory errors, while
dust near the VRAM adds artifacts.
Debug builds have **Dry paste** and **Fresh paste** under **Escape → Fault setup**.

### Repasting

Remove the heatsink (cable, fan screws, fan, cooler screws). The die is under the
heatsink, and the old compound is split between the die and the heatsink base.

The old compound is uneven, like real pumped-out paste. It is thin in the middle,
ridged toward the die edges and lumpy, with fissures and torn peaks where the
heatsink pulled it apart; the base carries the matching half. Each spot is a stack
of layers:

- **Glaze**: a hard, darker skin, thickest on the dried-out rim. It resists the
  blade until you get under an exposed edge (a gap, fissure or the die edge), then
  chips away quickly in small grey flakes.
- **Crust**: the chalky dried body, pared down steadily.
- **Gum**: a pasty, glossy base, wettest in the middle. The blade lifts some and
  ploughs the rest ahead of the stroke, so push it off the face rather than back
  and forth. Held still, it spreads outward.
- **Film**: the residue under everything.

Both surfaces need the same two stages:

1. **Spudger** (plastic): click the GPU or the detached heatsink to open focus. The
   view frames the exposed contact face. Hold and drag to work down the stack;
   thick ridges take several strokes. A grey film and a few gum smears stay behind.
2. **IPA wipe**: hold and rub to lift the film and dissolve leftover gum. Alcohol
   only smears glaze and crust, so scrape first. At about 95% the face clears with
   a jingle.
3. **Paste syringe** (die only): hold to squeeze. The bead grows while you hold;
   drag to lay a line. Dot, line or X patterns come from how you move. The bar is
   the amount squeezed; half-full is one full die of paste.
4. Refit the heatsink. It presses the paste: the bond line over the die fills
   outward from where you placed paste, and excess squeezes onto the package.
5. Optionally lift the heatsink again for a **lift test**. The imprint splits between
   the die and base and the status reports contact, dry patches or squeeze-out.
   Refitting presses the paste again, and the IPA wipe can remove squeeze-out.

**Feedback while working.** In focus, the equipped tool is drawn on the face under the
pointer: hovering, it floats just above; holding LMB presses it down. Each press is one
stroke. Right after pressing, the blade is still being aimed: circle the mouse near where
you pressed and it turns to point from that spot toward the pointer. Once the pointer moves
about three paste cells away, the heading locks until release, so the blade can follow a
curve but never turns around mid-stroke (moving back is ignored; release and press again
to scrape the other way). Gum is pushed along that heading. Pasty compound
beads along the blade's edge until a clump drops off, chalky crust crumbs get pushed off
ahead of it, and glaze throws grey chips. The IPA pad lies flat and turns grey as it
lifts film.

Sounds: drop a seamless loop at `assets/sounds/spudger_scrape.wav` and/or
`assets/sounds/ipa_wipe.wav` (16-bit PCM WAV). Each loops over its whole length while its
tool is on the face, louder with stroke speed and removal, fading out on release. Without
the file the tool is silent. Each has its own mixer slider (**Spudger scrape**, **IPA wipe**).

A single central dot of the right amount leaves the corners dry (about 92% contact).
An X of the same volume reaches them (about 95%). Too little paste leaves most of the
die dry, and a heatsink seated on a bare die with no paste is worse than the old
dried compound. Refitting over any paste state is allowed; the monitor's **GPU °C**
and the thermal camera show the result under load. Paste thickness, mounting pressure
and screw-tightening order are not modelled yet.

### Fan bearing

The 710's cheap sleeve-bearing fan can arrive dry and gummed up, so it grinds whenever it
spins on the test board (a synthesized placeholder until `assets/sounds/fan_grind.wav`
is supplied). The fix happens in focus on the detached fan:

1. **Peel the hub sticker**: click it (bare hands, spudger, IPA wipe or fan oiler). It
   peels slowly over the length of the supplied crackle recording (about 2 s).
2. **Pull the rotor**: click the hub. The rotor lifts out and rests face down beside the
   housing with its shaft up; the bearing boss and its three struts are exposed.
3. **IPA wipe** on the shaft: hold and drag along it. The wipe wraps round the thin
   shaft, so a stroke cleans every side; it clears with a jingle at about 95%.
4. **Fan oiler** (last tool-roll pocket) on the bearing: hold for drops, the first
   shortly after pressing and then one every 0.4 s. One or two drops is enough.
5. **Refit the rotor**: click it. The sticker presses back on with it. A clean, oiled
   bearing spins quietly; a skipped step leaves it grinding, and the notice says which.

The fan cannot be mounted while its rotor is out. A fan mounted with only its sticker
peeled gets the sticker pressed back on. Debug builds have **Dry bearing** and
**Oil bearing** under **Escape → Fault setup**. Worn (wobbly) bearings, over-oiling and fan replacement are
not modelled yet, and the bearing does not affect temperatures.

### Edge connector (diagnosis only, debug for now)

The card's PCIe edge connector can be damaged in three ways. There is no repair yet, so
the job board never rolls it; in debug builds **Escape → Fault setup → Cycle edge connector damage** cycles clean →
oxidised → lifted finger → torn finger → clean. Each has its own signature:

| Damage | Test monitor | Wiggle test | Under the loupe |
| --- | --- | --- | --- |
| Oxidised fingers | `PCIe x8`, capped at 34 FPS; the picture drops out at random (`LINK LOST`, then retrains) | Rocking makes dropouts far likelier | Patchy brown-green tarnish on a dozen fingers, both faces |
| Lifted finger | `PCIe x16`, normal | Rocking past a small angle cuts the picture until the card settles | One fan-side finger (contact 17) peels up at its tip |
| Torn finger | `PCIe x4`, capped at 18 FPS, steady | No change | Contact 24 is missing: a stub, bare fibreglass and a curl of trace |

The tell is **slow but cool**: a narrow link caps the frame rate while the core stays
cool at the full 1905 MHz, unlike dried paste (hot core, falling clock) or dust
(heat and memory artifacts). A card returned with connector damage is not paid. The
rocking card tilts about its connector line on a damped spring; the monitor goes blank
and silent while the link is down.

## Pending gameplay

Edge-connector repairs (cleaning, re-gluing, bodge wires) and rolling connector faults in jobs, paste thickness/mounting pressure, directional pad scraping, comparison view, spending and progression (purchases, more bench slots, unboxing the thermal camera, saving), volumetric dust (shell layers or detachable felt clumps), fan wear from overspinning and general interaction highlights are pending. Imported pad remnants are geometry only. Replacement pads have no gameplay yet. The racing feed simulates GPU performance; it does not measure actual rendering FPS or diagnose electrical faults.

No deployment workflow or export preset is configured.

## Where to edit

| File | Responsibility |
| --- | --- |
| `scenes/workbench.tscn` | Main composition, asset instances, camera, lighting, environment, and controller nodes. |
| `scenes/repair_desk.tscn` | Editable desk/mat/holder/tray and prop meshes. |
| `scripts/gpu_connector.gd`, `shaders/loupe_lens.gdshader` | Edge-connector damage (oxidised, lifted, torn) drawn on the imported gold contacts, PCIe link width, dropouts and retraining, debug cycle; the loupe's lens overlay. |
| `scenes/toolbox.tscn` | Instances the rounded tool scenes; tool_roll.gd builds the canvas bag, pockets, straps and rolling geometry and places tools from its `POCKETS` table. |
| `tools/import_tool_kit.gd`, `scenes/work_tool_shapes.tscn` | Bakes the Blender tool set into native scenes, preserving labels and the thermal display UV quad; includes the working scraper/wipe meshes used in close-up. |
| `scenes/screwdriver.tscn`, `tools/import_screwdriver.gd` | Rounded screwdriver mesh scene and Blender-to-native scene bake. Source: `models/screwdriver.blend`; intermediate: `assets/screwdriver.glb`. |
| `scenes/test_monitor.tscn`, `scripts/test_monitor.gd` | Editable LCD housing, power button, sound, deterministic pseudo-3D racing display driven by core clock and capped by PCIe link width, link-lost dropouts, VRAM error artifacts and GPU core sensor/clock readout. |
| `scripts/testing_station.gd` | PCIe fixture interaction, GPU transfer, rocking the seated card (wiggle test), monitor connection, signal cable, fan animation (powered or air-blown), cleanliness-driven fan audio and dry-bearing grind. |
| `scripts/gpu_bearing.gd`, `shaders/shaft_gunk.gdshader` | Fan sleeve bearing: runtime bearing boss, struts and shaft, hub-sticker peel, rotor pull/refit, shaft gunk wipe, oil drops and the dry/serviced state. |
| `scenes/shop_interior.tscn`, `scripts/shop_interior.gd` | Imported workshop shell and props, editor-visible layout conversion and cutaway visibility. |
| `scripts/workbench.gd` | Startup, controller wiring, input arbitration, desk alignment, placement obstacles and jaw motion. |
| `scripts/bench_closeup.gd`, `scripts/tool_roll.gd` | Live GPU/tool-bag viewing windows, isolated mesh proxies, mouse picking, orbit/zoom and segmented fabric animation. |
| `scripts/workbench_tools.gd` | Table-driven exclusive tool locations (`TOOLS`), roll/tool animations and placement guards. |
| `scripts/gpu_cleaning.gd`, `shaders/dust_overlay.gdshader`, `shaders/dust_highlight.gdshader` | Airflow-weighted dust thickness masks, lit felt shading, Dev blower spot and air blower jet cleaning, visible low-density residue, debug highlight, air loop, motor and per-part jingles. |
| `scripts/dust_puffs.gd`, `shaders/dust_puff.gdshader` | Pooled dust cloud and flakes lifted by the blowers, one MultiMesh shared with the focus view. |
| `scripts/held_part_pose.gd` | Shared left-hand framing for carried GPU and detached assemblies. |
| `scripts/gpu_service.gd` | Cable state/deformation, screw progress, assembly handling/placement, exact refit and screwdriver audio. |
| `scripts/interaction_picker.gd` | Cached triangle picking, live-transform tracking, depth-tested screw/plug targets, cleaning rays through fan-hub decoration, surface normals and action routing. |
| `scripts/first_person.gd` | Runtime walking body, collision generation, mouse capture/look and reach. `orbit_camera.gd` supplies only legacy test poses. |
| `scripts/gpu_thermal.gd` | Dust- and paste-dependent heating/cooling (about 6 s powered warm-up), core throttle limit and boost-clock bins, VRAM error rate, surface temperature/emissivity and VRAM markings. |
| `scripts/contact_loop.gd` | Plays a supplied loop (spudger scrape, IPA wipe) while its tool is on the face; silent without the file. |
| `scripts/gpu_paste.gd`, `shaders/paste_layer.gdshader` | Per-stroke contact report (sound, blade load, pad soil, crumbs and clumps); die and heatsink-base paste layers (uneven glaze/crust/gum stack, film and fresh paste per cell, with height relief), layered scrape with glaze chipping and gum smearing, wipe/squeeze brushes, pressure spread on seating, lift imprint, contact quality and debug dry/fresh. |
| `scripts/thermal_camera.gd`, `shaders/thermal_surface.gdshader`, `scenes/thermal_camera.tscn` | Pickup instrument, separate depth-tested thermal world, display, spot readout and fixed palette. |
| `scripts/gpu_inspection.gd` | Whole-GPU inspection state and exact home-transform restoration. |
| `scripts/repair_status.gd` | Debug-only repair status rows (job and rolled faults, dust, paste, bearing, assembly, test run) for the Escape-menu overlay. |
| `scripts/repair_jobs.gd` | Job offers, fault-count odds and rolling, complaints, the one-card queue, delivery and unboxing, per-job fault setup, return checks and payment. |
| `scenes/shop_computer.tscn`, `scripts/shop_computer.gd`, `shaders/crt_screen.gdshader` | Retro shop PC (CRT, beige 486 cabinet, keyboard, ball mouse); green-phosphor portal page in a SubViewport drawn through the curved CRT shader, camera settle and in-world click routing that follows the glass curvature. |
| `scenes/job_queue_monitor.tscn`, `scripts/job_queue_monitor.gd` | Job-queue display on a floor stand behind the repair desk. |
| `scripts/screen_ui.gd` | Shared helpers for pages drawn on in-world screens. |
| `scripts/delivery_box.gd` | Procedural carton (flaps, tape, label, foam cradle) for deliveries and the sealed thermal camera box. |
| `scripts/audio_mix.gd`, `default_bus_layout.tres` | Named mixer buses (one per sound plus Master), levels, reset and saving. |
| `scripts/hud.gd` | Native UI and signals; Escape menu with collapsible diagnostic, assembly, fault, speed and sound subpanels and bounded scrolling. Closeup provides the tool selection view, and workbench owns switching guards. |
| `scripts/asset_contract.gd` | Map source part names to imported nodes, validate parents, capture transforms. |
| `scripts/service_rules.gd` | Pure dependency/tool checks, plus `check_surface` for paste-face and bearing reach and tool choice, and `check_opening` for the fan's sticker/rotor order. Invalid graphs fail closed with errors. |
| `assets/gpu-parts.json` | Generated part metadata and source asset SHA-256 hashes. |
| `tools/sync_assets.py` | Copies Blender GLBs and extracts part metadata using Python standard library. |
| `tests/fixtures/service-rules.json` | Checked-in expected service decisions; no generation step or external toolchain. |
| `tests/smoke.gd` | Rule parity, malformed graphs, metadata/hierarchy, picking, camera, inspection, test-board/monitor flow, randomized dust coverage, fan mask orientation/hub cleaning, mounted-fan dust reachability, per-part completion and debug shortcut checks. |
| `tests/air_blower_flow.gd` | Dust deposition and thickness, air blower from the bag, narrow jet, sweep cleaning, dust cloud, motor wind-up/coast, air-spun fan grind and coast-down. |
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
& $godotExe --headless --path godot --script res://tests/tool_art_flow.gd
& $godotExe --headless --path godot --script res://tests/closeup_flow.gd
& $godotExe --headless --path godot --script res://tests/placement_flow.gd
& $godotExe --headless --path godot --script res://tests/tool_inspection_flow.gd
& $godotExe --headless --path godot --script res://tests/part_focus_flow.gd
& $godotExe --headless --path godot --script res://tests/staged_disassembly_flow.gd
& $godotExe --headless --path godot --script res://tests/repaste_flow.gd
& $godotExe --headless --path godot --script res://tests/fan_bearing_flow.gd
& $godotExe --headless --path godot --script res://tests/audio_mix_flow.gd
& $godotExe --headless --path godot --script res://tests/repair_status_flow.gd
& $godotExe --headless --path godot --script res://tests/repair_speed_flow.gd
& $godotExe --headless --path godot --script res://tests/tool_hotkey_flow.gd
& $godotExe --headless --path godot --script res://tests/air_blower_flow.gd
& $godotExe --headless --path godot --script res://tests/repair_jobs_flow.gd
& $godotExe --headless --path godot --script res://tests/gpu_brand_flow.gd
& $godotExe --headless --path godot --script res://tests/edge_connector_flow.gd

# Run the game, or open the editor.
& $godotExe --path godot
& $godotExe --editor --path godot
```

The first-person flow checks walking/collision, mouse release, proximity and pickup/return. The thermal flow checks physical camera pickup, placement, exclusivity, occlusion, internal cleaning under equal load, the dried-paste core/heatsink gap, the monitor's core readout, debug repaste and cooldown; append `-- --capture` without `--headless` for player/dirty/clean thermal PNGs. The repaste flow checks paste reach rules, tool exclusivity, scrape-then-wipe on both faces, the squeeze rate, seat spread, lift imprint and dot/X/scant/flood coverage, and prints the measured pattern contact and spread time. With `-- --capture` it writes `paste-*.png` for each stage.

Optional legacy rendered acceptance run: append `-- --capture` to the test command and omit `--headless`. It runs the same checks, writes repair/overview/front/back/service-tray, screw-hole and testing-monitor PNGs to ignored `build/`, then exits. Service tests tick hold progress explicitly for reproducibility and run real tool/cable/tray animations. The automated tests do not certify audible sound quality; check that manually.

The next gameplay milestone is paste thickness/mounting pressure, pad-residue scraping and the remaining cleaning/job controls.

The GPU uses a 0.25 scene scale (about 30 cm wide at the room's five units per
meter). Inspection, rotation, detached assemblies, tray screws and test-board
attachment preserve that physical scale. The holder is resized to fit and aligned beneath the GPU near the front of the mat. The test
desk footprint is 25% smaller, and the test board is resized independently;
the desk height and monitor size stay unchanged. `scale_toolbox_flow.gd -- --capture`
also captures the holder, held card, test station and tool bag (open and unrolling) under `build/`. `closeup_flow.gd -- --capture` adds enlarged front/rear GPU views and verifies real GUI mouse routing; headless runs exercise the same picking/controller actions directly.

Tool-roll visual reference: [Ergodyne Arsenal roll-up organizer](https://www.ergodyne.com/arsenal-5874-roll-up-tool-bag-zipper-pockets) (pockets, webbing and cinch straps). Geometry is native procedural Godot geometry; no product imagery is bundled.
