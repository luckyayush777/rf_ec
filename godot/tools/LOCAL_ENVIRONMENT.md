# Local tools and checks

Paths below were checked on 2026-10-03 for this Windows checkout. Check these
paths before searching installations; rediscover a tool only if its path fails.

| Tool | Verified executable | Version |
| --- | --- | --- |
| Godot console | `C:\Users\user\Desktop\ayush.dev\godot\Godot_v4.7.2-stable_win64_console.exe` | `4.7.2.stable.official.ed1daf0bf` |
| Blender | `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe` | `5.2.2 LTS` |

Python 3 and its standard library are sufficient for the check runner and asset
synchronization. Commands below run from the repository root. The runner also
resolves the project correctly when invoked from another working directory.

```powershell
python godot/tools/check.py --list
python godot/tools/check.py --suite menu
python godot/tools/check.py --suite focus --import
python godot/tools/check.py --suite tools --capture
```

`--import` adds a parser/import check before the suite. `--capture` opens rendered
Godot windows and passes `-- --capture`; inspect the resulting images for visual
changes. Choose suites from `--list`. Run additional relevant suites for changes
that cross controllers; the groups are navigation shortcuts, not a coverage guarantee.
Smoke includes service flow. Dust-generation changes still need several fresh
smoke runs; automated captures do not certify audio audibility.

Use `--godot 'C:\other\Godot_console.exe'` or `BENCH_GODOT_EXE` on another machine.
The default resolves Godot in the sibling `godot/` installation for this checkout.
Each command has a 180-second timeout, adjustable with `--timeout`. Runs stop at
the first failure. UTF-8 logs and a JSON report with commands, exit codes, duration
and status live under ignored `godot/build/checks/<UTC timestamp>/`; `latest.json`
contains the last run's results. A test passes only with exit code 0, a `PASS:`
message and no reported errors. These results describe that run, and need
refreshing after relevant edits.

For saved Blender edits, use the applicable export script:

```powershell
$blenderExe = 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'
& $blenderExe --background models/gpu.blend --python scripts/blender/export_gpu.py
python godot/tools/sync_assets.py
```

GPU/shop exports use `sync_assets.py`; tool exports write directly into Godot and
need their native scene importer instead. Follow [GPU authoring](../../models/README.md),
[screwdriver authoring](../../models/screwdriver.md) or [tool-kit authoring](../../models/tool-kit.md).
For visual drafts, Blender background scripts can write a PNG under `artifacts/`
for inspection. Live Blender MCP availability must be checked in the current
session; these executable paths do not imply a live connection.

Write helper JSON and text logs explicitly as UTF-8. Python's
`Path.write_text(..., encoding='utf-8')` avoids PowerShell's differing redirect
encodings; avoid redirecting structured output with default `>` encoding.
