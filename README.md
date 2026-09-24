# BENCH — GPU study

A browser repair desk with a simplified GPU, a work light, and an interactive toolbox containing a screwdriver. Built with TypeScript, Three.js, and Vite, with an editable Blender asset workflow.

## Cleaning with the toolbox

The app opens on the repair workbench. The air blower is a physical toolbox tool alongside the screwdriver; **Equip blower** also retrieves it from the box. Equipping one tool puts the other away.

When running the local development server, the larger purple **Dev blover** appears in the toolbox and equipment panel. It uses 20 times the regular blower's cleaning rate and a wider air stream. It follows the same equip, place, return, and service rules. Production builds hide this developer tool.

- Hold and sweep over the GPU or a detached part to blow away dust. On touch screens the aim point sits above your finger.
- Remove the fan or cooler with the existing service steps, then clean it while held or after placing it on the desk. Dust stays attached to its own mesh through removal, rotation, storage, and refitting.
- With a part held, drag with empty hands to rotate it. With the blower equipped, right-drag on desktop or use two fingers on touch screens to turn it; pinch/scroll zooms. **Flip held item** exposes the other side.
- Return the blower before placing, storing, refitting, or handling the cable. The blower cannot turn screws. Stored parts can be picked up again without refitting them first.
- Removing the fan exposes dust on the fin tops underneath it; removing the cooler exposes the populated PCB. Fan, cooler, PCB and screw heads keep independent cleaning state.
- Expand **Cleaning** in the equipment panel for per-part progress and **Compare before**. Reaching 99% clears the final traces of dust, shows 100%, and plays a short success jingle when sound is on. At 90% overall cleanliness, refit the parts and reconnect the cable to **Finish service**. **Next card** resets dust once everything is assembled.

This is a feedback prototype: jobs and cleaning progress live in memory, cards reuse the same fictional model, and replacement pads are not implemented. Fine dust uses small per-part surface masks, buildup uses removable clumps, and the blower has a bounded particle pool and synthesized air sound. Front and back masks are independent.

The card now starts with lighter amber dust and worn thermal-pad remnants on its four memory chips. The Cleaning panel names the surface with the most dust left. A low-profile PCB holder grips the card's edges on the mat; its jaws open while the GPU is lifted and close when it returns. Remove the cooler, set the GPU back in the holder, equip the plastic scraper from the toolbox, start in the band between two concentric rectangles on a remnant, and drag toward the opposite edge. Each pass erases a strip under the scraper; repeat across the pad. Untouched areas stay in place, and the active remnant glows light red. Scraper drags do not rotate the GPU. The separate cleaning-alcohol bottle and empty spare-parts box are on the right side of the desk. Replacement supplies will be added in a later stage.

The Blender source includes a populated PCB, rear silkscreen, and simplified DVI/HDMI connector faces. Fixed detail is batched at load time to reduce draw calls while remaining individually editable in Blender. It is an approximate 710-inspired card, not a reference-matched GT 710.

## Run

```sh
cd /Users/ayushkumar/ayush.dev/repair_shop
npm install
npm run dev -- --port 5173
```

Open **http://127.0.0.1:5173/** (or the URL printed by Vite if that port is occupied). Leave the terminal running; Ctrl+C stops the server. Node.js 22.12+ or 24 and a browser with WebGL 2 are required. The existing GLB is included, so Blender is not needed to run the game.

Workbench controls:

- Drag to orbit, scroll or pinch to zoom, and use the camera buttons to switch views or reset.
- Click the box labeled **TOOLBOX** to open or close its hinged lid.
- With the lid open, click the screwdriver to pick it up.
- **Currently equipped** shows the active tool (or empty hands). **Equip screwdriver** opens the toolbox and retrieves the tool, including while inspecting the GPU. GPU inspection works with the screwdriver equipped; handling cables and detached assemblies requires empty hands.
- While holding it, click a clear place on the tabletop or mat to set it down; click it again to pick it up.
- Click the open toolbox, press **Esc**, or use **Return screwdriver** to put it back. A closed toolbox opens when using Esc or the return button.
- Hover over a screw, connector, fan, or other interactive part to highlight its surface. The desk includes a large blue electronics mat and a parts tray with separate fan and cooler screw rows.
- With a mouse, drag to orbit, roll the wheel to zoom, or hold the wheel button and drag to pan the camera across the bench.
- Click the GPU to lift it for inspection. Drag to rotate the held GPU independently of the camera; press **Esc** or **Set GPU down** to return it to the mat.
- Click the fan cable or plug to unplug it from the board; click again to reconnect. **Unplug cable / Reconnect cable** is also available while inspecting.
- Pick up the screwdriver and hold each of the four top fan screws until it reaches the labeled tray. Release to pause and hold again to continue. Set the screwdriver down or return it, then click the fan or **Lift fan**.
- Click a clear spot on the enlarged desk to place the detached fan and cable. Click the fan to pick it up again; use **Refit fan** or Esc while carrying it to seat it on its mounting posts. With the screwdriver, hold each removed screw in the tray to reinstall it, then reconnect the cable.
- On a small screen, tap **Focus GPU** to hide the workbench and zoom in on the card. Pinch to zoom closer and move two fingers to pan toward a screw. Tap **Inspect GPU** to rotate it for rear screws; pinch and pan still work while it is held. After lifting a fan or cooler, tap **Store part** to set it aside without finding room on the desk; **Refit fan/cooler** brings it back. With the screwdriver equipped, hold **Refit screw** to reinstall a stored screw. **Exit focus** returns to the desk.
- With a mouse outside focus mode, hover over the mat or tabletop while carrying a detached assembly. A green footprint shows where it will land when clicked; red means that spot is blocked or too close to the edge.
- To remove the complete cooler, unplug the cable, pick up the screwdriver, use **Inspect GPU**, and drag to expose its four rear screws. Remove them, return the tool, then click the heatsink to lift the cooler. Place and refit it the same way. If both assemblies are detached, refit the cooler before the fan.
- The cable stays attached to the fan throughout. Placement checks keep complete parts on the desk and away from other objects. Screws can only be refitted after their assembly is seated; the cable can only reconnect with both assemblies seated.
- The top-right counter shows actual rendered FPS. **Sound on / Sound off** toggles the mechanical effects, including the toolbox latch and hinge. Audio starts after your first interaction.

To test a production build:

```sh
npm run build
npm run preview -- --port 4173
```

Open **http://127.0.0.1:4173/**. The production site is in `dist/` and can be hosted statically; `preview` is a local preview server.

## Share a browser version with testers

The repository includes a GitHub Actions workflow that builds and publishes the app to GitHub Pages. Your friends only need the HTTPS link and a phone browser with WebGL 2. There is no app installation, account, or backend setup.

1. In the [rf_ec repository](https://github.com/luckyayush777/rf_ec), open **Settings → Pages** and set **Build and deployment → Source** to **GitHub Actions**.
2. Commit the changes and push `main` to `origin`:

   ```sh
   git add README.md src/main.ts src/interactions.ts src/gpu-inspection.ts src/sound.ts src/assets/manual-screwdriver.wav sounds/screwdriver/manual.wav sounds/screwdriver/_readme_and_license.txt
   git commit -m "Improve phone screw controls and sound"
   git push origin main
   ```

3. Watch **Actions → Deploy to GitHub Pages** for a successful run. Then open `https://luckyayush777.github.io/rf_ec/` on your phone and share that link. GitHub also shows the live address under **Settings → Pages**. Later pushes to `main` publish updates automatically.

The workflow runs `npm ci`, tests, and a production build with the `/rf_ec/` asset path. The built files in `dist/` are the only files published. [Vite's GitHub Pages guide](https://vite.dev/guide/static-deploy#github-pages) explains the required path, and [GitHub's Pages setup guide](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site) covers the repository setting.

To check that exact build locally before pushing, run `npm run build -- --base /rf_ec/` and then `npm run preview -- --base /rf_ec/`. Open the `/rf_ec/` URL Vite prints. The build and preview base paths must match.

GitHub Pages sites are publicly accessible. On GitHub Free, the repository must also be public to use Pages. If you want to keep the repository private on that plan, import it into Netlify instead: use `npm run build` as the build command and `dist` as the publish directory, then share the HTTPS URL Netlify gives you. The GitHub Pages workflow's `/rf_ec/` path applies only to its own build. See [Vite's Netlify instructions](https://vite.dev/guide/static-deploy#netlify).

Before sending the link around, check one Android and one iPhone browser if available: load the scene, tap **Inspect GPU**, open the toolbox, equip the screwdriver, rotate and zoom, and turn sound on or off. Ask testers what they tried first and where they got stuck. The app does not currently collect analytics or feedback automatically.

## Model

Use `npm run model:build` to generate `models/gpu.blend` and the browser asset `src/assets/gpu.glb`. Edit and save the `.blend` file in Blender, then run `npm run model:export` to update the viewer without rebuilding your model. Blender 4.5 LTS or newer is required for these commands.

See [the Blender workflow](models/README.md) for setup, editable parts, and export instructions. The generator protects an existing `.blend` from accidental regeneration.

`src/load-gpu.ts` loads the exported GLB when present. `src/gpu.ts` supplies the original procedural fallback when no asset has been generated. Both use separate named parts: board, connector, bracket, heatsink, fan housing, rotor, cable, plug, socket, and individual fasteners. Dimensions are illustrative and do not reproduce a particular GPU.

Each logical part has `userData.part` metadata recording its role and assembled local position. Removable parts additionally record a removal direction and, where applicable, dependency names. The fan cable is attached to the fan assembly; its board-side plug must be disconnected before the cooler can move.

Fan removal order: unplug fan cable → remove four top fan screws → lift fan and cable → place on the desk. The fan screws engage bored metal posts fixed to the heatsink. The cooler can also be detached after removing its four rear screws. Reassembly reverses these steps; every part restores its original local transform.

`src/main.ts` owns scene lighting, camera presets, and the FPS counter. Rendering runs continuously while the tab is visible and pauses in the background. `src/workbench.ts` builds the desk, lamp, toolbox, and screwdriver. `src/interactions.ts` handles picking, equipped-tool state, lid animation, and tool placement; `src/gpu-inspection.ts` handles GPU rotation, close-up gestures, and cable detachment. `src/gpu-repair.ts` manages fasteners, assembly removal, placement, and refitting; `src/service-rules.ts` checks service dependencies. `src/interaction-highlight.ts` highlights hovered parts for mouse users. `src/sound.ts` plays the manual screwdriver recording, the cleaning completion jingle, and synthesized mechanical effects. `src/style.css` styles the viewer. The interface optionally loads Google Fonts with local font fallbacks.

The cleaning completion sound is [Win Jingle by Fupi](https://opengameart.org/content/win-jingle), licensed CC0. The bundled OGG plays at a faster rate for a brief cue; the source MIDI is kept in `sounds/` for reference.

Screwdriver audio: [“Screwdriver, Ratchet, A” by InspectorJ](https://freesound.org/s/393492/), licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The browser copy was downmixed to mono and resampled to 22.05 kHz from the original WAV in `sounds/screwdriver/manual.wav`.

Service order comes from each assembly's `requires` metadata in the GPU model. The rule evaluator checks removal requirements, derives screw and cable refit requirements from that relationship, and uses the original parent hierarchy to require the cooler before the fan. The cooler screw cable prerequisite is declared once in `src/service-rules.ts`; it applies to every fastener listed by the cooler assembly. The controller discovers assemblies and fasteners from their model roles, so adding a screw to an assembly's `requires` list also includes it in the count and service checks. Run `npm test` after changing service metadata or rules. Animation and placement guards stay with their interaction controllers.
