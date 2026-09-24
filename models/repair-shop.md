# Primitive repair shop model

Open `repair-shop.blend` in Blender to edit the workbench. The scene has two top-level collections:

- `Repair Shop`: desk, ESD mat, parts tray, power supply, and lamp.
- `GPU Testing Board`: a separate board with a PCIe x16 slot, 8-pin power socket, test button, and status light.

`repair-shop.glb` contains both collections for a complete scene. `gpu-test-board.glb` contains only the testing board, exported from its `gpu-testing-board` root object. The connectors are visual placeholders; no electrical testing or GPU insertion behavior is implemented.

The browser builds the original repair desk in `src/workbench.ts` and loads `repair-shop.glb` beside it through `src/load-testing-desk.ts`. The second desk and board are visual props; the separate `gpu-test-board.glb` is available for future interactions.

After editing `repair-shop.blend`, export the `repair-shop` and `gpu-testing-board` root objects together to `repair-shop.glb`. The existing `npm run model:export` command only exports `models/gpu.blend`, so it does not update these repair-shop assets.
