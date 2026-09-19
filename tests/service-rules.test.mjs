import test from 'node:test';
import assert from 'node:assert/strict';
import { createServiceRules, gpuServiceExceptions } from '../src/service-rules.ts';

function fixture(coolerScrewCount = 4) {
  const fanScrews = Array.from({ length: 4 }, (_, i) => `fan-screw-${i + 1}`);
  const coolerScrews = Array.from({ length: coolerScrewCount }, (_, i) => `cooler-screw-${i + 1}`);
  const parts = [
    { id: 'fan-plug', kind: 'connector', requires: [] },
    { id: 'cooler-assembly', kind: 'assembly', parent: 'gpu', requires: ['fan-plug', ...coolerScrews] },
    { id: 'fan-assembly', kind: 'assembly', parent: 'cooler-assembly', requires: ['fan-plug', ...fanScrews] },
    ...fanScrews.map(id => ({ id, kind: 'fastener', requires: [] })),
    ...coolerScrews.map(id => ({ id, kind: 'fastener', requires: [] })),
  ];
  const rules = createServiceRules(parts, gpuServiceExceptions);
  function check(kind, part, { removed = [], cableConnected = true, equippedTool = null } = {}) {
    const removedSet = new Set(removed);
    return rules.check({ kind, part }, { isRemoved: id => removedSet.has(id), isConnected: id => id === 'fan-plug' && cableConnected, equippedTool });
  }
  return { check, fanScrews, coolerScrews };
}

test('tool and cable constraints are checked at the action boundary', () => {
  const { check } = fixture();
  assert.equal(check('remove', 'fan-screw-1').allowed, false);
  assert.equal(check('remove', 'fan-screw-1', { equippedTool: 'screwdriver' }).allowed, true);
  assert.equal(check('remove', 'cooler-screw-1', { equippedTool: 'screwdriver' }).allowed, false);
  assert.deepEqual(check('remove', 'cooler-screw-1', { equippedTool: 'screwdriver' }).missing, ['fan-plug']);
  assert.equal(check('remove', 'cooler-screw-1', { equippedTool: 'screwdriver', cableConnected: false }).allowed, true);
  assert.equal(check('disconnect', 'fan-plug', { equippedTool: 'screwdriver' }).allowed, false);
  assert.equal(check('disconnect', 'fan-plug').allowed, true);
});

test('assembly removal follows model requirements', () => {
  const { check, fanScrews, coolerScrews } = fixture();
  assert.deepEqual(check('remove', 'fan-assembly').missing, ['fan-plug', ...fanScrews]);
  assert.deepEqual(check('remove', 'fan-assembly', { cableConnected: false }).missing, fanScrews);
  assert.equal(check('remove', 'fan-assembly', { cableConnected: false, removed: fanScrews }).allowed, true);
  assert.equal(check('remove', 'cooler-assembly', { cableConnected: false, removed: coolerScrews }).allowed, true);
  assert.equal(check('remove', 'cooler-assembly', { cableConnected: false, removed: coolerScrews, equippedTool: 'screwdriver' }).allowed, false);
});

test('refit order follows assembly dependents and parent relationships', () => {
  const { check } = fixture();
  const removed = ['fan-assembly', 'cooler-assembly', 'fan-screw-1', 'cooler-screw-1'];
  assert.deepEqual(check('refit', 'fan-assembly', { removed }).missing, ['cooler-assembly']);
  assert.deepEqual(check('refit', 'fan-screw-1', { removed, equippedTool: 'screwdriver' }).missing, ['fan-assembly']);
  assert.deepEqual(check('refit', 'cooler-screw-1', { removed, equippedTool: 'screwdriver' }).missing, ['cooler-assembly']);
  assert.deepEqual(check('connect', 'fan-plug', { removed }).missing, ['cooler-assembly', 'fan-assembly']);
  assert.equal(check('refit', 'cooler-assembly', { removed }).allowed, true);
  assert.equal(check('refit', 'fan-assembly', { removed: ['fan-assembly'] }).allowed, true);
  assert.equal(check('connect', 'fan-plug').allowed, true);
});

test('a new cooler screw inherits assembly and cable requirements', () => {
  const { check, coolerScrews } = fixture(5);
  assert.deepEqual(check('remove', 'cooler-screw-5', { equippedTool: 'screwdriver' }).missing, ['fan-plug']);
  assert.deepEqual(check('remove', 'cooler-assembly', {
    cableConnected: false, removed: coolerScrews.slice(0, 4),
  }).missing, ['cooler-screw-5']);
});

test('invalid dependency graphs fail during setup', () => {
  assert.throws(() => createServiceRules([
    { id: 'a', kind: 'assembly', requires: ['b'] },
    { id: 'b', kind: 'assembly', requires: ['a'] },
  ]), /Circular service requirements/);
  assert.throws(() => createServiceRules([
    { id: 'a', kind: 'assembly', requires: ['missing'] },
  ]), /Unknown service requirement/);
});

test('connector requirements use the supplied connector state', () => {
  const rules = createServiceRules([
    { id: 'aux-plug', kind: 'connector', requires: [] },
    { id: 'aux-assembly', kind: 'assembly', parent: 'gpu', requires: ['aux-plug'] },
  ]);
  const facts = { isRemoved: () => false, isConnected: id => id === 'aux-plug', equippedTool: null };
  assert.deepEqual(rules.check({ kind: 'remove', part: 'aux-assembly' }, facts).missing, ['aux-plug']);
  assert.equal(rules.check({ kind: 'remove', part: 'aux-assembly' }, { ...facts, isConnected: () => false }).allowed, true);
});


test('the blower cannot turn screws or bypass empty-hand service rules', () => {
  const { check, fanScrews } = fixture();
  const equippedTool = 'blower';
  assert.equal(check('remove', 'fan-screw-1', { equippedTool }).allowed, false);
  assert.equal(check('refit', 'fan-screw-1', { equippedTool }).allowed, false);
  assert.equal(check('disconnect', 'fan-plug', { equippedTool }).allowed, false);
  assert.equal(check('remove', 'fan-assembly', { equippedTool, cableConnected: false, removed: fanScrews }).allowed, false);
  assert.match(check('refit', 'fan-assembly', { equippedTool }).reason, /blower/);
  assert.equal(check('refit', 'fan-assembly', { equippedTool: null }).allowed, true);
});
