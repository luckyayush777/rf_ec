import './style.css';
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { loadGPU } from './load-gpu';
import { createWorkbench } from './workbench';
import { setupInteractions } from './interactions';
import { WorkbenchSound } from './sound';

const canvas = document.querySelector<HTMLCanvasElement>('#scene')!;
const app = document.querySelector<HTMLElement>('#app')!;
const focusButton = document.querySelector<HTMLButtonElement>('#focus-gpu')!;
const viewButtons = [...document.querySelectorAll<HTMLButtonElement>('[data-view]')];
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const touchInput = window.matchMedia('(pointer: coarse)').matches || window.innerWidth <= 640;

async function start() {
try {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, touchInput ? 1.5 : 2));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;
  renderer.outputColorSpace = THREE.SRGBColorSpace;

  const scene = new THREE.Scene();
  scene.background = new THREE.Color('#292b30');
  scene.fog = new THREE.FogExp2('#292b30', 0.012);

  const pmrem = new THREE.PMREMGenerator(renderer);
  const room = new RoomEnvironment();
  const environment = pmrem.fromScene(room, 0.04);
  scene.environment = environment.texture;
  scene.environmentIntensity = 0.5;
  room.dispose();
  pmrem.dispose();

  const camera = new THREE.PerspectiveCamera(35, 1, 0.1, 100);
  const controls = new OrbitControls(camera, canvas);
  controls.enableDamping = true;
  controls.dampingFactor = 0.075;
  controls.enablePan = false;
  controls.minDistance = 8;
  controls.maxDistance = 54;
  controls.minPolarAngle = 0.025;
  controls.maxPolarAngle = Math.PI * 0.47;
  controls.rotateSpeed = 0.65;
  controls.zoomSpeed = 0.8;
  controls.target.set(0, -.3, 0);
  controls.mouseButtons = { LEFT: THREE.MOUSE.ROTATE, MIDDLE: THREE.MOUSE.DOLLY, RIGHT: THREE.MOUSE.ROTATE };
  controls.touches = { ONE: THREE.TOUCH.ROTATE, TWO: THREE.TOUCH.DOLLY_ROTATE };

  const { gpu } = await loadGPU();
  gpu.position.add(new THREE.Vector3(-2.3, .047, .7));
  scene.add(gpu);
  scene.add(camera);
  const workbench = createWorkbench(scene);

  scene.add(new THREE.HemisphereLight('#eef2fa', '#373139', 1.0));
  const key = new THREE.DirectionalLight('#fff3e2', 2.3);
  key.position.set(-5, 11, 6);
  key.castShadow = true;
  key.shadow.mapSize.set(touchInput ? 1024 : 2048, touchInput ? 1024 : 2048);
  key.shadow.camera.left = -11;
  key.shadow.camera.right = 11;
  key.shadow.camera.top = 9;
  key.shadow.camera.bottom = -9;
  key.shadow.camera.near = 0.5;
  key.shadow.camera.far = 32;
  key.shadow.normalBias = 0.018;
  key.shadow.bias = -0.00015;
  key.shadow.radius = 3;
  scene.add(key);
  const fill = new THREE.DirectionalLight('#d6e6f0', 0.55);
  fill.position.set(4, 4, -5);
  scene.add(fill);
  const rim = new THREE.DirectionalLight('#ffffff', 0.8);
  rim.position.set(-3, 3, -5);
  scene.add(rim);

  type CameraView = 'perspective' | 'top';
  let activeView: CameraView | null = 'perspective';
  let transition: { from: THREE.Vector3; to: THREE.Vector3; start: number } | null = null;
  let frame = 0;
  let disposed = false;
  let focusMode = false;
  let focusCameraApplied = false;
  let savedCamera: { position: THREE.Vector3; quaternion: THREE.Quaternion; target: THREE.Vector3;
    minDistance: number; maxDistance: number } | null = null;
  const sounds = new WorkbenchSound();
  const interactions = setupInteractions(scene, camera, canvas, workbench, gpu, controls, sounds,
    requestRender, reducedMotion, () => focusMode);
  const fpsCounter = document.querySelector<HTMLOutputElement>('#fps')!;
  const muteButton = document.querySelector<HTMLButtonElement>('#mute-sound')!;
  let fpsStart = performance.now(), fpsFrames = 0;
  function toggleSound() {
    sounds.unlock(); sounds.setMuted(!sounds.muted);
    muteButton.textContent = sounds.muted ? 'Sound off' : 'Sound on';
    muteButton.setAttribute('aria-pressed', String(sounds.muted));
  }
  muteButton.addEventListener('click', toggleSound);

  function viewPosition(view: CameraView) {
    const mobile = window.innerWidth <= 640;
    const scale = mobile ? 1.7 : window.innerWidth < 1000 ? 1.15 : 1;
    return view === 'top'
      ? new THREE.Vector3(0, 29 * scale, 0.12)
      : new THREE.Vector3(12 * scale, 16 * scale, 23 * scale);
  }

  function applyFocusCamera() {
    if (!focusMode || interactions.inspection.state.held || interactions.inspection.state.moving) return;
    const center = new THREE.Box3().setFromObject(gpu).getCenter(new THREE.Vector3());
    const distance = Math.max(11, 3.6 / (Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) * Math.min(1, camera.aspect)));
    controls.target.copy(center);
    camera.position.copy(center).addScaledVector(new THREE.Vector3(.28, .42, .86).normalize(), distance);
    controls.minDistance = 7;
    controls.maxDistance = 30;
    controls.enableDamping = false;
    controls.update();
    controls.enableDamping = true;
    focusCameraApplied = true;
  }

  function updateFocusVisibility() {
    const { heldPart, stored } = interactions.repair.state;
    for (const object of scene.children) {
      if (object === gpu || object === camera || object instanceof THREE.Light || object.name === 'placement-preview') continue;
      object.visible = focusMode ? object.name === heldPart : !stored.includes(object.name);
    }
    workbench.screwdriver.visible = !focusMode;
  }

  function toggleFocusMode() {
    if (!focusMode) {
      savedCamera = { position: camera.position.clone(), quaternion: camera.quaternion.clone(),
        target: controls.target.clone(), minDistance: controls.minDistance, maxDistance: controls.maxDistance };
      focusMode = true;
      transition = null;
      focusCameraApplied = false;
      applyFocusCamera();
    } else {
      focusMode = false;
      focusCameraApplied = false;
      if (savedCamera) {
        controls.target.copy(savedCamera.target);
        camera.position.copy(savedCamera.position);
        camera.quaternion.copy(savedCamera.quaternion);
        controls.minDistance = savedCamera.minDistance;
        controls.maxDistance = savedCamera.maxDistance;
        controls.update();
      }
      savedCamera = null;
    }
    app.classList.toggle('focus-mode', focusMode);
    focusButton.textContent = focusMode ? 'Exit focus' : 'Focus GPU';
    focusButton.setAttribute('aria-pressed', String(focusMode));
    updateFocusVisibility();
    interactions.refreshFocus();
    requestRender();
  }
  focusButton.addEventListener('click', toggleFocusMode);

  function updateButtons() {
    viewButtons.forEach(button => {
      const selected = button.dataset.view === activeView;
      button.classList.toggle('active', selected);
      button.setAttribute('aria-pressed', String(selected));
    });
  }

  function requestRender() {
    if (!frame && !disposed && !document.hidden) frame = requestAnimationFrame(render);
  }

  function selectView(view: CameraView, immediate = false) {
    if (focusMode || !controls.enabled) return;
    activeView = view;
    updateButtons();
    controls.target.set(0, -.3, 0);
    // Flush residual orbit damping before a camera preset takes control.
    controls.enableDamping = false;
    controls.update();
    controls.enableDamping = true;
    if (immediate || reducedMotion) {
      transition = null;
      camera.position.copy(viewPosition(view));
      controls.update();
    } else {
      transition = { from: camera.position.clone(), to: viewPosition(view), start: performance.now() };
    }
    requestRender();
  }

  function resize() {
    const width = canvas.clientWidth || window.innerWidth;
    const height = canvas.clientHeight || window.innerHeight;
    renderer.setSize(width, height, false);
    camera.aspect = width / height;
    camera.clearViewOffset();
    camera.fov = width <= 640 ? 43 : 35;
    camera.updateProjectionMatrix();
    if (focusMode) { focusCameraApplied = false; applyFocusCamera(); }
    else if (activeView) selectView(activeView, true);
    requestRender();
  }

  function render(now: number) {
    frame = 0;
    if (disposed) return;
    if (!controls.enabled) transition = null;
    if (transition) {
      const progress = Math.min((now - transition.start) / 850, 1);
      const eased = progress < 0.5 ? 4 * progress ** 3 : 1 - (-2 * progress + 2) ** 3 / 2;
      camera.position.lerpVectors(transition.from, transition.to, eased);
      if (progress === 1) transition = null;
    }
    interactions.update(now);
    if (focusMode && !focusCameraApplied) applyFocusCamera();
    updateFocusVisibility();
    if (controls.enabled) controls.update();
    renderer.render(scene, camera);
    fpsFrames++;
    if (now - fpsStart >= 500) {
      fpsCounter.value = String(Math.round(fpsFrames * 1000 / (now - fpsStart)));
      fpsFrames = 0; fpsStart = now;
    }
    // Render continuously while visible so the counter measures actual rendered frames.
    requestRender();
  }

  controls.addEventListener('change', requestRender);
  controls.addEventListener('start', () => {
    transition = null;
    activeView = null;
    updateButtons();
    requestRender();
  });
  viewButtons.forEach(button => button.addEventListener('click', () => selectView(button.dataset.view as CameraView)));
  document.querySelector('#reset-view')!.addEventListener('click', () => selectView('perspective'));
  window.addEventListener('resize', resize);
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      cancelAnimationFrame(frame);
      frame = 0;
    } else { fpsStart = performance.now(); fpsFrames = 0; requestRender(); }
  });
  canvas.addEventListener('webglcontextlost', event => {
    event.preventDefault();
    cancelAnimationFrame(frame);
    frame = 0;
    disposed = true;
    document.querySelector('#interaction-status')!.textContent = 'The graphics connection was interrupted. Reload the page to reopen the workbench.';
    console.error('The graphics connection was interrupted. Reload to reopen the workbench.');
  });

  resize();
  renderer.compile(scene, camera);
  requestRender();

  // A small development inspection surface for checking the assembly and camera.
  if (import.meta.env.DEV) {
    Object.assign(window, { __bench: { scene, gpu, camera, controls, renderer, requestRender, workbench, interactions, sounds } });
  }

  window.addEventListener('pageshow', requestRender);
  window.addEventListener('pagehide', event => {
    if (event.persisted) return;
    disposed = true;
    cancelAnimationFrame(frame);
    controls.dispose();
    interactions.dispose();
    sounds.dispose();
    muteButton.removeEventListener('click', toggleSound);
    focusButton.removeEventListener('click', toggleFocusMode);
    scene.traverse(object => {
      if (object instanceof THREE.Mesh) {
        object.geometry.dispose();
        const materials = Array.isArray(object.material) ? object.material : [object.material];
        materials.forEach(mat => {
          for (const value of Object.values(mat)) if (value instanceof THREE.Texture) value.dispose();
          mat.dispose();
        });
      }
    });
    environment.dispose();
    renderer.dispose();
  });
} catch (cause) {
  console.error(cause);
  document.querySelector('#interaction-status')!.textContent = 'The workbench could not load. Reload the page to try again.';
}
}

void start();
