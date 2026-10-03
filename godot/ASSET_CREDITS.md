# Asset credits

`assets/manual-screwdriver.wav` is the repository's mono, 22.05 kHz adaptation of **“Screwdriver, Ratchet, A” by InspectorJ**, licensed under **Creative Commons Attribution 4.0**.

- Original recording: https://freesound.org/s/393492/
- License: https://creativecommons.org/licenses/by/4.0/

Keep this attribution with distributed builds. GPU and testing-desk assets are copied from this repository's Blender workflow; their editable sources and authoring notes remain under `../models/`.

`assets/cleaning-complete.ogg` is **Win Jingle by Fupi**, licensed CC0. It remains a retained reference asset; the current Godot cleaning cue uses the supplied `clean_jingle.wav` below.

- Source: https://opengameart.org/content/win-jingle

`assets/sounds/compressed_air.wav` and `assets/sounds/clean_jingle.wav` were supplied for this Godot port. The former plays during the Dev blower hold; the latter plays when each part becomes clean.

`assets/sounds/gpu_sounds/gpu_attach_short.wav` and `assets/button_press.ogg` were supplied for the testing station. They play when the GPU seats in the test board and when the monitor is turned on.

`assets/sounds/gpu_sounds/sticker_peel_gpu_use.wav` was supplied for the fan-bearing service and plays while the hub sticker peels. The fan's dry-bearing grind is synthesized in code until a recording is supplied. The air blower's motor is likewise synthesized in `scripts/gpu_cleaning.gd` until `assets/sounds/air_blower.wav` is supplied, and its dust-cloud texture and the dust noise are generated at runtime. The racing test game's sound is synthesized live in `scripts/test_monitor.gd`.

`assets/sounds/ambient_gpu.wav` and `assets/sounds/loud_gpu.wav` were supplied for GPU fan audio. The testing station loops their sustained middle sections and blends them according to remaining dust.

`assets/sounds/pc/keypress-001.wav` to `keypress-012.wav` are single keystrokes from **Keyboard Soundpack #1 [Typing and Single Keystrokes] by unicaegames** (Cherry KC 1000), licensed CC0. They play when sitting down at the shop computer, on its F1-F3 page keys and when stepping away.

- Source: https://opengameart.org/content/keyboard-soundpack-1-typing-and-single-keystrokes

`assets/sounds/pc/mouse_click.wav` and `assets/sounds/pc/mouse_release.wav` are `mouseclick1.wav` and `mouserelease1.wav` from **UI Audio by Kenney** (kenney.nl), licensed CC0. They play on mouse presses and releases at the shop computer.

- Source: https://kenney.nl/assets/ui-audio (via https://github.com/Calinou/kenney-ui-audio)

`assets/sounds/gpu_sounds/spudger_scraping.mp3` and `assets/sounds/gpu_sounds/ipa_wipe.mp3` (a window being wiped) were supplied for the paste tools. `assets/sounds/spudger_scrape.wav` and `assets/sounds/ipa_wipe.wav` are the in-game loops made from them: high-passed (150 Hz and 100 Hz) to remove rumble, the scrape gently compressed into a steady texture, the wipe's long silences shortened, each end crossfaded into its start, and the wipe set 6 dB below the scrape. They loop while the spudger or IPA wipe is on a paste face; the IPA wipe loop also plays while wiping the fan shaft.

The four sounds below were cut from Freesound previews, mixed to mono 44.1 kHz, high-passed to remove rumble and peak-normalised. Keep the CC-BY attributions with distributed builds.

- `assets/sounds/paste_squeeze.wav` loops while the paste syringe squeezes. It joins the five clean squeeze strokes (gaps removed, each end crossfaded into its start) from **"Toothpaste manipulation" by MaslovyTygr**, licensed **Creative Commons Attribution 4.0**. Source: https://freesound.org/s/736059/
- `assets/sounds/oil_drop.wav` plays once per fan-oiler drop, slightly re-pitched each time. It is **"Oil Squirts.wav" by Augdog** (oil squirted from a dropper), licensed **Creative Commons Attribution 4.0**. Source: https://freesound.org/s/210214/
- `assets/sounds/gpu_unbox.wav` plays as the delivery box opens: the first flap-opening pass of **"box cardboard open part flaps.wav" by kyles** (CC0, https://freesound.org/s/452567/), then, as the card lifts out, a second of plastic crinkle 7 dB lower from **"Opening Plastic Package" by rodrigocswm** (CC0, https://freesound.org/s/434674/).
- `assets/sounds/gpu_set_down.wav` plays when the card lands in its holder or on the bench, and when a detached assembly is placed on the table. It is the main impact of **"Plastic object being set down" by bwarpus99**, licensed CC0. Source: https://freesound.org/s/452535/

License: https://creativecommons.org/licenses/by/4.0/

`assets/shop-interior.glb` is the repository-authored workshop, exported from `models/shop-interior.blend`. Visual references and export instructions are recorded in `models/shop-interior.md`; no third-party model or photo textures are embedded.

`assets/fonts/PermanentMarker-Regular.ttf` is **Permanent Marker** by Font Diner, licensed under the Apache License 2.0 (`assets/fonts/LICENSE-PermanentMarker.txt`). Techs write fault tags with it. `assets/fonts/Caveat-Variable.ttf` is **Caveat** by The Caveat Project Authors, licensed under the SIL Open Font License 1.1 (`assets/fonts/OFL-Caveat.txt`). Customer notes and tech signatures use it. Both come from the Google Fonts repository (https://github.com/google/fonts).
