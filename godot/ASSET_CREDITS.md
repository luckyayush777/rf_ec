# Asset credits

`assets/manual-screwdriver.wav` is the repository's mono, 22.05 kHz adaptation of **“Screwdriver, Ratchet, A” by InspectorJ**, licensed under **Creative Commons Attribution 4.0**.

- Original recording: https://freesound.org/s/393492/
- License: https://creativecommons.org/licenses/by/4.0/
- Original recording and existing attribution notes: `../sounds/screwdriver/`.

Keep this attribution with distributed builds. GPU and testing-desk assets are copied from this repository's Blender workflow; their editable sources and authoring notes remain under `../models/`.

`assets/cleaning-complete.ogg` is **Win Jingle by Fupi**, licensed CC0. It remains a synced reference asset; the current Godot cleaning cue uses the supplied `clean_jingle.wav` below. The source MIDI is kept at `../sounds/winjingle-source.mid`.

- Source: https://opengameart.org/content/win-jingle

`assets/sounds/compressed_air.wav` and `assets/sounds/clean_jingle.wav` were supplied for this Godot port. The former plays during the Dev blower hold; the latter plays when each part becomes clean.

`assets/sounds/gpu_sounds/gpu_attach_short.wav` and `assets/button_press.ogg` were supplied for the testing station. They play when the GPU seats in the test board and when the monitor is turned on.

`assets/sounds/ambient_gpu.wav` and `assets/sounds/loud_gpu.wav` were supplied for GPU fan audio. The testing station loops their sustained middle sections and blends them according to remaining dust.

`assets/shop-interior.glb` is the repository-authored workshop, exported from `models/shop-interior.blend`. Visual references and export instructions are recorded in `models/shop-interior.md`; no third-party model or photo textures are embedded.
