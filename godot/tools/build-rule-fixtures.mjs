// Generate acceptance decisions from the existing TypeScript implementation.
// Fixtures are transient under .godot; regenerate whenever the browser rules change.
import { createServiceRules, gpuServiceExceptions } from '../../src/service-rules.ts';
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const fixtures = [];
let seed = 73;
const random = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 2 ** 32; };
for (const screwCount of [4, 5]) {
  const fan = Array.from({ length: 4 }, (_, i) => `fan-screw-${i + 1}`);
  const cooler = Array.from({ length: screwCount }, (_, i) => `cooler-screw-${i + 1}`);
  const definitions = [
    { id: 'fan-plug', kind: 'connector', requires: [] },
    { id: 'cooler-assembly', kind: 'assembly', parent: 'gpu', requires: ['fan-plug', ...cooler] },
    { id: 'fan-assembly', kind: 'assembly', parent: 'cooler-assembly', requires: ['fan-plug', ...fan] },
    ...fan.concat(cooler).map(id => ({ id, kind: 'fastener', requires: [] })),
  ];
  const rules = createServiceRules(definitions, gpuServiceExceptions);
  const cases = [];
  const tools = ['', 'screwdriver', 'blower', 'dev-blower', 'scraper'];
  // Both sparse and dense removal states exercise valid transitions and denials.
  for (let i = 0; i < 512; i++) {
    const part = definitions[i % definitions.length];
    const kinds = part.kind === 'connector' ? ['connect', 'disconnect']
      : part.kind === 'assembly' ? ['remove', 'refit', 'pickup'] : ['remove', 'refit'];
    const kind = kinds[Math.floor(random() * kinds.length)];
    const removed = definitions.filter(p => p.kind !== 'connector' && random() < (i % 2 ? .9 : .2)).map(p => p.id);
    const connected = { 'fan-plug': random() > .5 };
    const tool = tools[Math.floor(random() * tools.length)];
    const decision = rules.check({ kind, part: part.id }, {
      isRemoved: id => removed.includes(id), isConnected: id => Boolean(connected[id]), equippedTool: tool || null,
    });
    cases.push({ kind, id: part.id, removed, connected, tool, allowed: decision.allowed, missing: decision.missing });
  }
  fixtures.push({ definitions, exceptions: gpuServiceExceptions, cases });
}
const path = fileURLToPath(new URL('../.godot/', import.meta.url));
mkdirSync(path, { recursive: true });
writeFileSync(path + 'rule-fixtures.json', JSON.stringify(fixtures));
console.log('Generated 1,024 reproducible rule decisions from src/service-rules.ts.');
