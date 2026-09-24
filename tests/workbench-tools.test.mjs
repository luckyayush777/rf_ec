import test from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import { createWorkbenchTools } from '../src/workbench-tools.ts';

function fixture() {
  const scene = new THREE.Scene(), camera = new THREE.PerspectiveCamera(35, 1, .1, 100);
  const toolbox = new THREE.Group(), lid = new THREE.Group(), screwdriver = new THREE.Group(), blower = new THREE.Group(), scraper = new THREE.Group();
  scene.add(camera, toolbox); toolbox.add(lid, screwdriver, blower, scraper);
  const homePosition = new THREE.Vector3(0, .57, .05), blowerHomePosition = new THREE.Vector3(0, .57, -.65);
  const scraperHomePosition = new THREE.Vector3(-.78, .53, .72);
  const bench = { toolbox, lid, screwdriver, blower, scraper, homePosition, blowerHomePosition, scraperHomePosition };
  let allowed = true;
  const tools = createWorkbenchTools(scene, camera, bench, { play() {} }, true, () => allowed, () => {}, () => {}, () => {});
  function settle() { for (let i = 0; i < 6; i++) tools.update(performance.now() + 1000, .1); }
  return { tools, camera, bench, scene, settle, block: () => { allowed = false; } };
}

test('switching tools returns the old tool and equips only one object', () => {
  const { tools, camera, bench, settle } = fixture();
  tools.equip('screwdriver'); settle();
  assert.equal(tools.state.equippedTool, 'screwdriver');
  assert.equal(bench.screwdriver.parent, camera);
  tools.equip('blower');
  assert.equal(Object.values(tools.state.locations).filter(value => value === 'held').length, 0);
  settle();
  assert.equal(tools.state.equippedTool, 'blower');
  assert.equal(bench.blower.parent, camera);
  assert.equal(bench.screwdriver.parent, bench.toolbox);
  assert.deepEqual(bench.screwdriver.position.toArray(), bench.homePosition.toArray());
  tools.returnTool(); settle();
  assert.equal(tools.state.equippedTool, null);
  assert.equal(bench.blower.parent, bench.toolbox);
  assert.deepEqual(bench.blower.position.toArray(), bench.blowerHomePosition.toArray());
});

test('the blower can be placed on the desk and picked up again', () => {
  const { tools, scene, camera, bench, settle } = fixture();
  tools.equip('blower'); settle(); tools.place(new THREE.Vector3(2, 0, 1), []); settle();
  assert.equal(tools.state.locations.blower, 'desk');
  assert.equal(bench.blower.parent, scene);
  assert.equal(tools.state.equippedTool, null);
  tools.grab('blower'); settle();
  assert.equal(tools.state.equippedTool, 'blower');
  assert.equal(bench.blower.parent, camera);
});

test('a busy service action cannot switch or drop the equipped tool', () => {
  const { tools, settle, block } = fixture();
  tools.equip('screwdriver'); settle(); block();
  tools.equip('blower'); tools.returnTool(); settle();
  assert.equal(tools.state.equippedTool, 'screwdriver');
  assert.equal(tools.state.locations.blower, 'toolbox');
});

test('the scraper obeys the same toolbox, desk, and return rules', () => {
  const { tools, scene, bench, camera, settle } = fixture();
  tools.equip('scraper'); settle();
  assert.equal(tools.state.equippedTool, 'scraper');
  assert.equal(bench.scraper.parent, camera);
  tools.place(new THREE.Vector3(4, 0, 2), []); settle();
  assert.equal(tools.state.locations.scraper, 'desk');
  assert.equal(bench.scraper.parent, scene);
  tools.grab('scraper'); settle(); tools.returnTool(); settle();
  assert.equal(tools.state.locations.scraper, 'toolbox');
  assert.equal(bench.scraper.parent, bench.toolbox);
  assert.deepEqual(bench.scraper.position.toArray(), bench.scraperHomePosition.toArray());
});
