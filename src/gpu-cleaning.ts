import * as THREE from 'three';
import { createGPUDust } from './gpu-dust';
import type { WorkbenchSound } from './sound';

/** Cleaning is a tool action. Mesh references survive assembly detach/refit. */
export function setupGPUCleaning(scene: THREE.Scene, gpu: THREE.Object3D, camera: THREE.PerspectiveCamera,
  canvas: HTMLCanvasElement, sound: WorkbenchSound, reducedMotion: boolean,
  assembled: () => boolean, notify: (text: string) => void) {
  const dust = createGPUDust(gpu);
  const output = document.querySelector<HTMLOutputElement>('#clean-percent')!;
  const partOutput = document.querySelector<HTMLElement>('#part-cleanliness')!;
  const remainingOutput = document.querySelector<HTMLElement>('#remaining-dust')!;
  const targetOutput = document.querySelector<HTMLElement>('#cleaning-progress')!;
  const finish = document.querySelector<HTMLButtonElement>('#finish-cleaning')!;
  const before = document.querySelector<HTMLButtonElement>('#show-before')!;
  const next = document.querySelector<HTMLButtonElement>('#next-job')!;
  const reticle = document.querySelector<HTMLElement>('#blower-reticle')!;
  const state = { blowing: false, complete: false, celebrated: false, before: false, job: 1, targetPart: null as string | null };
  const raycaster = new THREE.Raycaster(), pointer = new THREE.Vector2();
  let aim = { x: 0, y: 0 }, hovering = false, previousTime = 0;
  const labels: Record<string, string> = { board: 'PCB', 'fan-assembly': 'Fan', 'cooler-assembly': 'Cooler' };
  const partLabel = (id: string) => labels[id] ?? id.replaceAll('-', ' ');
  let lastSummary = '', lastHintTime = 0;

  const COUNT = 48, positions = new Float32Array(COUNT * 3);
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
  const particleMaterial = new THREE.PointsMaterial({ color: '#dfb56e', size: .12, map: particleTexture, transparent: true, opacity: .45, depthWrite: false });
  const particles = new THREE.Points(particleGeometry, particleMaterial);
  particles.name = 'cleaning-particles'; particles.userData.cleaningEffect = true; particles.frustumCulled = false;
  scene.add(particles);
  let particleCursor = 0;
  // Capture the meshes, not the GPU root: detached parts remain raycast targets.
  // Desk, toolbox and other solids also block the air stream.
  const solids: THREE.Mesh[] = [];
  scene.traverse(object => {
    if (object instanceof THREE.Mesh && !object.name.includes('pick-target') &&
      !object.userData.dustVisual && object.name !== 'placement-preview') solids.push(object);
  });
  function hitAt(x: number, y: number, rect: DOMRect) {
    pointer.set((x - rect.left) / rect.width * 2 - 1, -(y - rect.top) / rect.height * 2 + 1);
    raycaster.setFromCamera(pointer, camera);
    return raycaster.intersectObjects(solids, false).find(hit => {
      const material = (hit.object as THREE.Mesh).material;
      const materials = Array.isArray(material) ? material : [material];
      if (!materials.some((material: THREE.Material) => material.visible)) return false;
      let object: THREE.Object3D | null = hit.object;
      while (object) { if (!object.visible || object === camera) return false; object = object.parent; }
      return true;
    });
  }
  function stop() { state.blowing = false; sound.stopAir(); reticle.classList.remove('blowing'); }
  function clearAim() { stop(); hovering = false; reticle.hidden = true; state.targetPart = null; }
  function finishJob() {
    if (dust.progress < .90 || !assembled()) { notify('Clean the parts, refit them and reconnect the cable before finishing the service.'); return; }
    stop(); state.complete = true; finish.hidden = true; next.hidden = false;
    notify('Service complete. Every part keeps its cleaned surfaces.'); sound.play('plug');
  }
  function compare() {
    stop(); state.before = !state.before; dust.before(state.before);
    before.setAttribute('aria-pressed', String(state.before)); before.textContent = state.before ? 'Show cleaned' : 'Compare before';
    notify(state.before ? 'Showing the original dust on each part. Select Show cleaned to resume.' : 'Showing your cleaned parts.');
  }
  function nextJob() {
    if (!assembled()) { notify('Refit the parts and reconnect the cable before taking the next card.'); return; }
    clearAim(); dust.reset(); state.complete = state.celebrated = state.before = false; state.job++;
    document.dispatchEvent(new Event('bench-next-job'));
    finish.hidden = false; next.hidden = true;
    before.setAttribute('aria-pressed', 'false'); before.textContent = 'Compare before';
    notify('Another dusty card is on the bench. Use your tools in any order.');
  }
  finish.addEventListener('click', finishJob); before.addEventListener('click', compare); next.addEventListener('click', nextJob);
  return {
    state, dust, stop, clearAim,
    get aim() { return hovering ? aim : null; },
    aimAt(x: number, y: number, pointerType = 'mouse') {
      aim = { x, y: y - (pointerType === 'touch' ? 46 : 0) }; hovering = true;
    },
    begin() {
      if (state.before) return;
      state.blowing = true; reticle.classList.add('blowing'); sound.startAir();
    },
    update(now: number, blower: 'blower' | 'dev-blower' | null, ready: boolean) {
      const dt = previousTime ? Math.min((now - previousTime) / 1000, .05) : 0; previousTime = now;
      const equipped = blower !== null, dev = blower === 'dev-blower';
      if (!equipped || !ready) stop();
      particles.visible = !reducedMotion;
      reticle.hidden = !equipped || !hovering || state.before || !ready;
      reticle.classList.toggle('dev-blover', dev);
      targetOutput.hidden = !equipped;
      let hit: THREE.Intersection | undefined;
      if (equipped && hovering) {
        scene.updateMatrixWorld(true);
        const rect = canvas.getBoundingClientRect();
        hit = hitAt(aim.x, aim.y, rect);
        reticle.style.left = `${aim.x}px`; reticle.style.top = `${aim.y}px`;
        state.targetPart = hit ? dust.partFor(hit.object) : null;
      }
      if (state.blowing && !state.before && hit && dust.clean(hit, dt * (dev ? 30 : 1.5), dev ? 1.1 : .47)) {
        if (!reducedMotion) {
          const i = particleCursor++ % COUNT;
          hit.point.toArray(positions, i * 3); life[i] = .35 + Math.random() * .3;
          velocities[i].copy(raycaster.ray.direction).multiplyScalar(-.5).add(new THREE.Vector3((Math.random()-.5)*1.5, .5, (Math.random()-.5)*1.5));
        }
      }
      if (state.blowing && !state.celebrated && dust.progress >= .99) {
        dust.cleanAll(); state.celebrated = true; stop();
        sound.playCleaningComplete(); notify('Spotless! The GPU is 100% clean.');
        remainingOutput.textContent = dust.remainingHint(); lastHintTime = now;
      }
      let movingParticles = false;
      for (let i = 0; i < COUNT; i++) if (life[i] > 0) {
        movingParticles = true;
        life[i] -= dt;
        for (let axis = 0; axis < 3; axis++) positions[i * 3 + axis] += velocities[i].getComponent(axis) * dt;
        velocities[i].y -= dt * .8;
        if (life[i] <= 0) positions[i * 3 + 1] = 10000;
      }
      if (movingParticles) particleGeometry.getAttribute('position').needsUpdate = true;
      const percent = Math.min(100, Math.floor(dust.progress * 100));
      const summary = Object.keys(labels).map(id => `${labels[id]} ${Math.floor(dust.partProgress(id) * 100)}%`).join(' · ');
      if (summary !== lastSummary) { partOutput.textContent = summary; lastSummary = summary; }
      if (now - lastHintTime > 400) { remainingOutput.textContent = dust.remainingHint(); lastHintTime = now; }
      output.value = `${percent}% clean`;
      finish.disabled = percent < 90 || !assembled();
      finish.textContent = percent < 90 ? 'Clean to 90% to finish' : !assembled() ? 'Refit parts to finish' : 'Finish service';
      targetOutput.textContent = state.before ? 'Before cleaning · comparison only' : state.targetPart
        ? `${partLabel(state.targetPart)} · ${Math.floor(dust.partProgress(state.targetPart) * 100)}% clean`
        : `${dev ? 'Dev blover' : 'Air blower'} · aim at the GPU or any detached part`;
    },
    dispose() {
      clearAim(); dust.dispose(); particleGeometry.dispose(); particleMaterial.dispose(); particleTexture.dispose(); particles.removeFromParent();
      finish.removeEventListener('click', finishJob); before.removeEventListener('click', compare); next.removeEventListener('click', nextJob);
    },
  };
}
