import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { createGPU } from './gpu';

// Vite discovers the asset after model:build/model:export and fingerprints it for production.
const assets = import.meta.glob<string>('./assets/gpu.glb', { eager: true, query: '?url', import: 'default' });

export async function loadGPU(): Promise<{ gpu: THREE.Object3D }> {
  const url = assets['./assets/gpu.glb'];
  if (!url) return createGPU();
  const gltf = await new GLTFLoader().loadAsync(url);
  const gpu = gltf.scene.getObjectByName('gpu');
  if (!gpu) throw new Error('The Blender asset is missing its named gpu root.');
  gpu.removeFromParent();
  gpu.traverse(object => {
    if (object instanceof THREE.Mesh) {
      object.castShadow = object.receiveShadow = true;
    }
    if (typeof object.userData.bench_part === 'string') {
      object.userData.part = JSON.parse(object.userData.bench_part);
    }
  });
  // The native source keeps every component editable. Batch fixed detail for phones.
  gpu.updateMatrixWorld(true);
  for (const name of ['pcb-detail', 'mounting-bracket']) {
    const group = gpu.getObjectByName(name);
    if (!group) continue;
    const inverse = group.matrixWorld.clone().invert();
    const batches = new Map<string, { material: THREE.Material; meshes: THREE.Mesh[] }>();
    group.traverse(object => {
      if (!(object instanceof THREE.Mesh) || Array.isArray(object.material) || object.name.startsWith('memory-residue-')) return;
      const key = object.material.uuid + Object.keys(object.geometry.attributes).sort().join(',');
      if (!batches.has(key)) batches.set(key, { material: object.material, meshes: [] });
      batches.get(key)!.meshes.push(object);
    });
    for (const { material, meshes } of batches.values()) {
      const geometries = meshes.map(mesh => mesh.geometry.clone().applyMatrix4(inverse.clone().multiply(mesh.matrixWorld)));
      const geometry = mergeGeometries(geometries);
      geometries.forEach(item => item.dispose());
      if (!geometry) continue;
      meshes.forEach(mesh => mesh.removeFromParent());
      const mesh = new THREE.Mesh(geometry, material);
      mesh.name = `${name}-${material.name}`; mesh.castShadow = mesh.receiveShadow = true;
      group.add(mesh);
    }
  }
  return { gpu };
}
