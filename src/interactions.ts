import * as THREE from 'three';
import type { Workbench } from './workbench';
import type { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import type { WorkbenchSound } from './sound';
import { setupGPUInspection } from './gpu-inspection';
import { setupGPURepair } from './gpu-repair';
import { createInteractionHighlight } from './interaction-highlight';

type ToolLocation = 'toolbox' | 'held' | 'desk';

export function setupInteractions(scene: THREE.Scene, camera: THREE.PerspectiveCamera,
  canvas: HTMLCanvasElement, bench: Workbench, gpu: THREE.Object3D, controls: OrbitControls, sound: WorkbenchSound,
  requestRender: () => void, reducedMotion: boolean, isFocusMode: () => boolean) {
  const status = document.querySelector<HTMLElement>('#interaction-status')!;
  const toolboxButton = document.querySelector<HTMLButtonElement>('#toggle-toolbox')!;
  const returnButton = document.querySelector<HTMLButtonElement>('#return-tool')!;
  const equipButton = document.querySelector<HTMLButtonElement>('#equip-tool')!;
  const equippedLabel = document.querySelector<HTMLElement>('#equipped-tool')!;
  const touchInput = window.matchMedia('(pointer: coarse)').matches || window.innerWidth <= 640;
  const raycaster = new THREE.Raycaster();
  const pointer = new THREE.Vector2();
  const state = {
    open: false, tool: 'toolbox' as ToolLocation, lidProgress: 0,
    get equippedTool(): 'screwdriver' | null { return this.tool === 'held' ? 'screwdriver' : null; },
  };
  let lastTime = 0;
  let lidMotion: { from: number; to: number; start: number } | null = null;
  let toolMotion: { start: number; from: THREE.Vector3; to: THREE.Vector3; rotation: THREE.Quaternion } | null = null;
  function isConnected(id: string) {
    if (id !== 'fan-plug') throw new Error(`Missing connection state for ${id}.`);
    return inspection.state.cableConnected;
  }

  const inspection = setupGPUInspection(gpu, camera, controls, sound, requestRender, reducedMotion, message,
    () => !repair.state.moving && !repair.state.heldPart && !toolMotion,
    connect => repair.check({ kind: connect ? 'connect' : 'disconnect', part: 'fan-plug' }));
  const repair = setupGPURepair(scene, gpu, sound, reducedMotion, isConnected,
    () => state.equippedTool === 'screwdriver', () => !inspection.busy && !toolMotion, () => inspection.putDown(),
    text => { status.textContent = text; }, message, isFocusMode);
  const highlight = createInteractionHighlight();
  const placementPreview = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), new THREE.MeshBasicMaterial({
    color: '#7fd9ae', transparent: true, opacity: .35, depthWrite: false, side: THREE.DoubleSide,
  }));
  placementPreview.name = 'placement-preview';
  placementPreview.rotation.x = -Math.PI / 2;
  placementPreview.renderOrder = 5;
  placementPreview.visible = false;
  scene.add(placementPreview);
  const inspectButton = document.querySelector<HTMLButtonElement>('#inspect-gpu')!;
  const fanButton = document.querySelector<HTMLButtonElement>('#remove-fan')!;
  const storePartButton = document.querySelector<HTMLButtonElement>('#store-part')!;
  const focusRefitButton = document.querySelector<HTMLButtonElement>('#focus-refit-screw')!;
  inspectButton.addEventListener('click', inspection.lift);

  function placementObstacles() {
    return [gpu, bench.toolbox, bench.screwdriver, scene.getObjectByName('desk-light')!,
      scene.getObjectByName('parts-tray')!, ...repair.looseObjects()];
  }

  let refitPointer: number | null = null;
  function refreshFocusActions() {
    inspectButton.hidden = isFocusMode() && Boolean(repair.state.heldPart || inspection.state.held);
    fanButton.hidden = isFocusMode() && Boolean(repair.state.heldPart || repair.state.stored.includes('fan-assembly'));
    storePartButton.hidden = !isFocusMode() || !repair.state.heldPart;
    storePartButton.disabled = repair.state.moving || inspection.busy;
    focusRefitButton.hidden = !isFocusMode() || (refitPointer === null && !repair.nextRefittableScrew());
  }
  function storePart() { repair.storePart(); refreshFocusActions(); }
  function refitDown(event: PointerEvent) {
    if (refitPointer !== null) return;
    const name = repair.nextRefittableScrew();
    sound.unlock();
    if (!name || !repair.beginScrew(name)) return;
    refitPointer = event.pointerId;
    focusRefitButton.setPointerCapture(event.pointerId);
    event.preventDefault();
  }
  function refitUp(event?: PointerEvent) {
    if (refitPointer === null || (event && event.pointerId !== refitPointer)) return;
    if (focusRefitButton.hasPointerCapture(refitPointer)) focusRefitButton.releasePointerCapture(refitPointer);
    refitPointer = null;
    repair.endScrew();
    refreshFocusActions();
  }
  storePartButton.addEventListener('click', storePart);
  focusRefitButton.addEventListener('pointerdown', refitDown);
  focusRefitButton.addEventListener('pointerup', refitUp);
  focusRefitButton.addEventListener('pointercancel', refitUp);

  function heldPose() {
    const halfHeight = 2.3 * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
    const halfWidth = halfHeight * camera.aspect;
    return {
      position: new THREE.Vector3(halfWidth * .55, -halfHeight * .43, -2.3),
      scale: Math.min(.36, halfWidth * .58),
    };
  }

  function message() {
    const desktopMessage = repair.state.heldPart
      ? 'Assembly lifted · click a clear spot on the desk to place · Esc to refit'
      : inspection.state.held
      ? state.equippedTool === 'screwdriver'
        ? 'GPU held · drag to expose screws · hold a screw to remove / refit · Esc to set down'
        : `GPU held · drag to rotate · equip screwdriver to service screws · click cable to ${inspection.state.cableConnected ? 'unplug' : 'reconnect'}`
      : inspection.state.moving ? 'Setting the GPU down…' : state.equippedTool === 'screwdriver'
      ? 'Screwdriver held · hold a screw to remove / refit · click the desk to place'
      : state.open ? 'Click the screwdriver to pick it up · click the box to close'
      : state.tool === 'desk' ? 'Click the screwdriver to pick it up' : 'Click the GPU to inspect · click the toolbox to open';
    const touchMessage = repair.state.heldPart
      ? 'Part lifted · tap a clear spot on the desk to place · use Refit to return'
      : inspection.state.held
      ? state.equippedTool === 'screwdriver'
        ? 'Drag GPU to find screws · pinch to zoom · move two fingers to pan · hold a screw to turn'
        : `Drag GPU to rotate · pinch to zoom · tap cable to ${inspection.state.cableConnected ? 'unplug' : 'reconnect'}`
      : inspection.state.moving ? 'Setting the GPU down…' : state.equippedTool === 'screwdriver'
      ? 'Hold a screw to turn · tap the desk to place the screwdriver'
      : state.open ? 'Tap the screwdriver to pick it up · tap the box to close'
      : state.tool === 'desk' ? 'Tap the screwdriver to pick it up' : 'Tap the GPU to inspect · tap the toolbox to open';
    const focusMessage = repair.state.heldPart
      ? 'Part lifted · Store part to set it aside, or Refit to return it'
      : inspection.state.held
      ? state.equippedTool === 'screwdriver'
        ? 'Drag GPU to find screws · pinch to zoom · move two fingers to pan · hold a screw to turn it'
        : `Drag GPU to rotate · pinch to zoom · tap cable to ${inspection.state.cableConnected ? 'unplug' : 'reconnect'}`
      : state.equippedTool === 'screwdriver'
      ? 'GPU focus · tap Inspect GPU, then hold a screw to turn it'
      : 'GPU focus · tap Inspect GPU to rotate · equip screwdriver for screws';
    status.textContent = isFocusMode() ? focusMessage : touchInput ? touchMessage : desktopMessage;
    toolboxButton.textContent = state.open ? 'Close toolbox' : 'Open toolbox';
    toolboxButton.setAttribute('aria-expanded', String(state.open));
    returnButton.hidden = state.tool === 'toolbox';
    equippedLabel.textContent = state.equippedTool === 'screwdriver' ? 'Screwdriver' : 'None (empty hands)';
    equipButton.hidden = state.equippedTool === 'screwdriver';
    equipButton.disabled = Boolean(repair.state.heldPart || repair.state.moving || inspection.busy || toolMotion);
    refreshFocusActions();
  }

  function toggleBox() {
    if (lidMotion || repair.state.moving) return;
    state.open = !state.open;
    sound.play(state.open ? 'open' : 'close');
    lidMotion = { from: state.lidProgress, to: state.open ? 1 : 0, start: performance.now() };
    message(); requestRender();
  }

  function animateTool(parent: THREE.Object3D, target: THREE.Vector3, rotation = new THREE.Quaternion()) {
    parent.attach(bench.screwdriver);
    toolMotion = { start: performance.now(), from: bench.screwdriver.position.clone(), to: target, rotation };
    requestRender();
  }

  function grab() {
    if (state.equippedTool || repair.state.heldPart || repair.state.moving || inspection.busy || toolMotion || (state.tool === 'toolbox' && state.lidProgress < .98)) return;
    state.tool = 'held';
    sound.play('pickup');
    bench.screwdriver.traverse(object => { if (object instanceof THREE.Mesh) object.castShadow = false; });
    animateTool(camera, heldPose().position, new THREE.Quaternion().setFromEuler(new THREE.Euler(.1, -.2, .9)));
    message();
  }

  // The toolbar also reaches the tool when the inspected GPU obscures the box.
  let equipPending = false;
  function equipTool() {
    if (repair.state.heldPart || repair.state.moving || inspection.busy || toolMotion) return;
    if (state.tool === 'toolbox' && state.lidProgress < .98) {
      if (lidMotion && !state.open) return;
      if (!state.open) toggleBox();
      equipPending = true; requestRender();
    } else grab();
  }

  function returnTool() {
    if (state.tool === 'toolbox' || toolMotion || repair.state.moving) return;
    if (!state.open) toggleBox();
    state.tool = 'toolbox';
    sound.play('place');
    animateTool(bench.toolbox, bench.homePosition.clone());
    bench.screwdriver.traverse(object => { if (object instanceof THREE.Mesh) object.castShadow = true; });
    message();
  }

  function hitAt(x: number, y: number) {
    const rect = canvas.getBoundingClientRect();
    pointer.set((x - rect.left) / rect.width * 2 - 1, -(y - rect.top) / rect.height * 2 + 1);
    scene.updateMatrixWorld(true);
    raycaster.setFromCamera(pointer, camera);
    const hits = raycaster.intersectObjects(scene.children, true);
    for (const hit of hits) {
      if (hit.object === placementPreview) continue;
      let object: THREE.Object3D | null = hit.object;
      let action: string | undefined;
      let target: THREE.Object3D | undefined;
      let held = false;
      let hidden = false;
      while (object) {
        if (!object.visible) { hidden = true; break; }
        if ((object === bench.screwdriver && state.equippedTool === 'screwdriver') || object.name === repair.state.heldPart) held = true;
        if (!action && object.userData.action) { action = object.userData.action; target = object; }
        object = object.parent;
      }
      if (held || hidden) continue;
      // The nearest solid surface blocks tools behind the closed lid and other props.
      return { hit, action, target };
    }
    return null;
  }

  function click(x: number, y: number) {
    if (toolMotion || inspection.state.moving || repair.state.moving) return;
    highlight.select(null);
    placementPreview.visible = false;
    const result = hitAt(x, y);
    if (repair.state.heldPart) {
      if (result?.action === 'desk') repair.place(result.hit.point, placementObstacles());
      return;
    }
    if (result?.action === 'screw') return;
    else if (result?.action === 'assembly' && result.target) {
      const name = result.target.name;
      if (!inspection.state.held && !repair.removed(name) &&
        !repair.check({ kind: 'remove', part: name }).allowed) inspection.lift();
      else repair.assembly(name);
    } else if (result?.action === 'cable') {
      inspection.toggleCable();
    } else if (result?.action === 'gpu') {
      if (inspection.state.held) status.textContent = 'Unplug the cable, then use the screwdriver on the screws. Drag to see the rear cooler screws.';
      else inspection.lift();
    } else if (result?.action === 'screwdriver') grab();
    else if (result?.action === 'toolbox') {
      if (state.equippedTool === 'screwdriver' && state.open && !lidMotion) returnTool();
      else toggleBox();
    } else if (result?.action === 'desk' && state.equippedTool === 'screwdriver') {
      const point = result.hit.point;
      // Keep the complete tool on the tabletop, away from other components.
      const target = new THREE.Vector3(THREE.MathUtils.clamp(point.x, -8.5, 8.5), point.y + .205, THREE.MathUtils.clamp(point.z, -5.4, 5.4));
      const proposed = new THREE.Box3(target.clone().add(new THREE.Vector3(-1.35, -.19, -.25)), target.clone().add(new THREE.Vector3(1.35, .22, .25)));
      const gpu = scene.getObjectByName('gpu');
      const lamp = scene.getObjectByName('desk-light');
      if ([scene.getObjectByName('parts-tray')!, ...repair.looseObjects()].some(object => proposed.intersectsBox(new THREE.Box3().setFromObject(object))) || (gpu && proposed.intersectsBox(new THREE.Box3().setFromObject(gpu))) || (lamp && proposed.intersectsBox(new THREE.Box3().setFromObject(lamp))) || proposed.intersectsBox(new THREE.Box3().setFromObject(bench.toolbox))) {
        status.textContent = 'Choose a clear spot on the desk.';
        return;
      }
      state.tool = 'desk';
      sound.play('place');
      animateTool(scene, target);
      bench.screwdriver.traverse(object => { if (object instanceof THREE.Mesh) object.castShadow = true; });
      message();
    }
  }

  const pointers = new Map<number, { x: number; y: number }>();
  let pinch: { distance: number; x: number; y: number } | null = null;
  function pinchPosition() {
    const [a, b] = [...pointers.values()];
    if (!a || !b) return null;
    return { distance: Math.hypot(a.x - b.x, a.y - b.y), x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
  }
  let press: { x: number; y: number; lastX: number; lastY: number; moved: boolean;
    screw: boolean; restoreControls: boolean } | null = null;
  function finishScrew() {
    if (!press?.screw) return;
    repair.endScrew();
    if (press.restoreControls) controls.enabled = true;
  }
  function down(event: PointerEvent) {
    sound.unlock();
    hover(event.clientX, event.clientY, event.pointerType);
    pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (pointers.size > 1) {
      if (press) { finishScrew(); press.moved = true; }
      if (inspection.state.held) canvas.setPointerCapture(event.pointerId);
      pinch = pinchPosition();
      return;
    }
    const result = event.button === 0 ? hitAt(event.clientX, event.clientY) : null;
    const screw = result?.action === 'screw' && Boolean(result.target);
    const restoreControls = screw && repair.beginScrew(result!.target!.name) && controls.enabled;
    if (restoreControls) controls.enabled = false;
    if ((inspection.state.held || screw) && event.button === 0) canvas.setPointerCapture(event.pointerId);
    press = event.button === 0 ? { x: event.clientX, y: event.clientY, lastX: event.clientX, lastY: event.clientY,
      moved: false, screw, restoreControls } : null;
  }
  let hoverPoint: { x: number; y: number; pointerType: string } | null = null;
  let lastHover = 0;
  function hover(x: number, y: number, pointerType = 'mouse') {
    const result = hitAt(x, y);
    const interactive = Boolean(result?.action && (result.action !== 'desk' || state.equippedTool || repair.state.heldPart));
    canvas.style.cursor = interactive ? 'pointer' : 'grab';
    const target = result?.target;
    const cableTarget = target?.name === 'fan-plug-pick-target' ? target.parent
      : target?.name === 'fan-cable' ? target.getObjectByName('fan-plug') : target;
    highlight.select(pointerType === 'mouse' && interactive && result?.action !== 'desk' && !repair.state.moving
      ? cableTarget ?? null : null);
    placementPreview.visible = false;
    if (pointerType === 'mouse' && !isFocusMode() && result?.action === 'desk' && repair.state.heldPart) {
      const placement = repair.previewPlacement(result.hit.point, placementObstacles());
      if (placement) {
        const { bounds, allowed } = placement;
        placementPreview.position.set((bounds.min.x + bounds.max.x) / 2, result.hit.point.y + .03,
          (bounds.min.z + bounds.max.z) / 2);
        placementPreview.scale.set(bounds.max.x - bounds.min.x, bounds.max.z - bounds.min.z, 1);
        (placementPreview.material as THREE.MeshBasicMaterial).color.set(allowed ? '#7fd9ae' : '#e59679');
        placementPreview.visible = true;
      }
    }
  }
  function leave() { hoverPoint = null; highlight.select(null); placementPreview.visible = false; }
  function move(event: PointerEvent) {
    hoverPoint = { x: event.clientX, y: event.clientY, pointerType: event.pointerType };
    if (pointers.has(event.pointerId)) pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (pointers.size === 2 && inspection.state.held) {
      const next = pinchPosition();
      if (next && pinch && pinch.distance > 0 && next.distance > 0) {
        const rect = canvas.getBoundingClientRect();
        inspection.gesture(pinch.distance / next.distance, next.x - pinch.x, next.y - pinch.y, rect.width, rect.height);
      }
      pinch = next;
    }
    if (press && Math.hypot(event.clientX - press.x, event.clientY - press.y) > 6) press.moved = true;
    if (press && !press.screw && pointers.size === 1 && inspection.state.held && press.moved) {
      inspection.rotate(event.clientX - press.lastX, event.clientY - press.lastY);
    }
    if (press) { press.lastX = event.clientX; press.lastY = event.clientY; }
    if (pointers.size) return;
    hover(event.clientX, event.clientY, event.pointerType);
  }
  function up(event: PointerEvent) {
    const activate = pointers.size === 1 && press && !press.screw && !press.moved && Math.hypot(event.clientX - press.x, event.clientY - press.y) <= 6;
    finishScrew();
    pointers.delete(event.pointerId); press = null;
    pinch = pointers.size === 2 ? pinchPosition() : null;
    if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
    if (activate) click(event.clientX, event.clientY);
  }
  function cancel(event: PointerEvent) {
    finishScrew(); pointers.delete(event.pointerId); press = null;
    pinch = pointers.size === 2 ? pinchPosition() : null;
  }
  function blur() { finishScrew(); refitUp(); pointers.clear(); press = null; pinch = null; placementPreview.visible = false; }
  function key(event: KeyboardEvent) {
    if (event.key === 'Escape') {
      if (press?.screw) { finishScrew(); press.moved = true; return; }
      if (repair.state.heldPart) repair.refit(); else if (inspection.state.held) inspection.putDown(); else returnTool();
    }
  }
  canvas.addEventListener('pointerdown', down);
  canvas.addEventListener('pointermove', move);
  canvas.addEventListener('pointerup', up);
  canvas.addEventListener('pointercancel', cancel);
  canvas.addEventListener('pointerleave', leave);
  window.addEventListener('keydown', key);
  window.addEventListener('blur', blur);
  document.addEventListener('visibilitychange', onVisibilityChange);
  toolboxButton.addEventListener('click', toggleBox);
  returnButton.addEventListener('click', returnTool);
  equipButton.addEventListener('click', equipTool);
  message();

  function onVisibilityChange() { if (document.hidden) blur(); }

  return {
    state, inspection, repair,
    cleaningReady: () => !toolMotion && !equipPending && state.tool !== 'held',
    clearHover: () => { hoverPoint = null; highlight.select(null); placementPreview.visible = false; },
    refreshFocus: () => { placementPreview.visible = false; message(); },
    update(now: number) {
      const delta = lastTime ? Math.min((now - lastTime) / 1000, .1) : 0;
      lastTime = now;
      if (lidMotion) {
        const t = reducedMotion ? 1 : Math.min((now - lidMotion.start) / 550, 1);
        const eased = t * t * (3 - 2 * t);
        state.lidProgress = THREE.MathUtils.lerp(lidMotion.from, lidMotion.to, eased);
        bench.lid.rotation.x = -state.lidProgress * 1.72;
        if (t === 1) lidMotion = null;
      }
      if (equipPending && !lidMotion) {
        equipPending = false;
        if (state.open) grab();
      }
      if (toolMotion) {
        const t = reducedMotion ? 1 : Math.min((now - toolMotion.start) / 320, 1);
        bench.screwdriver.position.lerpVectors(toolMotion.from, toolMotion.to, 1 - (1-t)**3);
        bench.screwdriver.quaternion.slerp(toolMotion.rotation, t === 1 ? 1 : 1 - Math.exp(-18 * delta));
        const targetScale = state.tool === 'held' ? heldPose().scale : 1;
        bench.screwdriver.scale.lerp(new THREE.Vector3(targetScale, targetScale, targetScale), t === 1 ? 1 : .3);
        if (t === 1) { toolMotion = null; message(); }
      }
      if (state.tool === 'held' && !toolMotion) {
        const pose = heldPose();
        bench.screwdriver.position.copy(pose.position);
        bench.screwdriver.scale.setScalar(pose.scale);
      }
      const inspecting = inspection.update(now);
      const repairing = repair.update(now);
      equipButton.disabled = Boolean(repair.state.heldPart || repair.state.moving || inspection.busy || toolMotion || equipPending);
      refreshFocusActions();
      if (hoverPoint && !pointers.size && now - lastHover > 80) {
        hover(hoverPoint.x, hoverPoint.y, hoverPoint.pointerType); lastHover = now;
      }
      return Boolean(lidMotion || toolMotion || inspecting || repairing);
    },
    dispose() {
      refitUp();
      inspection.dispose(); repair.dispose(); highlight.dispose();
      placementPreview.removeFromParent(); placementPreview.geometry.dispose();
      (placementPreview.material as THREE.Material).dispose();
      canvas.removeEventListener('pointerleave', leave);
      inspectButton.removeEventListener('click', inspection.lift);
      canvas.removeEventListener('pointerdown', down); canvas.removeEventListener('pointermove', move);
      canvas.removeEventListener('pointerup', up); canvas.removeEventListener('pointercancel', cancel);
      window.removeEventListener('keydown', key); toolboxButton.removeEventListener('click', toggleBox);
      window.removeEventListener('blur', blur); document.removeEventListener('visibilitychange', onVisibilityChange);
      returnButton.removeEventListener('click', returnTool);
      equipButton.removeEventListener('click', equipTool);
      storePartButton.removeEventListener('click', storePart);
      focusRefitButton.removeEventListener('pointerdown', refitDown);
      focusRefitButton.removeEventListener('pointerup', refitUp);
      focusRefitButton.removeEventListener('pointercancel', refitUp);
    },
  };
}
