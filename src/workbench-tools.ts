import * as THREE from 'three';
import type { Workbench } from './workbench';
import type { WorkbenchSound } from './sound';

export type ToolId = 'screwdriver' | 'blower' | 'dev-blower' | 'scraper';
type ToolLocation = 'toolbox' | 'held' | 'desk';

/** One shared inventory and animation path for every workbench tool. */
export function createWorkbenchTools(scene: THREE.Scene, camera: THREE.PerspectiveCamera, bench: Workbench,
  sound: WorkbenchSound, reducedMotion: boolean, canUse: (id: ToolId) => boolean,
  changed: () => void, notify: (text: string) => void, requestRender: () => void) {
  const objects = { screwdriver: bench.screwdriver, blower: bench.blower,
    'dev-blower': bench.devBlower, scraper: bench.scraper };
  const homes = { screwdriver: bench.homePosition, blower: bench.blowerHomePosition,
    'dev-blower': bench.devBlowerHomePosition, scraper: bench.scraperHomePosition };
  const state = {
    open: false, lidProgress: 0,
    locations: { screwdriver: 'toolbox', blower: 'toolbox', 'dev-blower': 'toolbox', scraper: 'toolbox' } as Record<ToolId, ToolLocation>,
    get tool() { return this.locations.screwdriver; },
    get equippedTool(): ToolId | null {
      return (Object.keys(this.locations) as ToolId[]).find(id => this.locations[id] === 'held') ?? null;
    },
  };
  let lidMotion: { from: number; to: number; start: number } | null = null;
  let motion: { id: ToolId; from: THREE.Vector3; to: THREE.Vector3; rotation: THREE.Quaternion; start: number } | null = null;
  let pending: ToolId | null = null;
  function heldPose() {
    const halfHeight = 2.3 * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
    const halfWidth = halfHeight * camera.aspect;
    return { position: new THREE.Vector3(halfWidth * .55, -halfHeight * .43, -2.3), scale: Math.min(.36, halfWidth * .58) };
  }
  function toggleBox() {
    if (lidMotion) return;
    state.open = !state.open;
    sound.play(state.open ? 'open' : 'close');
    lidMotion = { from: state.lidProgress, to: state.open ? 1 : 0, start: performance.now() };
    changed(); requestRender();
  }
  function animate(id: ToolId, parent: THREE.Object3D, to: THREE.Vector3, rotation = new THREE.Quaternion()) {
    const object = objects[id]; parent.attach(object);
    motion = { id, from: object.position.clone(), to, rotation, start: performance.now() };
    object.traverse(child => { if (child instanceof THREE.Mesh) child.castShadow = state.locations[id] !== 'held'; });
    requestRender();
  }
  function grab(id: ToolId) {
    if (state.equippedTool || motion || !canUse(id) || (state.locations[id] === 'toolbox' && state.lidProgress < .98)) return;
    state.locations[id] = 'held'; sound.play('pickup');
    animate(id, camera, heldPose().position, new THREE.Quaternion().setFromEuler(new THREE.Euler(.1, -.2,
      id === 'blower' || id === 'dev-blower' ? 2.2 : .9)));
    changed();
  }
  function returnTool(id: ToolId | null = state.equippedTool) {
    if (!id || state.locations[id] === 'toolbox' || motion || !canUse(id)) return;
    pending = null;
    if (!state.open && !lidMotion) toggleBox();
    state.locations[id] = 'toolbox'; sound.play('place');
    animate(id, bench.toolbox, homes[id].clone()); changed();
  }
  function equip(id: ToolId) {
    if (motion || pending || !canUse(id) || state.equippedTool === id) return;
    if (state.equippedTool) returnTool();
    pending = id;
    if (state.locations[id] === 'toolbox' && !state.open && !lidMotion) toggleBox();
    changed(); requestRender();
  }
  function place(point: THREE.Vector3, obstacles: THREE.Object3D[]) {
    const id = state.equippedTool;
    if (!id || motion || !canUse(id)) return;
    const large = id === 'dev-blower';
    const target = new THREE.Vector3(THREE.MathUtils.clamp(point.x, -8.5, 8.5), point.y + (large ? .37 : .205), THREE.MathUtils.clamp(point.z, -5.4, 5.4));
    const proposed = new THREE.Box3(target.clone().add(new THREE.Vector3(large ? -1.45 : -1.35, large ? -.35 : -.19, large ? -.4 : -.25)),
      target.clone().add(new THREE.Vector3(large ? 1.45 : 1.35, large ? .35 : .22, large ? .4 : .25)));
    if (obstacles.some(object => object !== objects[id] && proposed.intersectsBox(new THREE.Box3().setFromObject(object)))) {
      notify('Choose a clear spot on the desk.'); return;
    }
    state.locations[id] = 'desk'; sound.play('place'); animate(id, scene, target); changed();
  }
  return {
    state, objects, equip, grab, returnTool, toggleBox, place,
    get busy() { return Boolean(motion || pending); },
    get lidMoving() { return Boolean(lidMotion); },
    aimBlower(x: number, y: number, width: number, height: number) {
      const id = state.equippedTool;
      if ((id !== 'blower' && id !== 'dev-blower') || motion) return;
      const halfH = 2.3 * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
      const object = objects[id];
      object.position.set((x / width * 2 - 1) * halfH * camera.aspect + .25, (1 - y / height * 2) * halfH - .34, -2.3);
      object.quaternion.setFromEuler(new THREE.Euler(0, 0, 2.2)); object.scale.setScalar(id === 'dev-blower' ? .48 : .43);
    },
    update(now: number, delta: number) {
      if (lidMotion) {
        const t = reducedMotion ? 1 : Math.min((now - lidMotion.start) / 550, 1);
        state.lidProgress = THREE.MathUtils.lerp(lidMotion.from, lidMotion.to, t * t * (3 - 2 * t));
        bench.lid.rotation.x = -state.lidProgress * 1.72;
        if (t === 1) lidMotion = null;
      }
      if (pending && !motion && !lidMotion) {
        if (state.locations[pending] === 'toolbox' && !state.open) toggleBox();
        else { const id = pending; pending = null; grab(id); }
      }
      if (motion) {
        const object = objects[motion.id], t = reducedMotion ? 1 : Math.min((now - motion.start) / 320, 1);
        object.position.lerpVectors(motion.from, motion.to, 1 - (1 - t) ** 3);
        object.quaternion.slerp(motion.rotation, t === 1 ? 1 : 1 - Math.exp(-18 * delta));
        const scale = state.locations[motion.id] === 'held' ? heldPose().scale : 1;
        object.scale.lerp(new THREE.Vector3(scale, scale, scale), t === 1 ? 1 : .3);
        if (t === 1) {
          object.position.copy(motion.to); object.quaternion.copy(motion.rotation); object.scale.setScalar(scale);
          motion = null; changed();
        }
      }
      const id = state.equippedTool;
      if (id && !motion) { const pose = heldPose(); objects[id].position.copy(pose.position); objects[id].scale.setScalar(pose.scale); }
    },
  };
}
