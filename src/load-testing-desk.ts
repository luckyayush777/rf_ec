import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import testingDeskUrl from '../models/repair-shop.glb?url';

export async function loadTestingDesk(repairTabletop: THREE.Object3D) {
  const testingDesk = (await new GLTFLoader().loadAsync(testingDeskUrl)).scene;
  testingDesk.name = 'testing-desk';
  // The repair scene already has a floor. Keep only the second desk and its props.
  testingDesk.getObjectByName('floor')?.removeFromParent();
  testingDesk.scale.setScalar(5);

  const testingTabletop = testingDesk.getObjectByName('desk-top');
  if (!testingTabletop) throw new Error('The testing desk asset is missing its tabletop.');

  const repairBounds = new THREE.Box3().setFromObject(repairTabletop);
  const testingBounds = new THREE.Box3().setFromObject(testingTabletop);
  const repairCenter = repairBounds.getCenter(new THREE.Vector3());
  const testingCenter = testingBounds.getCenter(new THREE.Vector3());
  testingDesk.position.set(
    repairBounds.max.x - testingBounds.min.x + 2.5,
    repairBounds.max.y - testingBounds.max.y,
    repairCenter.z - testingCenter.z,
  );

  testingDesk.traverse(object => {
    if (!(object instanceof THREE.Mesh)) return;
    object.receiveShadow = true;
    object.castShadow = /^(desk-top|desk-leg|lower-shelf|bench-power-supply|lamp-head|pcb-substrate|pcie-x16-socket)/.test(object.name);
  });

  const testingTarget = new THREE.Box3().setFromObject(testingTabletop).getCenter(new THREE.Vector3());
  testingTarget.y = -.3;
  return { testingDesk, testingTarget };
}
