import * as THREE from 'three';

/** Tint only the selected part, preserving shared materials on its neighbours. */
export function createInteractionHighlight() {
  let target: THREE.Object3D | null = null;
  const originals = new Map<THREE.Mesh, THREE.Material | THREE.Material[]>();
  const highlights: THREE.Material[] = [];

  function clear() {
    originals.forEach((material, mesh) => { mesh.material = material; });
    originals.clear();
    highlights.forEach(material => material.dispose());
    highlights.length = 0;
  }

  function select(object: THREE.Object3D | null) {
    if (object === target) return;
    clear(); target = object;
    object?.traverse(child => {
      if (!(child instanceof THREE.Mesh) || !child.visible) return;
      const materials = Array.isArray(child.material) ? child.material : [child.material];
      if (!materials.some(material => material.visible)) return;
      originals.set(child, child.material);
      const tinted = materials.map(material => {
        const clone = material.clone();
        if (clone instanceof THREE.MeshStandardMaterial) {
          clone.emissive.set('#ffc65c');
          clone.emissiveIntensity = .38;
        } else if (clone instanceof THREE.MeshBasicMaterial) {
          clone.color.lerp(new THREE.Color('#ffc65c'), .4);
        }
        highlights.push(clone);
        return clone;
      });
      child.material = Array.isArray(child.material) ? tinted : tinted[0];
    });
  }

  return { select, dispose() { clear(); target = null; } };
}
