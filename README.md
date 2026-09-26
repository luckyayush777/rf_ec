# BENCH

A first-person GPU repair game built with Godot 4.7.2, GDScript and the Compatibility renderer.

Open [godot/project.godot](godot/project.godot) in Godot and press **F5**. The included assets are ready to use; no Node, npm, TypeScript or Blender installation is needed to play.

Walk around the workshop, inspect and disassemble the GPU, select tools from the toolbox, clean internal dust, and compare surface heat with the thermal camera under test-board load.

- [Controls, implemented features and validation](godot/README.md)
- [GPU model authoring and export](models/README.md)
- [Testing desk](models/repair-shop.md) and [shop interior](models/shop-interior.md)
- [Asset credits](godot/ASSET_CREDITS.md)
- [Codebase navigation](AGENTS.md)

The runtime project is entirely under `godot/`. Blender sources and exports live in `models/`; Python authoring scripts live in `scripts/blender/`. Run `python godot/tools/sync_assets.py` after exporting model changes. Audio is maintained directly in `godot/assets/`.

There is no backend, save system or deployment workflow. Heat and FPS are gameplay simulations. See the Godot README for current limitations and test commands.
