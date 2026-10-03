"""Run a focused group of existing Godot checks and save UTF-8 results."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / 'godot'
DEFAULT_GODOT = ROOT.parent / 'godot/Godot_v4.7.2-stable_win64_console.exe'
SUITES = {
    'smoke': ['smoke'],  # Smoke already invokes service_flow.
    'menu': ['audio_mix_flow', 'repair_speed_flow', 'repair_status_flow'],
    'tools': ['tool_art_flow', 'scale_toolbox_flow', 'tool_hotkey_flow'],
    'focus': ['closeup_flow', 'part_focus_flow', 'tool_inspection_flow'],
    'paste': ['repaste_flow', 'repair_speed_flow'],
    'dust': ['air_blower_flow', 'smoke'],
    'bearing': ['fan_bearing_flow'],
    'placement': ['placement_flow', 'staged_disassembly_flow'],
    'thermal': ['thermal_flow'],
    'jobs': ['repair_jobs_flow', 'gpu_brand_flow', 'billing_flow'],
    'connector': ['edge_connector_flow'],
    'walking': ['first_person_flow'],
    'outside': ['outside_flow'],
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=SUITES, default='smoke')
    parser.add_argument('--godot', default=os.environ.get('BENCH_GODOT_EXE', str(DEFAULT_GODOT)))
    parser.add_argument('--list', action='store_true', help='Show suites and check paths without running Godot')
    parser.add_argument('--import', dest='do_import', action='store_true', help='Import/check scripts first')
    parser.add_argument('--capture', action='store_true', help='Run rendered checks with -- --capture (opens windows)')
    parser.add_argument('--timeout', type=float, default=180, help='Maximum seconds per command')
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    godot = Path(args.godot).expanduser().resolve()
    missing = [name for tests in SUITES.values() for name in tests
               if not (PROJECT / f'tests/{name}.gd').is_file()]
    if missing:
        parser.error('Missing test scripts: ' + ', '.join(sorted(set(missing))))
    if args.list:
        print(f'Godot: {godot} (exists: {godot.is_file()})')
        for suite, tests in SUITES.items():
            print(f'{suite}: ' + ', '.join(f'tests/{name}.gd' for name in tests))
        return 0
    if not godot.is_file():
        parser.error('Godot not found; pass --godot PATH or set BENCH_GODOT_EXE. See godot/tools/LOCAL_ENVIRONMENT.md.')
    steps = []
    if args.do_import:
        steps.append(('import', ['--headless', '--editor', '--path', str(PROJECT), '--import', '--quit']))
    for name in SUITES[args.suite]:
        flags = [] if args.capture else ['--headless']
        flags += ['--path', str(PROJECT), '--script', f'res://tests/{name}.gd']
        if args.capture:
            flags += ['--', '--capture']
        steps.append((name, flags))
    output_dir = PROJECT / 'build/checks' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    output_dir.mkdir(parents=True, exist_ok=True)
    report = {'started_utc': datetime.now(timezone.utc).isoformat(), 'suite': args.suite,
              'capture': args.capture, 'godot': str(godot), 'results': [], 'status': 'running'}

    def save_report():
        data = json.dumps(report, indent=2) + '\n'
        (output_dir / 'results.json').write_text(data, encoding='utf-8')
        (output_dir.parent / 'latest.json').write_text(data, encoding='utf-8')

    save_report()
    for name, flags in steps:
        command = [str(godot), *flags]
        print(f'Running {name}...', flush=True)
        started = time.monotonic()
        exit_code = None
        try:
            process = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, encoding='utf-8', errors='replace',
                                     timeout=args.timeout)
            output, exit_code = process.stdout, process.returncode
            passed = exit_code == 0 and (name == 'import' or 'PASS:' in output)
            if 'FAIL:' in output or 'Parse Error:' in output or 'ERROR:' in output:
                passed = False
            status = 'passed' if passed else 'failed'
        except subprocess.TimeoutExpired as error:
            output = error.stdout or b''
            if isinstance(output, bytes):
                output = output.decode('utf-8', errors='replace')
            output += f'\nTimed out after {args.timeout:g} seconds.\n'
            status = 'timeout'
        except OSError as error:
            output, status = str(error) + '\n', 'failed'
        except KeyboardInterrupt:
            output, status = 'Interrupted before completion.\n', 'interrupted'
        log = output_dir / f'{name}.log'
        log.write_text(output, encoding='utf-8')
        report['results'].append({'name': name, 'status': status, 'exit_code': exit_code,
                                  'seconds': round(time.monotonic() - started, 2),
                                  'command': command, 'log': str(log)})
        report['status'] = status if status != 'passed' else 'running'
        save_report()
        print(f'{name}: {status} ({report["results"][-1]["seconds"]}s)', flush=True)
        if status != 'passed':
            print(output[-4000:])
            print(f'Results: {output_dir / "results.json"}')
            return 130 if status == 'interrupted' else 1
    report['status'] = 'passed'
    save_report()
    print(f'PASS: {args.suite}. Results: {output_dir / "results.json"}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
