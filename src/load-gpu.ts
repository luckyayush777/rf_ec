import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
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
  return { gpu };
}
