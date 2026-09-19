import * as THREE from 'three';

// Six small planar masks per part avoid depending on the asset's UV unwrap.
// Each face has its own tile, so cleaning the front cannot erase the back.
const TILE = 48, WIDTH = TILE * 3, HEIGHT = TILE * 2;
type DustSurface = {
  mesh: THREE.Mesh; bounds: THREE.Box3; size: THREE.Vector3;
  texture: THREE.DataTexture; data: Uint8Array; initial: Uint8Array;
  mass: number; remaining: number; weight: number[];
  clumps?: { mesh: THREE.InstancedMesh; samples: { pixel: number; matrix: THREE.Matrix4 }[] };
};

function faceIndex(normal: THREE.Vector3) {
  const a = [Math.abs(normal.x), Math.abs(normal.y), Math.abs(normal.z)];
  const axis = a[0] > a[1] && a[0] > a[2] ? 0 : a[1] > a[2] ? 1 : 2;
  return axis * 2 + (normal.getComponent(axis) < 0 ? 1 : 0);
}
const axes = [[2, 1], [2, 1], [0, 2], [0, 2], [0, 1], [0, 1]];
function pixel(point: THREE.Vector3, face: number, bounds: THREE.Box3, size: THREE.Vector3) {
  const [u, v] = axes[face];
  return new THREE.Vector2(
    (point.getComponent(u) - bounds.min.getComponent(u)) / size.getComponent(u) * (TILE - 2) + 1 + (face % 3) * TILE,
    (point.getComponent(v) - bounds.min.getComponent(v)) / size.getComponent(v) * (TILE - 2) + 1 + Math.floor(face / 3) * TILE,
  );
}

export function createGPUDust(gpu: THREE.Object3D) {
  const surfaces: DustSurface[] = [];
  const lookup = new Map<THREE.Object3D, DustSurface>();
  gpu.updateWorldMatrix(true, true);
  const inverse = gpu.matrixWorld.clone().invert();
  const selected = /^(board-top|board-bottom|fan-housing|fan-blade-\d+|fan-hub-cap|heatsink-fins|heatsink-fin-\d+)$/;
  gpu.traverse(object => {
    if (!(object instanceof THREE.Mesh) || !selected.test(object.name)) return;
    const mesh = object;
    mesh.geometry.computeBoundingBox();
    const bounds = mesh.geometry.boundingBox!.clone();
    const size = bounds.getSize(new THREE.Vector3()).max(new THREE.Vector3(.001, .001, .001));
    const localToGPU = inverse.clone().multiply(mesh.matrixWorld);
    const normalMatrix = new THREE.Matrix3().getNormalMatrix(localToGPU);
    const paint = document.createElement('canvas'); paint.width = WIDTH; paint.height = HEIGHT;
    const ctx = paint.getContext('2d')!;
    ctx.fillStyle = '#fff';
    const position = mesh.geometry.getAttribute('position');
    const index = mesh.geometry.index;
    const a = new THREE.Vector3(), b = new THREE.Vector3(), c = new THREE.Vector3();
    const normal = new THREE.Vector3();
    for (let i = 0; i < (index?.count ?? position.count); i += 3) {
      a.fromBufferAttribute(position, index ? index.getX(i) : i);
      b.fromBufferAttribute(position, index ? index.getX(i + 1) : i + 1);
      c.fromBufferAttribute(position, index ? index.getX(i + 2) : i + 2);
      normal.crossVectors(b.clone().sub(a), c.clone().sub(a)).normalize();
      const outward = normal.clone().applyMatrix3(normalMatrix).normalize();
      // First job is exterior cleaning: no inaccessible dust below the cooler.
      if (mesh.name === 'board-bottom' ? outward.y > -.7 : outward.y < .7) continue;
      const face = faceIndex(normal);
      const points = [a, b, c].map(p => pixel(p, face, bounds, size));
      ctx.beginPath(); ctx.moveTo(points[0].x, points[0].y);
      ctx.lineTo(points[1].x, points[1].y); ctx.lineTo(points[2].x, points[2].y); ctx.closePath(); ctx.fill();
    }
    const coverage = ctx.getImageData(0, 0, WIDTH, HEIGHT).data;
    const initial = new Uint8Array(WIDTH * HEIGHT * 4);
    const weight = axes.map(([u, v]) => size.getComponent(u) * size.getComponent(v) / ((TILE - 2) ** 2));
    let mass = 0;
    for (let y = 0; y < HEIGHT; y++) for (let x = 0; x < WIDTH; x++) {
      const i = (y * WIDTH + x) * 4;
      if (coverage[i + 3] < 100) continue;
      const face = Math.floor(y / TILE) * 3 + Math.floor(x / TILE);
      const [u, v] = axes[face];
      const p = bounds.min.clone();
      p.setComponent(Math.floor(face / 2), face % 2 ? bounds.min.getComponent(Math.floor(face / 2)) : bounds.max.getComponent(Math.floor(face / 2)));
      p.setComponent(u, bounds.min.getComponent(u) + ((x % TILE) - 1) / (TILE - 2) * size.getComponent(u));
      p.setComponent(v, bounds.min.getComponent(v) + ((y % TILE) - 1) / (TILE - 2) * size.getComponent(v));
      p.applyMatrix4(localToGPU);
      if (mesh.name === 'board-top' && p.x < 2.07 && Math.abs(p.z) < 1.16) continue;
      if (mesh.name.startsWith('heatsink-fin') && Math.abs(p.x + .43) < 1.10 && Math.abs(p.z) < 1.10) continue;
      const patch = Math.sin(p.x * 4.1 + p.z * 2.9) * Math.cos(p.z * 6.3 - p.x * 1.8);
      initial[i] = Math.round(180 + patch * 45 + Math.random() * 29);
      initial[i + 3] = 255;
      mass += initial[i] * weight[face];
    }
    const data = initial.slice();
    const texture = new THREE.DataTexture(data, WIDTH, HEIGHT);
    texture.minFilter = texture.magFilter = THREE.LinearFilter;
    texture.needsUpdate = true;
    const original = mesh.material as THREE.MeshStandardMaterial;
    const material = original.clone();
    material.onBeforeCompile = shader => {
      shader.uniforms.dustMap = { value: texture };
      shader.uniforms.dustMin = { value: bounds.min };
      shader.uniforms.dustSize = { value: size };
      shader.vertexShader = 'varying vec3 dustP; varying vec3 dustN;\n' + shader.vertexShader;
      shader.vertexShader = shader.vertexShader.replace('#include <begin_vertex>', '#include <begin_vertex>\ndustP = position; dustN = normal;');
      shader.fragmentShader = `uniform sampler2D dustMap; uniform vec3 dustMin; uniform vec3 dustSize;
        varying vec3 dustP; varying vec3 dustN;
        float dustAmount() {
          vec3 p = clamp((dustP - dustMin) / dustSize, 0.0, 1.0);
          vec3 n = abs(dustN); float f; vec2 q;
          if(n.x > n.y && n.x > n.z) { f = dustN.x < 0.0 ? 1.0 : 0.0; q = p.zy; }
          else if(n.y > n.z) { f = dustN.y < 0.0 ? 3.0 : 2.0; q = p.xz; }
          else { f = dustN.z < 0.0 ? 5.0 : 4.0; q = p.xy; }
          vec2 uv = (q * ${TILE - 2}.0 + 1.0 + vec2(mod(f, 3.0), floor(f / 3.0)) * ${TILE}.0) / vec2(${WIDTH}.0, ${HEIGHT}.0);
          return texture2D(dustMap, uv).r;
        }\n` + shader.fragmentShader;
      shader.fragmentShader = shader.fragmentShader.replace('#include <color_fragment>', `#include <color_fragment>
        float dust = dustAmount();
        float grain = fract(sin(dot(floor(dustP * 260.0), vec3(12.9898,78.233,43.71))) * 43758.5453);
        diffuseColor.rgb = mix(diffuseColor.rgb, vec3(.30, .26, .21) * (.8 + grain * .4), dust * .94);`);
      shader.fragmentShader = shader.fragmentShader.replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\nroughnessFactor = mix(roughnessFactor, 1.0, dust);');
      shader.fragmentShader = shader.fragmentShader.replace('#include <metalnessmap_fragment>', '#include <metalnessmap_fragment>\nmetalnessFactor *= 1.0 - dust;');
    };
    material.customProgramCacheKey = () => 'gpu-dust-v1';
    mesh.material = material;
    const surface = { mesh, bounds, size, data, initial, texture, mass, remaining: mass, weight };
    surfaces.push(surface); lookup.set(mesh, surface);
  });
  const clumpGeometry = new THREE.SphereGeometry(1, 6, 4);
  const clumpMaterial = new THREE.MeshStandardMaterial({ color: '#9b8e77', roughness: 1 });
  const dummy = new THREE.Object3D();
  for (const s of surfaces) {
    const candidates: number[] = [];
    for (let i = 0; i < s.initial.length; i += 4) if (s.initial[i] > 210) candidates.push(i);
    const count = s.mesh.name.includes('board') ? 20 : s.mesh.name.includes('blade') ? 3 : 12;
    const samples: { pixel: number; matrix: THREE.Matrix4 }[] = [];
    if (!candidates.length) continue;
    const clumps = new THREE.InstancedMesh(clumpGeometry, clumpMaterial, count);
    clumps.name = `${s.mesh.name}-dust-clumps`; clumps.userData.dustVisual = true; clumps.userData.noHighlight = true;
    for (let i = 0; i < count; i++) {
      const cell = candidates[Math.floor(Math.random() * candidates.length)];
      const x = (cell / 4) % WIDTH, y = Math.floor(cell / 4 / WIDTH);
      const face = Math.floor(y / TILE) * 3 + Math.floor(x / TILE), [u, v] = axes[face], axis = Math.floor(face / 2);
      const normal = new THREE.Vector3().setComponent(axis, face % 2 ? -1 : 1);
      dummy.position.copy(s.bounds.min);
      dummy.position.setComponent(axis, face % 2 ? s.bounds.min.getComponent(axis) : s.bounds.max.getComponent(axis));
      dummy.position.setComponent(u, s.bounds.min.getComponent(u) + ((x % TILE) - 1) / (TILE - 2) * s.size.getComponent(u));
      dummy.position.setComponent(v, s.bounds.min.getComponent(v) + ((y % TILE) - 1) / (TILE - 2) * s.size.getComponent(v));
      dummy.position.addScaledVector(normal, .012);
      dummy.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), normal);
      dummy.scale.set(.025 + Math.random() * .045, .015, .025 + Math.random() * .025);
      dummy.updateMatrix(); clumps.setMatrixAt(i, dummy.matrix);
      samples.push({ pixel: cell, matrix: dummy.matrix.clone() });
    }
    s.mesh.add(clumps); s.clumps = { mesh: clumps, samples };
  }
  function updateClumps(s: DustSurface, before = false) {
    if (!s.clumps) return;
    s.clumps.samples.forEach((sample, i) => {
      const amount = before ? 1 : s.data[sample.pixel] / Math.max(1, s.initial[sample.pixel]);
      s.clumps!.mesh.setMatrixAt(i, sample.matrix.clone().scale(new THREE.Vector3(amount, amount, amount)));
    });
    s.clumps.mesh.instanceMatrix.needsUpdate = true;
  }
  let showingBefore = false;
  return {
    surfaces,
    get progress() { const total = surfaces.reduce((sum, s) => sum + s.mass, 0); return total ? 1 - surfaces.reduce((sum, s) => sum + s.remaining, 0) / total : 1; },
    clean(hit: THREE.Intersection, seconds: number, radius = .36) {
      if (showingBefore || !hit.face) return 0;
      const s = lookup.get(hit.object); if (!s) return 0;
      const point = s.mesh.worldToLocal(hit.point.clone());
      const face = faceIndex(hit.face.normal), [u, v] = axes[face];
      const center = pixel(point, face, s.bounds, s.size);
      const scale = s.mesh.getWorldScale(new THREE.Vector3());
      const rx = radius / scale.getComponent(u) / s.size.getComponent(u) * (TILE - 2);
      const ry = radius / scale.getComponent(v) / s.size.getComponent(v) * (TILE - 2);
      let removed = 0;
      const tileX = (face % 3) * TILE, tileY = Math.floor(face / 3) * TILE;
      for (let y = Math.max(tileY, Math.floor(center.y - ry)); y <= Math.min(tileY + TILE - 1, Math.ceil(center.y + ry)); y++) {
        for (let x = Math.max(tileX, Math.floor(center.x - rx)); x <= Math.min(tileX + TILE - 1, Math.ceil(center.x + rx)); x++) {
          const falloff = Math.max(0, 1 - ((x - center.x) / rx) ** 2 - ((y - center.y) / ry) ** 2);
          const i = (y * WIDTH + x) * 4;
          const amount = Math.min(s.data[i], Math.round(seconds * 360 * falloff));
          s.data[i] -= amount; removed += amount * s.weight[face];
        }
      }
      if (removed) { s.remaining = Math.max(0, s.remaining - removed); s.texture.needsUpdate = true; updateClumps(s); }
      return removed;
    },
    before(value: boolean) {
      showingBefore = value;
      for (const s of surfaces) { s.texture.image.data = value ? s.initial : s.data; s.texture.needsUpdate = true; updateClumps(s, value); }
    },
    reset() {
      showingBefore = false;
      for (const s of surfaces) {
        // Different patch strengths on the next arrival, with the same reachable coverage.
        for (let i = 0; i < s.initial.length; i += 4) if (s.initial[i]) s.initial[i] = 160 + Math.floor(Math.random() * 95);
        s.data.set(s.initial); s.texture.image.data = s.data; s.texture.needsUpdate = true;
        updateClumps(s);
        s.mass = s.remaining = s.initial.reduce((sum, value, i) => i % 4 === 0 ? sum + value * s.weight[Math.floor(Math.floor(i / 4) / WIDTH / TILE) * 3 + Math.floor((i / 4 % WIDTH) / TILE)] : sum, 0);
      }
    },
    dispose() { surfaces.forEach(s => { s.texture.dispose(); s.clumps?.mesh.removeFromParent(); s.clumps?.mesh.dispose(); }); clumpGeometry.dispose(); clumpMaterial.dispose(); },
  };
}
