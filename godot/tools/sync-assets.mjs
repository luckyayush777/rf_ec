// Run from any directory: node godot/tools/sync-assets.mjs
// Source assets remain in the browser/Blender directories. Godot gets exact copies.
import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';

const root = fileURLToPath(new URL('../', import.meta.url));
const assets = resolve(root, 'assets');
const repo = resolve(root, '..');
mkdirSync(assets, { recursive: true });
const sources = ['src/assets/gpu.glb', 'models/repair-shop.glb', 'src/assets/manual-screwdriver.wav',
  'src/assets/cleaning-complete.ogg'];
const hashes = {};
for (const source of sources) {
  const bytes = readFileSync(resolve(repo, source));
  hashes[source] = createHash('sha256').update(bytes).digest('hex');
  copyFileSync(resolve(repo, source), resolve(assets, source.split('/').at(-1)));
}
const gpu = readFileSync(resolve(assets, 'gpu.glb'));
if (gpu.toString('ascii', 0, 4) !== 'glTF') throw new Error('Expected binary glTF.');
const json = JSON.parse(gpu.toString('utf8', 20, 20 + gpu.readUInt32LE(12)));
const parents = new Map();
json.nodes.forEach((node, index) => (node.children ?? []).forEach(child => parents.set(child, index)));
const parts = [];
for (const [index, node] of json.nodes.entries()) {
  if (!node.extras?.bench_part) continue;
  const metadata = JSON.parse(node.extras.bench_part);
  parts.push({ id: node.name, parent: json.nodes[parents.get(index)]?.name ?? '', ...metadata });
}
const manifest = { sources: hashes, parts };
writeFileSync(resolve(assets, 'gpu-parts.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(`Synced ${sources.length} assets and ${parts.length} named part definitions.`);
