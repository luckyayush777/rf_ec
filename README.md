# BENCH — GPU study

A browser repair desk with a simplified GPU, a work light, and an interactive toolbox containing a screwdriver. Built with TypeScript, Three.js, and Vite, with an editable Blender asset workflow.

## Run

```sh
cd /Users/ayushkumar/ayush.dev/repair_shop
npm install
npm run dev -- --port 5173
```

Open **http://127.0.0.1:5173/** (or the URL printed by Vite if that port is occupied). Leave the terminal running; Ctrl+C stops the server. Node.js 22.12+ or 24 and a browser with WebGL 2 are required. The existing GLB is included, so Blender is not needed to run the game.

- Drag to orbit, scroll or pinch to zoom, and use the camera buttons to switch views or reset.
- Click the box labeled **TOOLBOX** to open or close its hinged lid.
- With the lid open, click the screwdriver to pick it up.
- **Currently equipped** shows the active tool (or empty hands). **Equip screwdriver** opens the toolbox and retrieves the tool, including while inspecting the GPU. GPU inspection works with the screwdriver equipped; handling cables and detached assemblies requires empty hands.
- While holding it, click a clear place on the tabletop or mat to set it down; click it again to pick it up.
- Click the open toolbox, press **Esc**, or use **Return screwdriver** to put it back. A closed toolbox opens when using Esc or the return button.
- Hover over a screw, connector, fan, or other interactive part to highlight its surface. The desk includes a large blue electronics mat and a parts tray with separate fan and cooler screw rows.
- Click the GPU to lift it for inspection. Drag to rotate the held GPU independently of the camera; press **Esc** or **Set GPU down** to return it to the mat.
- Click the fan cable or plug to unplug it from the board; click again to reconnect. **Unplug cable / Reconnect cable** is also available while inspecting.
- Pick up the screwdriver and hold each of the four top fan screws until it reaches the labeled tray. Release to pause and hold again to continue. Set the screwdriver down or return it, then click the fan or **Lift fan**.
- Click a clear spot on the enlarged desk to place the detached fan and cable. Click the fan to pick it up again; use **Refit fan** or Esc while carrying it to seat it on its mounting posts. With the screwdriver, hold each removed screw in the tray to reinstall it, then reconnect the cable.
- To remove the complete cooler, unplug the cable, pick up the screwdriver, use **Inspect GPU**, and drag to expose its four rear screws. Remove them, return the tool, then click the heatsink to lift the cooler. Place and refit it the same way. If both assemblies are detached, refit the cooler before the fan.
- The cable stays attached to the fan throughout. Placement checks keep complete parts on the desk and away from other objects. Screws can only be refitted after their assembly is seated; the cable can only reconnect with both assemblies seated.
- The top-right counter shows actual rendered FPS. **Sound on / Sound off** toggles the mechanical effects, including the toolbox latch and hinge. Audio starts after your first interaction.

To test a production build:

```sh
npm run build
npm run preview -- --port 4173
```

Open **http://127.0.0.1:4173/**. The production site is in `dist/` and can be hosted statically; `preview` is a local preview server.

## Model

Use `npm run model:build` to generate `models/gpu.blend` and the browser asset `src/assets/gpu.glb`. Edit and save the `.blend` file in Blender, then run `npm run model:export` to update the viewer without rebuilding your model. Blender 4.5 LTS or newer is required for these commands.

See [the Blender workflow](models/README.md) for setup, editable parts, and export instructions. The generator protects an existing `.blend` from accidental regeneration.

`src/load-gpu.ts` loads the exported GLB when present. `src/gpu.ts` supplies the original procedural fallback when no asset has been generated. Both use separate named parts: board, connector, bracket, heatsink, fan housing, rotor, cable, plug, socket, and individual fasteners. Dimensions are illustrative and do not reproduce a particular GPU.

Each logical part has `userData.part` metadata recording its role and assembled local position. Removable parts additionally record a removal direction and, where applicable, dependency names. The fan cable is attached to the fan assembly; its board-side plug must be disconnected before the cooler can move.

Fan removal order: unplug fan cable → remove four top fan screws → lift fan and cable → place on the desk. The fan screws engage bored metal posts fixed to the heatsink. The cooler can also be detached after removing its four rear screws. Reassembly reverses these steps; every part restores its original local transform.

`src/main.ts` owns scene lighting, camera presets, and the FPS counter. Rendering runs continuously while the tab is visible and pauses in the background. `src/workbench.ts` builds the desk, lamp, toolbox, and screwdriver. `src/interactions.ts` handles picking, equipped-tool state, lid animation, and tool placement; `src/gpu-inspection.ts` handles GPU rotation and cable detachment. `src/gpu-repair.ts` manages fasteners, assembly removal, placement, and refitting; `src/service-rules.ts` checks service dependencies. `src/interaction-highlight.ts` highlights the selected part's materials. `src/sound.ts` synthesizes short mechanical effects locally with Web Audio. `src/style.css` styles the viewer. The interface optionally loads Google Fonts with local font fallbacks.

Service order comes from each assembly's `requires` metadata in the GPU model. The rule evaluator checks removal requirements, derives screw and cable refit requirements from that relationship, and uses the original parent hierarchy to require the cooler before the fan. The cooler screw cable prerequisite is declared once in `src/service-rules.ts`; it applies to every fastener listed by the cooler assembly. The controller discovers assemblies and fasteners from their model roles, so adding a screw to an assembly's `requires` list also includes it in the count and service checks. Run `npm test` after changing service metadata or rules. Animation and placement guards stay with their interaction controllers.
