import { existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const [mode, ...args] = process.argv.slice(2);
if (!['build', 'export'].includes(mode)) {
  console.error('Usage: node scripts/blender.mjs build|export [options]');
  process.exit(1);
}
const candidates = [process.env.BLENDER_BIN, '/Applications/Blender.app/Contents/MacOS/Blender', 'blender'].filter(Boolean);
let executable;
for (const candidate of candidates) {
  const result = spawnSync(candidate, ['--version'], { encoding: 'utf8' });
  if (!result.error && result.status === 0) { executable = candidate; break; }
}
if (!executable) {
  console.error('Blender was not found. Install Blender 4.5 LTS or newer, or set BLENDER_BIN to its executable.\nSee models/README.md for setup and editing instructions.');
  process.exit(1);
}
let blenderArgs;
if (mode === 'build') {
  blenderArgs = ['--background', '--factory-startup', '--python-exit-code', '1', '--python', path.join(root, 'scripts/blender/build_gpu.py'), '--', ...args];
} else {
  const index = args.indexOf('--blend');
  if (index !== -1 && (!args[index + 1] || args[index + 1].startsWith('--'))) {
    console.error('--blend needs a .blend file path.');
    process.exit(1);
  }
  const blend = index === -1 ? path.join(root, 'models/gpu.blend') : path.resolve(args[index + 1]);
  if (index !== -1) args.splice(index, 2);
  if (!existsSync(blend)) {
    console.error(`No Blender model at ${blend}. Run npm run model:build first.`);
    process.exit(1);
  }
  blenderArgs = ['--background', blend, '--python-exit-code', '1', '--python', path.join(root, 'scripts/blender/export_gpu.py'), '--', ...args];
}
const result = spawnSync(executable, blenderArgs, { cwd: root, stdio: 'inherit' });
if (result.error) console.error(result.error.message);
process.exit(result.status ?? 1);
