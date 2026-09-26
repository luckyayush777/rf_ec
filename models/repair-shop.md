# Primitive repair shop model

Open `repair-shop.blend` in Blender to edit the workbench. The scene has two top-level collections:

- `Repair Shop`: desk, ESD mat, parts tray, power supply, and lamp.
- `GPU Testing Board`: a separate board with a PCIe x16 slot, 8-pin power socket, test button, and status light.

`repair-shop.glb` contains both collections for a complete scene. `gpu-test-board.glb` contains only the testing board, exported from its `gpu-testing-board` root object. The connectors are visual placeholders; electrical diagnosis is not implemented.

Godot instances the full export in `godot/scenes/workbench.tscn`. `workbench.gd` aligns and sizes the desk and board; `testing_station.gd` handles GPU insertion, removal and testing. Electrical diagnosis is not implemented.

After editing `repair-shop.blend`, export the `repair-shop` and `gpu-testing-board` root objects together to `models/repair-shop.glb`, then run `python godot/tools/sync_assets.py`. The GPU exporter only exports the separate GPU model.
