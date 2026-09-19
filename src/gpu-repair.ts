import * as THREE from 'three';
import type { WorkbenchSound } from './sound';

/** Keeps the original parent and local transform so servicing never accumulates drift. */
export function setupGPURepair(scene: THREE.Scene, gpu: THREE.Object3D, sound: WorkbenchSound,
  reducedMotion: boolean, cableConnected: () => boolean, toolHeld: () => boolean,
  ready: () => boolean, setGPUDown: () => void, notify: (text: string) => void, changed: () => void) {
  const state = { heldPart: null as string | null, moving: false, removed: [] as string[] };
  gpu.updateMatrixWorld(true);
  const names = ['fan-assembly', 'cooler-assembly', ...['fan', 'cooler'].flatMap(kind =>
    Array.from({ length: 4 }, (_, i) => `${kind}-screw-${i + 1}`))];
  const parts = new Map(names.map(name => {
    const object = gpu.getObjectByName(name)!;
    object.userData.action = name.includes('screw') ? 'screw' : 'assembly';
    if (name.includes('screw')) {
      const pick = new THREE.Mesh(new THREE.SphereGeometry(.11, 12, 8), new THREE.MeshBasicMaterial({ visible: false }));
      pick.name = `${name}-pick-target`; object.add(pick);
    }
    return [name, { object, parent: object.parent!, position: object.position.clone(),
      rotation: object.quaternion.clone(), scale: object.scale.clone(),
      upright: object.getWorldQuaternion(new THREE.Quaternion()) }];
  }));
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
  let motion: { object: THREE.Object3D; from: THREE.Vector3; to: THREE.Vector3;
    rotation: THREE.Quaternion; toRotation: THREE.Quaternion; start: number; screw: boolean;
    done: () => void } | null = null;
  const turns = new Map<string, { progress: number; reinstall: boolean; from: THREE.Vector3; rotation: THREE.Quaternion }>();
  let activeTurn: { name: string; lastTime: number } | null = null;
  const screwAxis = new THREE.Vector3(0, 1, 0);
  const removed = (name: string) => state.removed.includes(name);
  const fanOff = () => removed('fan-assembly');
  const coolerOff = () => removed('cooler-assembly');

  function refresh() {
    const count = ['fan', 'cooler'].map(kind => state.removed.filter(name => name.startsWith(`${kind}-screw`)).length);
    progress.textContent = `Fan screws ${count[0]}/4 removed · Cooler screws ${count[1]}/4 removed`;
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
    if (!toolHeld()) { notify('Pick up the screwdriver to remove or refit a screw.'); return false; }
    const part = parts.get(name);
    if (!part || !name.includes('screw')) return false;
    const fanScrew = name.startsWith('fan-');
    const reinstall = removed(name);
    if (reinstall && (fanScrew ? fanOff() : coolerOff())) {
      notify(`Refit the ${fanScrew ? 'fan' : 'cooler'} before tightening its screws.`); return false;
    }
    if (!reinstall && !fanScrew && cableConnected()) {
      notify('Unplug the fan cable before removing the rear cooler screws.'); return false;
    }
    if (!turns.has(name)) {
      if (reinstall) scene.attach(part.object);
      turns.set(name, { progress: 0, reinstall, from: part.object.position.clone(), rotation: part.object.quaternion.clone() });
    }
    activeTurn = { name, lastTime: performance.now() };
    state.moving = true;
    sound.startUnscrew();
    refresh(); changed();
    notify(`Hold to ${reinstall ? 'tighten' : 'remove'} ${fanScrew ? 'fan' : 'cooler'} screw ${name.slice(-1)}.`);
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
    const fanScrew = name.startsWith('fan-');
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
      const index = Number(name.slice(-1)) - 1;
      // Separate labelled rows keep every screw reachable and associated with its original hole.
      animate(part.object, new THREE.Vector3(3.1 + index * .48, .20, fanScrew ? 3.38 : 4.12),
        new THREE.Quaternion().setFromEuler(new THREE.Euler(0, 0, Math.PI / 2)), true,
        () => notify(`${fanScrew ? 'Fan' : 'Cooler'} screw ${index + 1} in the parts tray. Hold it with the screwdriver to refit.`));
    }
  }
  function assembly(name: string) {
    if (!ready() || state.moving || state.heldPart) return;
    if (toolHeld()) { notify('Set the screwdriver down before picking up the assembly.'); return; }
    const part = parts.get(name)!;
    if (!removed(name)) {
      if (cableConnected()) { notify('Unplug the fan cable first.'); return; }
      const kind = name === 'fan-assembly' ? 'fan' : 'cooler';
      const remaining = Array.from({ length: 4 }, (_, i) => `${kind}-screw-${i + 1}`).filter(id => !removed(id));
      if (remaining.length) { notify(`Remove the ${remaining.length} remaining ${kind} screw${remaining.length === 1 ? '' : 's'} with the screwdriver first.`); return; }
      state.removed.push(name);
    }
    scene.attach(part.object);
    if (name === 'fan-assembly') settleCable(true);
    setGPUDown();
    state.heldPart = name;
    const target = part.object.position.clone().add(new THREE.Vector3(0, 1.2, 0));
    animate(part.object, target, part.upright, false, () => notify(`${name === 'fan-assembly' ? 'Fan and cable' : 'Cooler'} lifted · click a clear spot on the desk to place · Esc to refit`));
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
      state.heldPart = null; sound.play('place'); notify('Assembly on the desk · click to pick up, or use Refit to reconnect it to its mounts.');
    });
  }
  function refit() {
    if (!ready() || state.moving) return;
    if (toolHeld()) { notify('Set the screwdriver down before refitting the assembly.'); return; }
    const name = state.heldPart ?? (coolerOff() ? 'cooler-assembly' : fanOff() ? 'fan-assembly' : null);
    if (!name) return;
    const part = parts.get(name)!;
    if (name === 'fan-assembly' && coolerOff()) { notify('Refit the cooler first. Place the fan on the desk, then refit the cooler.'); return; }
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
    state, beginScrew, endScrew, assembly, place, refit, removed,
    canConnect: () => !fanOff() && !coolerOff() && !state.moving,
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
          part.object.position.copy(part.position).addScaledVector(screwAxis, .34 * turn.progress);
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
    dispose() { endScrew(); button.removeEventListener('click', refit); fanButton.removeEventListener('click', liftFan); },
  };
}
