import * as THREE from 'three';
import { createGPUDust } from './gpu-dust';
import type { setupInteractions } from './interactions';
import type { WorkbenchSound } from './sound';

export function setupGPUCleaning(scene: THREE.Scene, gpu: THREE.Object3D, camera: THREE.PerspectiveCamera,
  canvas: HTMLCanvasElement, interactions: ReturnType<typeof setupInteractions>, sound: WorkbenchSound,
  focus: () => void, reducedMotion: boolean) {
  const dust = createGPUDust(gpu);
  const app = document.querySelector('#app')!;
  const panel = document.querySelector<HTMLElement>('#cleaning-panel')!;
  const hint = document.querySelector<HTMLElement>('#cleaning-hint')!;
  const output = document.querySelector<HTMLOutputElement>('#clean-percent')!;
  const progress = document.querySelector<HTMLProgressElement>('#clean-progress')!;
  const finish = document.querySelector<HTMLButtonElement>('#finish-cleaning')!;
  const before = document.querySelector<HTMLButtonElement>('#show-before')!;
  const next = document.querySelector<HTMLButtonElement>('#next-job')!;
  const toggle = document.querySelector<HTMLButtonElement>('#toggle-cleaning')!;
  const title = document.querySelector<HTMLElement>('#job-title')!;
  const stage = document.querySelector<HTMLElement>('#job-stage')!;
  const reticle = document.querySelector<HTMLElement>('#blower-reticle')!;
  const cleanButton = document.querySelector<HTMLButtonElement>('#mode-clean')!;
  const rotateButton = document.querySelector<HTMLButtonElement>('#mode-rotate')!;
  const flipButton = document.querySelector<HTMLButtonElement>('#flip-card')!;
  const state = { active: false, mode: 'clean' as 'clean' | 'rotate', blowing: false, complete: false, before: false, job: 1 };
  const raycaster = new THREE.Raycaster();
  const pointer = new THREE.Vector2();
  const points = new Map<number, { x: number; y: number }>();
  let aim = { x: 0, y: 0 }, hovering = false, previousTime = 0, startTime = 0, elapsed = 0;
  let lastPercent = -1, rear = false;
  let flip: { from: THREE.Quaternion; to: THREE.Quaternion; start: number } | null = null;
  const nozzle = new THREE.Group(); nozzle.name = 'air-blower'; camera.add(nozzle);
  const metal = new THREE.MeshStandardMaterial({ color: '#a6b7b9', metalness: .8, roughness: .3 });
  const teal = new THREE.MeshStandardMaterial({ color: '#267e80', metalness: .25, roughness: .42 });
  const grip = new THREE.Mesh(new THREE.CylinderGeometry(.095, .12, .43, 16), teal);
  const tip = new THREE.Mesh(new THREE.CylinderGeometry(.024, .05, .42, 12), metal); tip.position.y = .4;
  const collar = new THREE.Mesh(new THREE.CylinderGeometry(.12, .12, .07, 16), metal); collar.position.y = .19;
  nozzle.add(grip, tip, collar); nozzle.rotation.set(.05, 0, .5); nozzle.scale.setScalar(.65); nozzle.visible = false;

  // One bounded particle buffer; no meshes are allocated while spraying.
  const COUNT = 72, positions = new Float32Array(COUNT * 3);
  positions.fill(10000);
  const velocities = Array.from({ length: COUNT }, () => new THREE.Vector3());
  const life = new Float32Array(COUNT);
  const particleGeometry = new THREE.BufferGeometry();
  particleGeometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  const sprite = document.createElement('canvas'); sprite.width = sprite.height = 32;
  const ctx = sprite.getContext('2d')!, gradient = ctx.createRadialGradient(16, 16, 0, 16, 16, 16);
  gradient.addColorStop(0, '#ffffff'); gradient.addColorStop(1, '#ffffff00');
  ctx.fillStyle = gradient; ctx.fillRect(0, 0, 32, 32);
  const particleTexture = new THREE.CanvasTexture(sprite);
  const particleMaterial = new THREE.PointsMaterial({ color: '#cdbd9e', size: .12, map: particleTexture, transparent: true, opacity: .45, depthWrite: false });
  const particles = new THREE.Points(particleGeometry, particleMaterial);
  particles.name = 'cleaning-particles'; particles.userData.cleaningEffect = true; particles.frustumCulled = false;
  scene.add(particles);
  let particleCursor = 0;
  const visibleMeshes: THREE.Mesh[] = [];
  gpu.traverse(object => {
    if (object instanceof THREE.Mesh && !object.name.includes('pick-target') && !object.userData.dustVisual) visibleMeshes.push(object);
  });

  function stop() {
    state.blowing = false; sound.stopAir(); reticle.classList.remove('blowing');
  }
  function cancel() {
    stop();
    for (const id of points.keys()) if (canvas.hasPointerCapture(id)) canvas.releasePointerCapture(id);
    points.clear(); hovering = false; nozzle.visible = false; reticle.hidden = true;
  }
  function setMode(mode: 'clean' | 'rotate') {
    cancel(); state.mode = mode;
    cleanButton.setAttribute('aria-pressed', String(mode === 'clean'));
    rotateButton.setAttribute('aria-pressed', String(mode === 'rotate'));
    canvas.style.cursor = mode === 'clean' ? 'crosshair' : 'grab';
    hint.textContent = mode === 'clean' ? 'Hold and sweep to blow away dust. Flip the card to reach the back.' : 'Drag to turn the card. Pinch or scroll to zoom.';
  }
  function enter() {
    if (interactions.repair.state.moving || interactions.repair.state.heldPart || interactions.inspection.busy || !interactions.cleaningReady()) {
      document.querySelector('#interaction-status')!.textContent = 'Set down the tool and finish the current movement before cleaning.';
      return;
    }
    if (interactions.repair.state.removed.length) {
      document.querySelector('#interaction-status')!.textContent = 'Refit the removed parts before starting the exterior cleaning job.';
      return;
    }
    focus(); interactions.clearHover();
    state.active = true; app.classList.add('cleaning-job'); panel.hidden = false;
    toggle.textContent = 'Repair sandbox'; toggle.setAttribute('aria-pressed', 'true');
    interactions.inspection.lift(); setMode('clean');
  }
  function exit() {
    cancel(); dust.before(false); state.before = false; before.setAttribute('aria-pressed', 'false');
    state.active = false; flip = null; app.classList.remove('cleaning-job'); panel.hidden = true;
    toggle.textContent = 'Cleaning job'; toggle.setAttribute('aria-pressed', 'false');
    interactions.refreshFocus();
  }
  function toggleJob() { if (state.active) exit(); else enter(); }
  function flipCard() {
    if (interactions.inspection.busy) return;
    stop(); rear = !rear;
    const target = camera.quaternion.clone().multiply(new THREE.Quaternion().setFromEuler(new THREE.Euler(rear ? -Math.PI / 2 : Math.PI / 2, 0, rear ? .06 : -.06)));
    flip = { from: gpu.quaternion.clone(), to: target, start: performance.now() };
    flipButton.textContent = rear ? 'Show front' : 'Show back';
  }
  function finishJob() {
    if (dust.progress < .90 || state.complete) return;
    stop(); state.complete = true;
    stage.textContent = 'SERVICE COMPLETE'; title.textContent = 'Ready for a fresh start.';
    hint.textContent = `Cleaned in ${Math.max(1, Math.round(elapsed))} seconds of work. Compare your result, or take the next card.`;
    finish.hidden = true; next.hidden = false; sound.play('plug');
  }
  function compare() {
    stop(); state.before = !state.before; dust.before(state.before);
    before.setAttribute('aria-pressed', String(state.before)); before.textContent = state.before ? 'Show cleaned' : 'Compare before';
    hint.textContent = state.before ? 'Before cleaning · the card as it arrived.' : state.complete ? 'Your finished card. Rotate it to inspect the result.' : 'Hold and sweep to blow away dust. Flip the card to reach the back.';
  }
  function nextJob() {
    cancel(); dust.reset(); state.complete = state.before = false; state.job++;
    startTime = 0; elapsed = 0; lastPercent = -1;
    stage.textContent = `JOB ${String(state.job).padStart(3, '0')} / EXTERIOR CLEAN`;
    title.textContent = 'A little care. A lot less dust.';
    finish.hidden = false; finish.disabled = true; next.hidden = true;
    before.setAttribute('aria-pressed', 'false'); before.textContent = 'Compare before';
    if (rear) flipCard(); setMode('clean');
  }

  function aimAt(event: PointerEvent) {
    aim = { x: event.clientX, y: event.clientY - (event.pointerType === 'touch' ? 46 : 0) };
    hovering = true;
  }
  function down(event: PointerEvent) {
    if (!state.active) return;
    event.stopImmediatePropagation(); event.preventDefault();
    if (event.button !== 0) return;
    points.set(event.pointerId, { x: event.clientX, y: event.clientY }); canvas.setPointerCapture(event.pointerId);
    aimAt(event); sound.unlock();
    if (points.size > 1) { stop(); return; }
    if (state.mode === 'clean' && !state.complete && !state.before && !interactions.inspection.busy && !flip) {
      state.blowing = true; reticle.classList.add('blowing'); sound.startAir();
      if (!startTime) startTime = performance.now();
    }
  }
  function move(event: PointerEvent) {
    if (!state.active) return;
    event.stopImmediatePropagation(); aimAt(event);
    const old = points.get(event.pointerId);
    if (!old) return;
    if (state.mode === 'rotate' && !flip) {
      if (points.size === 1) interactions.inspection.rotate(event.clientX - old.x, event.clientY - old.y);
      else if (points.size === 2) {
        const other = [...points.entries()].find(([id]) => id !== event.pointerId)![1];
        const a = Math.hypot(old.x - other.x, old.y - other.y), b = Math.hypot(event.clientX - other.x, event.clientY - other.y);
        if (a > 0 && b > 0) interactions.inspection.gesture(a / b, (event.clientX - old.x) / 2, (event.clientY - old.y) / 2, canvas.clientWidth, canvas.clientHeight);
      }
    }
    points.set(event.pointerId, { x: event.clientX, y: event.clientY });
  }
  function up(event: PointerEvent) {
    if (!state.active) return;
    event.stopImmediatePropagation(); points.delete(event.pointerId); stop();
    if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
    if (event.pointerType === 'touch') hovering = false;
  }
  function wheel(event: WheelEvent) {
    if (!state.active) return;
    event.stopImmediatePropagation(); event.preventDefault();
    interactions.inspection.gesture(Math.exp(event.deltaY * .001), 0, 0, canvas.clientWidth, canvas.clientHeight);
  }
  function key(event: KeyboardEvent) {
    if (state.active && event.key === 'Escape') { event.stopImmediatePropagation(); setMode('rotate'); }
  }
  function visibility() { if (document.hidden) cancel(); }
  function leave() { if (!points.size) hovering = false; }
  const cleanClick = () => setMode('clean'), rotateClick = () => setMode('rotate');
  cleanButton.addEventListener('click', cleanClick); rotateButton.addEventListener('click', rotateClick);
  toggle.addEventListener('click', toggleJob); flipButton.addEventListener('click', flipCard);
  finish.addEventListener('click', finishJob); before.addEventListener('click', compare); next.addEventListener('click', nextJob);
  canvas.addEventListener('pointerdown', down, true); canvas.addEventListener('pointermove', move, true);
  canvas.addEventListener('pointerup', up, true); canvas.addEventListener('pointercancel', up, true);
  canvas.addEventListener('lostpointercapture', stop); canvas.addEventListener('pointerleave', leave);
  canvas.addEventListener('wheel', wheel, { capture: true, passive: false });
  window.addEventListener('blur', cancel); window.addEventListener('keydown', key, true);
  document.addEventListener('visibilitychange', visibility);

  function hitAt(x: number, y: number) {
    const rect = canvas.getBoundingClientRect();
    pointer.set((x - rect.left) / rect.width * 2 - 1, -(y - rect.top) / rect.height * 2 + 1);
    raycaster.setFromCamera(pointer, camera);
    return raycaster.intersectObjects(visibleMeshes, false).find(hit => {
      let object: THREE.Object3D | null = hit.object;
      while (object) { if (!object.visible) return false; object = object.parent; }
      return true;
    });
  }
  return {
    state, dust, enter, exit,
    update(now: number) {
      const dt = previousTime ? Math.min((now - previousTime) / 1000, .05) : 0; previousTime = now;
      particles.visible = state.active && !reducedMotion;
      nozzle.visible = state.active && state.mode === 'clean' && hovering && !state.before && !state.complete;
      reticle.hidden = !nozzle.visible;
      if (!state.active) return;
      if (flip) {
        const t = reducedMotion ? 1 : Math.min(1, (now - flip.start) / 450);
        gpu.quaternion.slerpQuaternions(flip.from, flip.to, t * t * (3 - 2 * t));
        if (t === 1) flip = null;
      }
      if (nozzle.visible) {
        reticle.style.left = `${aim.x}px`; reticle.style.top = `${aim.y}px`;
        const halfH = 3 * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
        nozzle.position.set((aim.x / canvas.clientWidth * 2 - 1) * halfH * camera.aspect + .19,
          (1 - aim.y / canvas.clientHeight * 2) * halfH - .36, -3);
      }
      gpu.updateWorldMatrix(true, true);
      if (state.blowing && !flip && !interactions.inspection.busy) {
        elapsed += dt;
        // Separate rays make fins occlude the PCB; a wide sweep can reach adjacent fins.
        for (const [dx, dy] of [[0, 0], [-12, 0], [12, 0], [0, -12], [0, 12]]) {
          const hit = hitAt(aim.x + dx, aim.y + dy);
          if (!hit || !dust.clean(hit, dt * .5)) continue;
          if (!reducedMotion) {
            const i = particleCursor++ % COUNT;
            hit.point.toArray(positions, i * 3); life[i] = .35 + Math.random() * .3;
            velocities[i].copy(raycaster.ray.direction).multiplyScalar(-.5).add(new THREE.Vector3((Math.random()-.5)*1.5, .5, (Math.random()-.5)*1.5));
          }
        }
      }
      for (let i = 0; i < COUNT; i++) if (life[i] > 0) {
        life[i] -= dt;
        for (let axis = 0; axis < 3; axis++) positions[i * 3 + axis] += velocities[i].getComponent(axis) * dt;
        velocities[i].y -= dt * .8;
        if (life[i] <= 0) positions[i * 3 + 1] = 10000;
      }
      particleGeometry.getAttribute('position').needsUpdate = true;
      const percent = Math.min(100, Math.floor(dust.progress * 100));
      if (percent !== lastPercent) {
        output.value = `${percent}%`; progress.value = percent; lastPercent = percent;
        finish.disabled = percent < 90;
        finish.textContent = percent >= 90 ? 'Finish service →' : 'Clean to 90% to finish';
        if (percent >= 90 && !state.complete) stage.textContent = 'LOOKING GOOD / READY TO FINISH';
      }
    },
    dispose() {
      cancel(); dust.dispose(); particleGeometry.dispose(); particleMaterial.dispose(); particleTexture.dispose(); particles.removeFromParent();
      nozzle.removeFromParent(); nozzle.traverse(o => { if (o instanceof THREE.Mesh) o.geometry.dispose(); }); metal.dispose(); teal.dispose();
      cleanButton.removeEventListener('click', cleanClick); rotateButton.removeEventListener('click', rotateClick);
      toggle.removeEventListener('click', toggleJob); flipButton.removeEventListener('click', flipCard);
      finish.removeEventListener('click', finishJob); before.removeEventListener('click', compare); next.removeEventListener('click', nextJob);
      canvas.removeEventListener('pointerdown', down, true); canvas.removeEventListener('pointermove', move, true);
      canvas.removeEventListener('pointerup', up, true); canvas.removeEventListener('pointercancel', up, true);
      canvas.removeEventListener('lostpointercapture', stop); canvas.removeEventListener('pointerleave', leave); canvas.removeEventListener('wheel', wheel, true);
      window.removeEventListener('blur', cancel); window.removeEventListener('keydown', key, true); document.removeEventListener('visibilitychange', visibility);
    },
  };
}
