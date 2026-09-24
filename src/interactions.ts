import * as THREE from 'three';
import type { Workbench } from './workbench';
import type { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import type { WorkbenchSound } from './sound';
import { setupGPUInspection } from './gpu-inspection';
import { setupGPURepair } from './gpu-repair';
import { setupGPUCleaning } from './gpu-cleaning';
import { setupGPUPadRemoval } from './gpu-pad-removal';
import { createWorkbenchTools, type ToolId } from './workbench-tools';
import { createInteractionHighlight } from './interaction-highlight';

export function setupInteractions(scene: THREE.Scene, camera: THREE.PerspectiveCamera,
  canvas: HTMLCanvasElement, bench: Workbench, gpu: THREE.Object3D, controls: OrbitControls, sound: WorkbenchSound,
  requestRender: () => void, reducedMotion: boolean, isFocusMode: () => boolean) {
  const status = document.querySelector<HTMLElement>('#interaction-status')!;
  const toolboxButton = document.querySelector<HTMLButtonElement>('#toggle-toolbox')!;
  const returnButton = document.querySelector<HTMLButtonElement>('#return-tool')!;
  const equipButton = document.querySelector<HTMLButtonElement>('#equip-tool')!;
  const blowerButton = document.querySelector<HTMLButtonElement>('#equip-blower')!;
  const scraperButton = document.querySelector<HTMLButtonElement>('#equip-scraper')!;
  const equippedLabel = document.querySelector<HTMLElement>('#equipped-tool')!;
  const touchInput = window.matchMedia('(pointer: coarse)').matches || window.innerWidth <= 640;
  const raycaster = new THREE.Raycaster(), pointer = new THREE.Vector2();
  let lastTime = 0;
  function isConnected(id: string) {
    if (id !== 'fan-plug') throw new Error(`Missing connection state for ${id}.`);
    return inspection.state.cableConnected;
  }
  const inspection = setupGPUInspection(gpu, camera, controls, sound, requestRender, reducedMotion, message,
    () => !repair.state.moving && !repair.state.heldPart && !tools.busy,
    connect => repair.check({ kind: connect ? 'connect' : 'disconnect', part: 'fan-plug' }));
  const repair = setupGPURepair(scene, gpu, camera, sound, reducedMotion, isConnected,
    () => tools.state.equippedTool, () => !inspection.busy && !tools.busy, () => inspection.putDown(),
    text => { status.textContent = text; }, message, isFocusMode);
  const highlight = createInteractionHighlight();
  const placementPreview = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), new THREE.MeshBasicMaterial({
    color: '#7fd9ae', transparent: true, opacity: .35, depthWrite: false, side: THREE.DoubleSide,
  }));
  placementPreview.name = 'placement-preview'; placementPreview.rotation.x = -Math.PI / 2;
  placementPreview.renderOrder = 5; placementPreview.visible = false; scene.add(placementPreview);
  const tools = createWorkbenchTools(scene, camera, bench, sound, reducedMotion,
    id => !repair.state.moving && !inspection.busy && (id === 'blower' || !repair.state.heldPart),
    () => { cleaning.clearAim(); clearHover(); message(); }, text => { status.textContent = text; }, requestRender);
  const state = tools.state;
  const cleaning = setupGPUCleaning(scene, gpu, camera, canvas, sound, reducedMotion,
    () => !repair.state.removed.length && inspection.state.cableConnected && !repair.state.moving && !inspection.busy,
    text => { status.textContent = text; });
  const padRemoval = setupGPUPadRemoval(gpu, () => repair.removed('cooler-assembly'),
    text => { status.textContent = text; });
  const inspectButton = document.querySelector<HTMLButtonElement>('#inspect-gpu')!;
  const fanButton = document.querySelector<HTMLButtonElement>('#remove-fan')!;
  const coolerButton = document.querySelector<HTMLButtonElement>('#remove-cooler')!;
  const flipButton = document.querySelector<HTMLButtonElement>('#flip-held')!;
  const storePartButton = document.querySelector<HTMLButtonElement>('#store-part')!;
  const focusRefitButton = document.querySelector<HTMLButtonElement>('#focus-refit-screw')!;
  const heldItem = () => Boolean(inspection.state.held || repair.state.heldPart);
  const ready = () => !tools.busy && !inspection.busy && !repair.state.moving;
  function placementObstacles() {
    return [gpu, bench.pcbHolder, bench.toolbox, bench.screwdriver, bench.blower, bench.scraper, bench.spareParts, bench.alcohol,
      scene.getObjectByName('desk-light')!,
      scene.getObjectByName('parts-tray')!, ...repair.looseObjects()];
  }
  let refitPointer: number | null = null;
  function refreshFocusActions() {
    inspectButton.hidden = Boolean(repair.state.heldPart) || (isFocusMode() && inspection.state.held);
    fanButton.hidden = coolerButton.hidden = isFocusMode() && Boolean(repair.state.heldPart);
    storePartButton.hidden = !isFocusMode() || !repair.state.heldPart;
    storePartButton.disabled = !ready() || Boolean(state.equippedTool);
    focusRefitButton.hidden = !isFocusMode() || (refitPointer === null && !repair.nextRefittableScrew());
    flipButton.hidden = !heldItem(); flipButton.disabled = !ready();
    equipButton.hidden = state.equippedTool === 'screwdriver';
    blowerButton.hidden = state.equippedTool === 'blower';
    scraperButton.hidden = state.equippedTool === 'scraper';
    equipButton.disabled = !ready() || Boolean(repair.state.heldPart);
    blowerButton.disabled = !ready(); scraperButton.disabled = !ready() || Boolean(repair.state.heldPart);
    returnButton.disabled = !ready();
  }
  function message() {
    const blower = state.equippedTool === 'blower';
    status.textContent = blower
      ? touchInput ? 'Hold a part to blow dust · use two fingers to turn / zoom a held part · return blower to move parts'
        : heldItem() ? 'Hold and sweep to blow dust · right-drag or Flip held item to turn it · return blower before refitting'
        : 'Hold and sweep over a part to blow dust · click clear desk to place blower'
      : state.equippedTool === 'scraper' ? inspection.state.held
        ? 'Set the GPU down in the PCB holder before scraping'
        : 'Remove the cooler, then drag inward from the edge of each old pad'
      : repair.state.heldPart ? 'Part held · drag to rotate · equip blower to clean · return blower before refitting'
      : inspection.state.held ? state.equippedTool === 'screwdriver'
        ? 'GPU held · drag to expose screws · hold a screw to remove / refit'
        : `Drag GPU to rotate · equip a tool · tap cable to ${inspection.state.cableConnected ? 'unplug' : 'reconnect'}`
      : state.equippedTool === 'screwdriver' ? 'Hold a screw to turn it · click a clear desk spot to place the screwdriver'
      : state.open ? 'Pick a tool from the toolbox · inspect the GPU to service it'
      : 'Click the GPU to inspect · open the toolbox to pick up a tool';
    toolboxButton.textContent = state.open ? 'Close toolbox' : 'Open toolbox';
    toolboxButton.setAttribute('aria-expanded', String(state.open));
    returnButton.hidden = !state.equippedTool;
    returnButton.textContent = state.equippedTool === 'blower' ? 'Return blower'
      : state.equippedTool === 'scraper' ? 'Return scraper' : 'Return screwdriver';
    equippedLabel.textContent = blower ? 'Air blower' : state.equippedTool === 'screwdriver' ? 'Screwdriver'
      : state.equippedTool === 'scraper' ? 'Plastic scraper' : 'None (empty hands)';
    refreshFocusActions();
  }
  function equip(id: ToolId) { cleaning.stop(); clearHover(); tools.equip(id); }
  const equipScrewdriver = () => equip('screwdriver'), equipBlower = () => equip('blower'), equipScraper = () => equip('scraper');
  function returnTool() { cleaning.clearAim(); tools.returnTool(); }
  function toggleBox() { if (!repair.state.moving) tools.toggleBox(); }
  function storePart() { cleaning.clearAim(); repair.storePart(); refreshFocusActions(); }
  function rotate(dx: number, dy: number) {
    if (state.equippedTool === 'scraper') return;
    if (repair.state.heldPart) repair.rotateHeld(dx, dy); else inspection.rotate(dx, dy);
  }
  function gesture(scale: number, dx: number, dy: number) {
    if (repair.state.heldPart) repair.zoomHeld(scale);
    else inspection.gesture(scale, dx, dy, canvas.clientWidth, canvas.clientHeight);
  }
  function flipHeld() { if (ready()) { cleaning.stop(); rotate(0, Math.PI / .009); requestRender(); } }
  function refitDown(event: PointerEvent) {
    if (refitPointer !== null) return;
    const name = repair.nextRefittableScrew(); sound.unlock();
    if (!name || !repair.beginScrew(name)) return;
    refitPointer = event.pointerId; focusRefitButton.setPointerCapture(event.pointerId); event.preventDefault();
  }
  function refitUp(event?: PointerEvent) {
    if (refitPointer === null || (event && event.pointerId !== refitPointer)) return;
    if (focusRefitButton.hasPointerCapture(refitPointer)) focusRefitButton.releasePointerCapture(refitPointer);
    refitPointer = null; repair.endScrew(); refreshFocusActions();
  }
  function hitAt(x: number, y: number) {
    const rect = canvas.getBoundingClientRect();
    pointer.set((x - rect.left) / rect.width * 2 - 1, -(y - rect.top) / rect.height * 2 + 1);
    scene.updateMatrixWorld(true); raycaster.setFromCamera(pointer, camera);
    for (const hit of raycaster.intersectObjects(scene.children, true)) {
      if (!(hit.object instanceof THREE.Mesh) || hit.object === placementPreview || hit.object.userData.dustVisual) continue;
      let object: THREE.Object3D | null = hit.object;
      let action: string | undefined, target: THREE.Object3D | undefined;
      let held = false, hidden = false;
      while (object) {
        if (!object.visible) { hidden = true; break; }
        if (object === camera || object.name === repair.state.heldPart) held = true;
        if (!action && object.userData.action) { action = object.userData.action; target = object; }
        object = object.parent;
      }
      if (held || hidden) continue;
      return { hit, action, target };
    }
    return null;
  }
  function click(x: number, y: number) {
    if (!ready()) return;
    clearHover(); const result = hitAt(x, y);
    if (result?.action === 'screwdriver' || result?.action === 'blower' || result?.action === 'scraper') {
      if (state.equippedTool) equip(result.action); else tools.grab(result.action);
      return;
    }
    if (result?.action === 'toolbox') {
      if (state.equippedTool && state.open && !tools.lidMoving) returnTool(); else toggleBox();
      return;
    }
    if (result?.action === 'desk' && state.equippedTool) { tools.place(result.hit.point, placementObstacles()); return; }
    if (repair.state.heldPart) {
      if (result?.action === 'desk') repair.place(result.hit.point, placementObstacles());
      return;
    }
    if (result?.action === 'assembly' && result.target) {
      const name = result.target.name;
      if (!inspection.state.held && !repair.removed(name) && !repair.check({ kind: 'remove', part: name }).allowed) inspection.lift();
      else repair.assembly(name);
    } else if (result?.action === 'cable') inspection.toggleCable();
    else if (result?.action === 'gpu' && !inspection.state.held) inspection.lift();
  }

  const pointers = new Map<number, { x: number; y: number }>();
  let pinch: { distance: number; x: number; y: number } | null = null;
  function pinchPosition() {
    const [a, b] = [...pointers.values()];
    return a && b ? { distance: Math.hypot(a.x - b.x, a.y - b.y), x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 } : null;
  }
  let press: { x: number; y: number; lastX: number; lastY: number; moved: boolean;
    screw: boolean; blow: boolean; scrape: boolean; right: boolean } | null = null;
  function down(event: PointerEvent) {
    sound.unlock(); pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (pointers.size > 1) {
      cleaning.stop(); repair.endScrew(); padRemoval.end();
      if (press) { press.moved = true; press.scrape = false; }
      if (heldItem() || press?.blow) { event.stopImmediatePropagation(); canvas.setPointerCapture(event.pointerId); }
      pinch = pinchPosition(); return;
    }
    const result = hitAt(event.clientX, event.clientY);
    const overHeldGPU = state.equippedTool === 'scraper' && inspection.state.held && raycaster.intersectObject(gpu, true).some(hit => {
      if (!(hit.object instanceof THREE.Mesh) || hit.object.name.includes('pick-target')) return false;
      const materials = Array.isArray(hit.object.material) ? hit.object.material : [hit.object.material];
      return materials.some(material => material.visible);
    });
    const blow = event.button === 0 && state.equippedTool === 'blower' &&
      (heldItem() || ['gpu', 'assembly', 'screw', 'cable'].includes(result?.action ?? ''));
    const scrape = event.button === 0 && ready() && state.equippedTool === 'scraper' &&
      (overHeldGPU || ['residue', 'gpu', 'assembly'].includes(result?.action ?? ''));
    const screw = event.button === 0 && !blow && result?.action === 'screw';
    const right = event.button === 2 && heldItem();
    press = event.button === 0 || right ? { x: event.clientX, y: event.clientY, lastX: event.clientX, lastY: event.clientY,
      moved: false, screw, blow, scrape, right } : null;
    if (blow || scrape || right || heldItem() || screw) {
      event.stopImmediatePropagation(); event.preventDefault(); controls.enabled = false;
      canvas.setPointerCapture(event.pointerId);
    }
    if (blow) {
      clearHover(); cleaning.aimAt(event.clientX, event.clientY, event.pointerType);
      if (ready()) cleaning.begin();
    } else if (scrape) {
      clearHover();
      if (overHeldGPU) status.textContent = 'Set the GPU down in the PCB holder before scraping.';
      else if (result?.action === 'residue') padRemoval.begin(result.target, result.hit.point);
      else status.textContent = 'Start in the outer band of an old memory pad.';
    }
    else if (screw && result?.target) repair.beginScrew(result.target.name);
    else hover(event.clientX, event.clientY, event.pointerType);
  }
  let hoverPoint: { x: number; y: number; pointerType: string } | null = null;
  let lastHover = 0;
  function clearHover() { hoverPoint = null; highlight.select(null); placementPreview.visible = false; }
  function hover(x: number, y: number, pointerType = 'mouse') {
    if (state.equippedTool === 'blower') {
      highlight.select(null); placementPreview.visible = false;
      cleaning.aimAt(x, y, pointerType); canvas.style.cursor = 'crosshair'; return;
    }
    const result = hitAt(x, y);
    const interactive = Boolean(result?.action && (result.action !== 'desk' || state.equippedTool || repair.state.heldPart));
    canvas.style.cursor = state.equippedTool === 'scraper' && result?.action === 'residue' ? 'crosshair'
      : interactive ? 'pointer' : 'grab';
    const target = result?.target;
    const cableTarget = target?.name === 'fan-plug-pick-target' ? target.parent : target?.name === 'fan-cable' ? target.getObjectByName('fan-plug') : target;
    highlight.select(pointerType === 'mouse' && interactive && result?.action !== 'desk' && !repair.state.moving ? cableTarget ?? null : null);
    placementPreview.visible = false;
    if (pointerType === 'mouse' && !isFocusMode() && result?.action === 'desk' && repair.state.heldPart) {
      const placement = repair.previewPlacement(result.hit.point, placementObstacles());
      if (placement) {
        const { bounds, allowed } = placement;
        placementPreview.position.set((bounds.min.x + bounds.max.x) / 2, result.hit.point.y + .03, (bounds.min.z + bounds.max.z) / 2);
        placementPreview.scale.set(bounds.max.x - bounds.min.x, bounds.max.z - bounds.min.z, 1);
        (placementPreview.material as THREE.MeshBasicMaterial).color.set(allowed ? '#7fd9ae' : '#e59679'); placementPreview.visible = true;
      }
    }
  }
  function leave() { clearHover(); if (!pointers.size) cleaning.clearAim(); }
  function move(event: PointerEvent) {
    hoverPoint = { x: event.clientX, y: event.clientY, pointerType: event.pointerType };
    if (pointers.has(event.pointerId)) pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (state.equippedTool === 'blower' && pointers.size < 2) cleaning.aimAt(event.clientX, event.clientY, event.pointerType);
    if (press?.scrape && pointers.size === 1) {
      const rect = canvas.getBoundingClientRect();
      pointer.set((event.clientX - rect.left) / rect.width * 2 - 1,
        -(event.clientY - rect.top) / rect.height * 2 + 1);
      raycaster.setFromCamera(pointer, camera);
      padRemoval.drag(raycaster.ray);
    }
    if (pointers.size === 2 && heldItem()) {
      const next = pinchPosition();
      if (next && pinch && pinch.distance > 0 && next.distance > 0) {
        const turn = state.equippedTool === 'blower' || Boolean(repair.state.heldPart);
        if (turn) rotate(next.x - pinch.x, next.y - pinch.y);
        gesture(pinch.distance / next.distance, turn ? 0 : next.x - pinch.x, turn ? 0 : next.y - pinch.y);
      }
      pinch = next;
    }
    if (press && Math.hypot(event.clientX - press.x, event.clientY - press.y) > 6) press.moved = true;
    if (press && !press.screw && !press.blow && !press.scrape && pointers.size === 1 && heldItem() && press.moved)
      rotate(event.clientX - press.lastX, event.clientY - press.lastY);
    if (press) { press.lastX = event.clientX; press.lastY = event.clientY; }
    if (!pointers.size) hover(event.clientX, event.clientY, event.pointerType);
  }
  function up(event: PointerEvent) {
    const activate = pointers.size === 1 && press && !press.screw && !press.blow && !press.scrape && !press.right && !press.moved;
    if (press?.screw) repair.endScrew(); cleaning.stop(); padRemoval.end();
    pointers.delete(event.pointerId); press = null; pinch = pinchPosition();
    if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
    if (event.pointerType === 'touch') cleaning.clearAim();
    if (activate) click(event.clientX, event.clientY);
  }
  function cancel(event: PointerEvent) {
    if (press?.screw) repair.endScrew(); cleaning.clearAim(); padRemoval.end();
    pointers.delete(event.pointerId); press = null; pinch = pinchPosition();
  }
  function blur() {
    repair.endScrew(); refitUp(); cleaning.clearAim(); padRemoval.end();
    for (const id of pointers.keys()) if (canvas.hasPointerCapture(id)) canvas.releasePointerCapture(id);
    pointers.clear(); press = null; pinch = null; clearHover();
  }
  function key(event: KeyboardEvent) {
    if (event.key !== 'Escape') return;
    if (press?.screw) { repair.endScrew(); press.moved = true; return; }
    cleaning.stop(); padRemoval.end();
    if (state.equippedTool) returnTool(); else if (repair.state.heldPart) repair.refit(); else if (inspection.state.held) inspection.putDown();
  }
  function wheel(event: WheelEvent) {
    if (!heldItem()) return;
    event.preventDefault(); event.stopImmediatePropagation(); gesture(Math.exp(event.deltaY * .001), 0, 0);
  }
  function contextMenu(event: Event) { if (heldItem()) event.preventDefault(); }
  function onVisibilityChange() { if (document.hidden) blur(); }
  canvas.addEventListener('pointerdown', down, true); canvas.addEventListener('pointermove', move);
  canvas.addEventListener('pointerup', up); canvas.addEventListener('pointercancel', cancel);
  canvas.addEventListener('lostpointercapture', cleaning.stop); canvas.addEventListener('pointerleave', leave);
  canvas.addEventListener('wheel', wheel, { capture: true, passive: false }); canvas.addEventListener('contextmenu', contextMenu);
  window.addEventListener('keydown', key); window.addEventListener('blur', blur);
  document.addEventListener('visibilitychange', onVisibilityChange);
  toolboxButton.addEventListener('click', toggleBox); returnButton.addEventListener('click', returnTool);
  equipButton.addEventListener('click', equipScrewdriver); blowerButton.addEventListener('click', equipBlower);
  scraperButton.addEventListener('click', equipScraper);
  inspectButton.addEventListener('click', inspection.lift); storePartButton.addEventListener('click', storePart);
  flipButton.addEventListener('click', flipHeld);
  focusRefitButton.addEventListener('pointerdown', refitDown); focusRefitButton.addEventListener('pointerup', refitUp);
  focusRefitButton.addEventListener('pointercancel', refitUp);
  message();

  return {
    state, inspection, repair, cleaning, padRemoval, tools, clearHover,
    refreshFocus: () => { clearHover(); cleaning.clearAim(); message(); },
    update(now: number) {
      const delta = lastTime ? Math.min((now - lastTime) / 1000, .1) : 0; lastTime = now;
      tools.update(now, delta); inspection.update(now); repair.update(now);
      bench.updatePCBHolder(!inspection.state.held && !inspection.state.moving, delta);
      controls.enabled = !heldItem() && !inspection.busy && !repair.state.moving && !press?.blow && !press?.scrape && !press?.screw;
      cleaning.update(now, state.equippedTool === 'blower', ready());
      const aim = cleaning.aim;
      if (aim && state.equippedTool === 'blower') tools.aimBlower(aim.x, aim.y, canvas.clientWidth, canvas.clientHeight);
      refreshFocusActions();
      if (hoverPoint && !pointers.size && now - lastHover > 80) { hover(hoverPoint.x, hoverPoint.y, hoverPoint.pointerType); lastHover = now; }
      return Boolean(tools.busy || inspection.busy || repair.state.moving || cleaning.state.blowing);
    },
    dispose() {
      refitUp(); cleaning.dispose(); padRemoval.dispose(); inspection.dispose(); repair.dispose(); highlight.dispose();
      placementPreview.removeFromParent(); placementPreview.geometry.dispose(); (placementPreview.material as THREE.Material).dispose();
      canvas.removeEventListener('pointerdown', down, true); canvas.removeEventListener('pointermove', move);
      canvas.removeEventListener('pointerup', up); canvas.removeEventListener('pointercancel', cancel);
      canvas.removeEventListener('lostpointercapture', cleaning.stop); canvas.removeEventListener('pointerleave', leave);
      canvas.removeEventListener('wheel', wheel, true); canvas.removeEventListener('contextmenu', contextMenu);
      window.removeEventListener('keydown', key); window.removeEventListener('blur', blur);
      document.removeEventListener('visibilitychange', onVisibilityChange);
      toolboxButton.removeEventListener('click', toggleBox); returnButton.removeEventListener('click', returnTool);
      equipButton.removeEventListener('click', equipScrewdriver); blowerButton.removeEventListener('click', equipBlower);
      scraperButton.removeEventListener('click', equipScraper);
      inspectButton.removeEventListener('click', inspection.lift); storePartButton.removeEventListener('click', storePart);
      flipButton.removeEventListener('click', flipHeld);
      focusRefitButton.removeEventListener('pointerdown', refitDown); focusRefitButton.removeEventListener('pointerup', refitUp);
      focusRefitButton.removeEventListener('pointercancel', refitUp);
    },
  };
}
