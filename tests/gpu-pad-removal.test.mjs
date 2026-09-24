import test from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import { setupGPUPadRemoval } from '../src/gpu-pad-removal.ts';

test('scraping erases a directional strip while untouched pad material stays in place', () => {
  const oldDocument = globalThis.document;
  const events = new EventTarget();
  const output = { value: '' };
  globalThis.document = Object.assign(events, { querySelector: () => output });
  try {
    const gpu = new THREE.Group();
    const originalMaterial = new THREE.MeshStandardMaterial({ color: '#888888' });
    const piece = new THREE.Mesh(new THREE.BoxGeometry(.18, .024, .22), originalMaterial);
    piece.name = 'memory-residue-0-1';
    piece.position.set(-1.475, .146, -.46);
    gpu.add(piece);
    gpu.updateMatrixWorld(true);
    let coolerRemoved = false;
    const notices = [];
    const removal = setupGPUPadRemoval(gpu, () => coolerRemoved, text => notices.push(text));
    const at = (x, z = -.46) => new THREE.Vector3(x, .158, z);
    const ray = (x, z = -.46) => new THREE.Ray(new THREE.Vector3(x, 1, z), new THREE.Vector3(0, -1, 0));
    const visible = (x, z) => new THREE.Raycaster(new THREE.Vector3(x, 1, z), new THREE.Vector3(0, -1, 0))
      .intersectObject(piece).length > 0;

    assert.equal(removal.begin(piece, at(-1.415)), false);
    coolerRemoved = true;
    assert.equal(removal.begin(piece, at(-1.475)), false);
    assert.equal(removal.begin(piece, at(-1.415)), true);
    assert.equal(piece.material.emissive.getHexString(), 'ff7777');
    assert.equal(piece.children.length, 2);
    assert.equal(removal.drag(ray(-1.395)), false);
    assert.equal(removal.progress, 0);
    assert.equal(removal.drag(ray(-1.445)), true);
    assert.ok(removal.progress > 0 && removal.progress < 1);
    assert.equal(removal.drag(ray(-1.59)), true);
    assert.equal(piece.scale.x, 1);
    assert.equal(piece.scale.z, 1);
    assert.deepEqual(piece.position.toArray(), [-1.475, .146, -.46]);
    assert.equal(visible(-1.475, -.46), false);
    assert.equal(visible(-1.475, -.55), true);
    removal.end();
    assert.equal(piece.children.length, 0);
    assert.notEqual(piece.material, originalMaterial);

    const shader = { vertexShader: '#include <begin_vertex>', fragmentShader: '#include <clipping_planes_fragment>', uniforms: {} };
    piece.material.onBeforeCompile(shader);
    assert.match(shader.fragmentShader, /residueMask.*discard/s);
    assert.ok(shader.uniforms.residueMask.value instanceof THREE.DataTexture);

    assert.equal(removal.begin(piece, at(-1.415, -.39)), true);
    assert.equal(removal.drag(ray(-1.59, -.39)), true);
    assert.ok(removal.progress > 0);
    removal.end();
    document.dispatchEvent(new Event('bench-next-job'));
    assert.equal(removal.progress, 0);
    assert.equal(piece.visible, true);
    assert.equal(visible(-1.475, -.46), true);
    assert.match(output.value, /0%/);
    removal.dispose();
    assert.equal(piece.material, originalMaterial);
  } finally {
    globalThis.document = oldDocument;
  }
});
