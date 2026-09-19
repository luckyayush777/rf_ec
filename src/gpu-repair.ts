import * as THREE from 'three';
import type { WorkbenchSound } from './sound';
import type { PartMetadata } from './gpu';
import { createServiceRules, gpuServiceExceptions, type ServiceAction, type ServicePart } from './service-rules';

/** Keeps the original parent and local transform so servicing never accumulates drift. */
export function setupGPURepair(scene: THREE.Scene, gpu: THREE.Object3D, sound: WorkbenchSound,
  reducedMotion: boolean, isConnected: (part: string) => boolean, toolHeld: () => boolean,
  ready: () => boolean, setGPUDown: () => void, notify: (text: string) => void, changed: () => void) {
  const state = { heldPart: null as string | null, moving: false, removed: [] as string[] };
  gpu.updateMatrixWorld(true);
  const serviceObjects: THREE.Object3D[] = [];
  gpu.traverse(object => {
    const role = (object.userData.part as PartMetadata | undefined)?.role;
    if (object !== gpu && (role === 'assembly' || role === 'fastener')) serviceObjects.push(object);
  });
  const parts = new Map(serviceObjects.map(object => {
    const role = (object.userData.part as PartMetadata).role;
    object.userData.action = role === 'fastener' ? 'screw' : 'assembly';
    if (role === 'fastener') {
      const pick = new THREE.Mesh(new THREE.SphereGeometry(.11, 12, 8), new THREE.MeshBasicMaterial({ visible: false }));
      pick.name = `${object.name}-pick-target`; object.add(pick);
    }
    return [object.name, { object, parent: object.parent!, position: object.position.clone(),
      rotation: object.quaternion.clone(), scale: object.scale.clone(),
      upright: object.getWorldQuaternion(new THREE.Quaternion()) }];
  }));
  const fastenersFor = (assembly: string) =>
    ((parts.get(assembly)?.object.userData.part as PartMetadata | undefined)?.requires ?? [])
      .filter(id => (parts.get(id)?.object.userData.part as PartMetadata | undefined)?.role === 'fastener');
  const fanScrews = fastenersFor('fan-assembly');
  const coolerScrews = fastenersFor('cooler-assembly');
  const holeMaterial = new THREE.MeshStandardMaterial({ color: '#111a1b', metalness: .2, roughness: .85 });
  const holeRimMaterial = new THREE.MeshStandardMaterial({ color: '#9ca5a4', metalness: .7, roughness: .4 });
  const holeGeometry = new THREE.CircleGeometry(.059, 32);
  const holeRimGeometry = new THREE.RingGeometry(.057, .092, 32);
  const coolerHoles: THREE.Group[] = [];
  for (const name of coolerScrews) {
    const part = parts.get(name)!;
    const outward = new THREE.Vector3(0, 1, 0).applyQuaternion(part.rotation);
    const hole = new THREE.Group();
    hole.name = `${name}-hole`;
    hole.position.copy(part.position).addScaledVector(outward, -.052);
    hole.quaternion.copy(part.rotation);
    const recess = new THREE.Mesh(holeGeometry, holeMaterial);
    recess.rotation.x = -Math.PI / 2;
    recess.position.y = .002;
    recess.userData.noHighlight = true;
    const rim = new THREE.Mesh(holeRimGeometry, holeRimMaterial);
    rim.rotation.x = -Math.PI / 2;
    rim.position.y = .004;
    rim.userData.noHighlight = true;
    hole.add(recess, rim);
    part.parent.add(hole);
    coolerHoles.push(hole);
  }
  const plug = gpu.getObjectByName('fan-plug')!;
  const wireMeshes = ['fan-positive-wire', 'fan-ground-wire'].map(name => gpu.getObjectByName(name) as THREE.Mesh<THREE.BufferGeometry>);
  let looseCable: { plug: THREE.Vector3; wires: Float32Array[] } | null = null;
  function settleCable(loose: boolean) {
    if (loose && !looseCable) {
      looseCable = { plug: plug.position.clone(), wires: wireMeshes.map(wire => Float32Array.from(wire.geometry.getAttribute('position').array)) };
      const plane = parts.get('fan-assembly')!.position.y - .035;
      plug.position.y = plane;
      wireMeshes.forEach(wire => {
        const positions = wire.geometry.getAttribute('position');
        for (let i = 0; i < positions.count; i++) positions.setY(i, plane + (positions.getY(i) - looseCable!.plug.y) * .13);
        positions.needsUpdate = true; wire.geometry.computeVertexNormals(); wire.geometry.computeBoundingBox(); wire.geometry.computeBoundingSphere();
      });
    } else if (!loose && looseCable) {
      plug.position.copy(looseCable.plug);
      wireMeshes.forEach((wire, index) => {
        const positions = wire.geometry.getAttribute('position') as THREE.BufferAttribute;
        positions.copyArray(looseCable!.wires[index]); positions.needsUpdate = true;
        wire.geometry.computeVertexNormals(); wire.geometry.computeBoundingBox(); wire.geometry.computeBoundingSphere();
      });
      looseCable = null;
    }
  }
  const button = document.querySelector<HTMLButtonElement>('#return-part')!;
  const fanButton = document.querySelector<HTMLButtonElement>('#remove-fan')!;
  const progress = document.querySelector<HTMLElement>('#repair-progress')!;
  const touchInput = window.matchMedia('(pointer: coarse)').matches || window.innerWidth <= 640;
  let motion: { object: THREE.Object3D; from: THREE.Vector3; to: THREE.Vector3;
    rotation: THREE.Quaternion; toRotation: THREE.Quaternion; start: number; screw: boolean;
    done: () => void } | null = null;
  const turns = new Map<string, { progress: number; reinstall: boolean; from: THREE.Vector3; rotation: THREE.Quaternion }>();
  let activeTurn: { name: string; lastTime: number } | null = null;
  const screwAxis = new THREE.Vector3(0, 1, 0);
  const removed = (name: string) => state.removed.includes(name);
  const fanOff = () => removed('fan-assembly');
  const coolerOff = () => removed('cooler-assembly');
  const serviceParts: ServicePart[] = [...parts].map(([id, part]) => {
    const metadata = part.object.userData.part as PartMetadata | undefined;
    const kind: ServicePart['kind'] = metadata?.role === 'fastener' ? 'fastener' : 'assembly';
    if (!metadata || (kind === 'assembly' && !Array.isArray(metadata.requires))) {
      throw new Error(`Missing service metadata for ${id}.`);
    }
    return { id, kind, parent: part.parent.name, requires: metadata.requires ?? [] };
  });
  for (const id of new Set(serviceParts.flatMap(part => part.requires))) {
    if (parts.has(id)) continue;
    const object = gpu.getObjectByName(id);
    const metadata = object?.userData.part as PartMetadata | undefined;
    if (!object || metadata?.role !== 'removable') throw new Error(`Missing service connector: ${id}.`);
    serviceParts.push({ id, kind: 'connector', parent: object.parent?.name, requires: metadata.requires ?? [] });
  }
  const service = createServiceRules(serviceParts, gpuServiceExceptions);
  const check = (action: ServiceAction) => service.check(action, {
    isRemoved: removed, isConnected, toolHeld: toolHeld(),
  });

  function refresh() {
    const count = (screws: string[]) => screws.filter(removed).length;
    progress.textContent = `Fan screws ${count(fanScrews)}/${fanScrews.length} removed · Cooler screws ${count(coolerScrews)}/${coolerScrews.length} removed`;
    button.hidden = !state.heldPart && !fanOff() && !coolerOff();
    const next = state.heldPart ?? (coolerOff() ? 'cooler-assembly' : 'fan-assembly');
    button.textContent = `Refit ${next === 'fan-assembly' ? 'fan' : 'cooler'}`;
    button.disabled = state.moving;
    fanButton.textContent = fanOff() ? 'Pick up fan' : 'Lift fan';
    fanButton.disabled = state.moving || Boolean(state.heldPart);
  }
  function animate(object: THREE.Object3D, to: THREE.Vector3, rotation: THREE.Quaternion, screw: boolean, done: () => void) {
    state.moving = true;
    motion = { object, from: object.position.clone(), to, rotation: object.quaternion.clone(),
      toRotation: rotation, start: performance.now(), screw, done };
    refresh(); changed();
  }
  function beginScrew(name: string) {
    if (!ready() || state.moving || state.heldPart || activeTurn) return false;
    const part = parts.get(name);
    if (!part || (part.object.userData.part as PartMetadata).role !== 'fastener') return false;
    const fanScrew = fanScrews.includes(name);
    const reinstall = removed(name);
    const decision = check({ kind: reinstall ? 'refit' : 'remove', part: name });
    if (!decision.allowed) { notify(decision.reason); return false; }
    if (!turns.has(name)) {
      if (reinstall) scene.attach(part.object);
      turns.set(name, { progress: 0, reinstall, from: part.object.position.clone(), rotation: part.object.quaternion.clone() });
    }
    activeTurn = { name, lastTime: performance.now() };
    state.moving = true;
    sound.startUnscrew();
    refresh(); changed();
    notify(`Hold to ${reinstall ? 'tighten' : 'remove'} ${fanScrew ? 'fan' : 'cooler'} screw ${(fanScrew ? fanScrews : coolerScrews).indexOf(name) + 1}.`);
    return true;
  }
  function endScrew() {
    if (!activeTurn) return;
    const { name } = activeTurn;
    activeTurn = null;
    state.moving = false;
    sound.stopUnscrew();
    const turn = turns.get(name);
    refresh(); changed();
    if (turn) notify(`${Math.round(turn.progress * 100)}% ${turn.reinstall ? 'tightened' : 'removed'} · hold the screw to continue.`);
  }
  function completeScrew(name: string) {
    const part = parts.get(name)!;
    const turn = turns.get(name)!;
    activeTurn = null;
    turns.delete(name);
    sound.stopUnscrew();
    const fanScrew = fanScrews.includes(name);
    if (turn.reinstall) {
      part.parent.add(part.object); part.object.position.copy(part.position);
      part.object.quaternion.copy(part.rotation); part.object.scale.copy(part.scale);
      state.removed = state.removed.filter(item => item !== name);
      state.moving = false;
      refresh(); changed();
      notify(`${fanScrew ? 'Fan' : 'Cooler'} screw refitted.`);
    } else {
      state.removed.push(name);
      scene.attach(part.object);
      const index = (fanScrew ? fanScrews : coolerScrews).indexOf(name);
      // Separate labelled rows keep every screw reachable and associated with its original hole.
      animate(part.object, new THREE.Vector3(3.1 + index * .48, .20, fanScrew ? 3.38 : 4.12),
        new THREE.Quaternion().setFromEuler(new THREE.Euler(0, 0, Math.PI / 2)), true,
        () => notify(`${fanScrew ? 'Fan' : 'Cooler'} screw ${index + 1} in the parts tray. Hold it with the screwdriver to refit.`));
    }
  }
  function assembly(name: string) {
    if (!ready() || state.moving || state.heldPart) return;
    const part = parts.get(name)!;
    const decision = check({ kind: removed(name) ? 'pickup' : 'remove', part: name });
    if (!decision.allowed) { notify(decision.reason); return; }
    if (!removed(name)) {
      state.removed.push(name);
    }
    scene.attach(part.object);
    if (name === 'fan-assembly') settleCable(true);
    setGPUDown();
    state.heldPart = name;
    const target = part.object.position.clone().add(new THREE.Vector3(0, 1.2, 0));
    animate(part.object, target, part.upright, false, () => notify(`${name === 'fan-assembly' ? 'Fan and cable' : 'Cooler'} lifted · ${touchInput ? 'tap' : 'click'} a clear spot on the desk to place · ${touchInput ? 'use Refit to return' : 'Esc to refit'}`));
    sound.play('pickup');
  }
  function place(point: THREE.Vector3, obstacles: THREE.Object3D[]) {
    if (!state.heldPart || state.moving || !ready()) return;
    const part = parts.get(state.heldPart)!;
    const bounds = new THREE.Box3().setFromObject(part.object);
    const offset = point.clone().sub(bounds.getCenter(new THREE.Vector3()));
    offset.y = point.y + .025 - bounds.min.y;
    const proposed = bounds.clone().translate(offset);
    if (proposed.min.x < -9.75 || proposed.max.x > 9.75 || proposed.min.z < -5.75 || proposed.max.z > 5.75 ||
      obstacles.some(object => object !== part.object && proposed.intersectsBox(new THREE.Box3().setFromObject(object).expandByScalar(.08)))) {
      notify('Choose a clear spot with room for the whole assembly and its cable.'); return;
    }
    animate(part.object, part.object.position.clone().add(offset), part.upright, false, () => {
      state.heldPart = null; sound.play('place'); notify(`Assembly on the desk · ${touchInput ? 'tap' : 'click'} to pick up, or use Refit to reconnect it to its mounts.`);
    });
  }
  function refit() {
    if (!ready() || state.moving) return;
    const name = state.heldPart ?? (coolerOff() ? 'cooler-assembly' : fanOff() ? 'fan-assembly' : null);
    if (!name) return;
    const part = parts.get(name)!;
    const decision = check({ kind: 'refit', part: name });
    if (!decision.allowed) { notify(decision.reason); return; }
    part.parent.updateWorldMatrix(true, false);
    animate(part.object, part.parent.localToWorld(part.position.clone()),
      part.parent.getWorldQuaternion(new THREE.Quaternion()).multiply(part.rotation), false, () => {
        part.parent.add(part.object); part.object.position.copy(part.position);
        part.object.quaternion.copy(part.rotation); part.object.scale.copy(part.scale);
        state.removed = state.removed.filter(item => item !== name); state.heldPart = null;
        if (name === 'fan-assembly') settleCable(false);
        sound.play('place'); notify('Assembly seated · use the screwdriver to refit its screws from the tray.');
      });
  }
  const liftFan = () => assembly('fan-assembly');
  button.addEventListener('click', refit); fanButton.addEventListener('click', liftFan);
  refresh();
  return {
    state, beginScrew, endScrew, assembly, place, refit, removed, check,
    looseObjects: () => [...parts.values()].map(p => p.object).filter(o => removed(o.name)),
    update(now: number) {
      if (activeTurn) {
        const { name } = activeTurn;
        const part = parts.get(name)!;
        const turn = turns.get(name)!;
        turn.progress = Math.min(1, turn.progress + Math.max(0, now - activeTurn.lastTime) / 1500);
        activeTurn.lastTime = now;
        if (turn.reinstall) {
          part.parent.updateWorldMatrix(true, false);
          part.object.position.lerpVectors(turn.from, part.parent.localToWorld(part.position.clone()), turn.progress);
          part.object.position.y += Math.sin(Math.PI * turn.progress) * .35;
          part.object.quaternion.slerpQuaternions(turn.rotation,
            part.parent.getWorldQuaternion(new THREE.Quaternion()).multiply(part.rotation), turn.progress);
          part.object.rotateY(-Math.PI * 6 * turn.progress);
        } else {
          const outward = screwAxis.clone().applyQuaternion(part.rotation);
          part.object.position.copy(part.position).addScaledVector(outward, .34 * turn.progress);
          part.object.quaternion.copy(part.rotation).multiply(new THREE.Quaternion().setFromAxisAngle(screwAxis, Math.PI * 6 * turn.progress));
        }
        if (turn.progress === 1) completeScrew(name);
      }
      if (!motion) return Boolean(activeTurn);
      const t = reducedMotion ? 1 : Math.min((now - motion.start) / (motion.screw ? 680 : 450), 1);
      const ease = t * t * (3 - 2 * t);
      motion.object.position.lerpVectors(motion.from, motion.to, ease);
      motion.object.position.y += Math.sin(Math.PI * t) * (motion.screw ? .7 : .5);
      motion.object.quaternion.slerpQuaternions(motion.rotation, motion.toRotation, ease);
      if (motion.screw) motion.object.rotateY(Math.PI * 8 * t);
      if (t === 1) {
        motion.object.quaternion.copy(motion.toRotation);
        const done = motion.done; motion = null; state.moving = false; done(); refresh();
      }
      return Boolean(motion);
    },
    dispose() {
      endScrew();
      button.removeEventListener('click', refit); fanButton.removeEventListener('click', liftFan);
      coolerHoles.forEach(hole => hole.removeFromParent());
      holeGeometry.dispose(); holeRimGeometry.dispose(); holeMaterial.dispose(); holeRimMaterial.dispose();
    },
  };
}
