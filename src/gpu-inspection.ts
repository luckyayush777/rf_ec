import * as THREE from 'three';
import type { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import type { WorkbenchSound } from './sound';
import type { ServiceDecision } from './service-rules';

export function setupGPUInspection(gpu: THREE.Object3D, camera: THREE.PerspectiveCamera,
  controls: OrbitControls, sound: WorkbenchSound, requestRender: () => void,
  reducedMotion: boolean, changed: () => void, canInteract: () => boolean,
  checkCable: (connect: boolean) => ServiceDecision) {
  const state = { held: false, moving: false, cableConnected: true };
  const home = { position: gpu.position.clone(), rotation: gpu.quaternion.clone() };
  const plug = gpu.getObjectByName('fan-plug')!;
  const plugHome = { position: plug.position.clone(), rotation: plug.quaternion.clone() };
  const displacement = new THREE.Vector3(0, .22, .58);
  const button = document.querySelector<HTMLButtonElement>('#return-gpu')!;
  const cableButton = document.querySelector<HTMLButtonElement>('#toggle-cable')!;
  const cameraButtons = [...document.querySelectorAll<HTMLButtonElement>('[data-view], #reset-view')];
  gpu.userData.action = 'gpu';
  plug.userData.action = 'cable';
  gpu.getObjectByName('board-fan-socket')!.userData.action = 'cable';
  gpu.getObjectByName('fan-cable')!.userData.action = 'cable';
  // A slightly larger invisible target makes the small plug usable with touch, too.
  const target = new THREE.Mesh(new THREE.BoxGeometry(.38, .28, .4), new THREE.MeshBasicMaterial({ visible: false }));
  target.name = 'fan-plug-pick-target'; target.userData.action = 'cable'; plug.add(target);
  let motion: { start: number; position: THREE.Vector3; rotation: THREE.Quaternion; returning: boolean } | null = null;
  let cableMotion: { start: number; from: number; to: number } | null = null;
  let cableProgress = 0;
  let zoom = 1;
  const pan = new THREE.Vector2();
  const wires = ['fan-positive-wire', 'fan-ground-wire'].map((name, index) => {
    const wire = gpu.getObjectByName(name) as THREE.Mesh<THREE.BufferGeometry>;
    const originalGeometry = wire.geometry;
    wire.geometry = originalGeometry.clone();
    const positions = wire.geometry.getAttribute('position') as THREE.BufferAttribute;
    const original = Float32Array.from(positions.array);
    const weights = new Float32Array(positions.count);
    const end = new THREE.Vector3(2.54, index === 0 ? .244 : .205, .39);
    const vertex = new THREE.Vector3();
    for (let i = 0; i < positions.count; i++) {
      vertex.fromBufferAttribute(positions, i);
      weights[i] = THREE.MathUtils.smoothstep(1 - Math.max(0, vertex.distanceTo(end) - .06) / .7, 0, 1);
    }
    return { wire, positions, original, weights, originalGeometry };
  });

  function inspectionPosition() {
    const distance = Math.max(11, 3.9 / (Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) * Math.min(1, camera.aspect))) * zoom;
    return camera.localToWorld(new THREE.Vector3(pan.x, pan.y - .1, -distance));
  }
  function updateButtons() {
    button.hidden = !state.held;
    cableButton.hidden = !state.held;
    cableButton.textContent = state.cableConnected ? 'Unplug cable' : 'Reconnect cable';
    cableButton.setAttribute('aria-pressed', String(!state.cableConnected));
    cameraButtons.forEach(button => { button.disabled = state.held || state.moving; });
    changed();
  }
  function lift() {
    if (state.held || state.moving || !canInteract()) return;
    zoom = 1;
    pan.set(0, 0);
    controls.enableDamping = false; controls.update(); controls.enableDamping = true;
    controls.enabled = false;
    state.held = state.moving = true;
    motion = { start: performance.now(), position: gpu.position.clone(), rotation: gpu.quaternion.clone(), returning: false };
    sound.play('pickup'); updateButtons(); requestRender();
  }
  function putDown() {
    if (!state.held || state.moving || !canInteract()) return;
    state.held = false; state.moving = true;
    motion = { start: performance.now(), position: gpu.position.clone(), rotation: gpu.quaternion.clone(), returning: true };
    updateButtons(); requestRender();
  }
  function toggleCable() {
    if (cableMotion || state.moving || !canInteract()) return;
    const decision = checkCable(!state.cableConnected);
    if (!decision.allowed) { document.querySelector('#interaction-status')!.textContent = decision.reason; return; }
    state.cableConnected = !state.cableConnected;
    cableMotion = { start: performance.now(), from: cableProgress, to: state.cableConnected ? 0 : 1 };
    sound.play(state.cableConnected ? 'plug' : 'unplug');
    updateButtons(); requestRender();
  }
  button.addEventListener('click', putDown);
  cableButton.addEventListener('click', toggleCable);

  return {
    state, lift, putDown, toggleCable,
    get busy() { return Boolean(motion || cableMotion); },
    rotate(dx: number, dy: number) {
      if (!state.held || state.moving || !canInteract()) return;
      const up = new THREE.Vector3(0, 1, 0).applyQuaternion(camera.quaternion);
      const right = new THREE.Vector3(1, 0, 0).applyQuaternion(camera.quaternion);
      gpu.quaternion.premultiply(new THREE.Quaternion().setFromAxisAngle(up, dx * .009));
      gpu.quaternion.premultiply(new THREE.Quaternion().setFromAxisAngle(right, dy * .009));
      gpu.quaternion.normalize(); requestRender();
    },
    gesture(scale: number, dx: number, dy: number, width: number, height: number) {
      if (!state.held || state.moving || !canInteract()) return;
      zoom = THREE.MathUtils.clamp(zoom * scale, .42, 1.5);
      const distance = Math.max(11, 3.9 / (Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) * Math.min(1, camera.aspect))) * zoom;
      const viewHeight = 2 * distance * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
      pan.x = THREE.MathUtils.clamp(pan.x + dx / width * viewHeight * camera.aspect, -4, 4);
      pan.y = THREE.MathUtils.clamp(pan.y - dy / height * viewHeight, -3, 3);
      requestRender();
    },
    update(now: number) {
      if (motion) {
        const t = reducedMotion ? 1 : Math.min((now - motion.start) / 480, 1);
        const ease = t * t * (3 - 2 * t);
        const rotation = motion.returning ? home.rotation : camera.quaternion.clone().multiply(new THREE.Quaternion().setFromEuler(new THREE.Euler(.95, -.12, -.08)));
        gpu.position.lerpVectors(motion.position, motion.returning ? home.position : inspectionPosition(), ease);
        gpu.quaternion.slerpQuaternions(motion.rotation, rotation, ease);
        if (t === 1) {
          if (motion.returning) { controls.enabled = true; sound.play('place'); }
          state.moving = false; motion = null; updateButtons();
        }
      } else if (state.held) gpu.position.copy(inspectionPosition());
      if (cableMotion) {
        const t = reducedMotion ? 1 : Math.min((now - cableMotion.start) / 240, 1);
        cableProgress = THREE.MathUtils.lerp(cableMotion.from, cableMotion.to, t * t * (3 - 2 * t));
        plug.position.copy(plugHome.position).addScaledVector(displacement, cableProgress);
        plug.quaternion.copy(plugHome.rotation).multiply(new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(1, 0, 0), -.22 * cableProgress));
        for (const { wire, positions, original, weights } of wires) {
          for (let i = 0; i < positions.count; i++) {
            positions.setXYZ(i, original[i*3], original[i*3+1] + displacement.y * cableProgress * weights[i], original[i*3+2] + displacement.z * cableProgress * weights[i]);
          }
          positions.needsUpdate = true;
          wire.geometry.computeVertexNormals(); wire.geometry.computeBoundingSphere(); wire.geometry.computeBoundingBox();
        }
        if (t === 1) cableMotion = null;
      }
      return Boolean(motion || cableMotion);
    },
    dispose() {
      button.removeEventListener('click', putDown); cableButton.removeEventListener('click', toggleCable);
      wires.forEach(wire => wire.originalGeometry.dispose());
    },
  };
}
