import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';

const material = (color: string, metalness = 0, roughness = 0.6) =>
  new THREE.MeshStandardMaterial({ color, metalness, roughness });

function box(name: string, size: [number, number, number], mat: THREE.Material,
  position: [number, number, number], parent: THREE.Object3D, radius = 0.04) {
  const mesh = new THREE.Mesh(new RoundedBoxGeometry(...size, 2, Math.min(radius, Math.min(...size) / 3)), mat);
  mesh.name = name;
  mesh.position.set(...position);
  mesh.castShadow = mesh.receiveShadow = true;
  parent.add(mesh);
  return mesh;
}

function cylinder(name: string, radius: number, length: number, mat: THREE.Material,
  position: [number, number, number], parent: THREE.Object3D) {
  const mesh = new THREE.Mesh(new THREE.CylinderGeometry(radius, radius, length, 32), mat);
  mesh.name = name;
  mesh.position.set(...position);
  mesh.castShadow = mesh.receiveShadow = true;
  parent.add(mesh);
  return mesh;
}

function label(text: string, width: number, height: number, background: string, color: string) {
  const canvas = document.createElement('canvas');
  canvas.width = 1024; canvas.height = 256;
  const ctx = canvas.getContext('2d')!;
  ctx.fillStyle = background; ctx.fillRect(0, 0, 1024, 256);
  ctx.fillStyle = color;
  ctx.font = 'bold 94px sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.fillText(text, 512, 137);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(width, height), new THREE.MeshStandardMaterial({ map: texture, roughness: 0.8 }));
  return mesh;
}

export function createWorkbench(scene: THREE.Scene) {
  const desk = new THREE.Group(); desk.name = 'repair-desk'; scene.add(desk);
  const steel = material('#343940', 0.65, 0.4);
  const black = material('#171b21', 0.08, 0.7);
  const silver = material('#b5bec8', 0.82, 0.28);
  const woodCanvas = document.createElement('canvas');
  woodCanvas.width = woodCanvas.height = 512;
  const ctx = woodCanvas.getContext('2d')!;
  ctx.fillStyle = '#b19776'; ctx.fillRect(0, 0, 512, 512);
  let seed = 73;
  for (let i = 0; i < 2200; i++) {
    seed = (seed * 1664525 + 1013904223) >>> 0;
    const x = seed % 512;
    const y = (seed >>> 9) % 512;
    ctx.strokeStyle = `rgba(79,53,31,${0.015 + (seed % 8) / 180})`;
    ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + 35 + seed % 160, y + .4); ctx.stroke();
  }
  const wood = new THREE.CanvasTexture(woodCanvas); wood.colorSpace = THREE.SRGBColorSpace;
  wood.wrapS = wood.wrapT = THREE.RepeatWrapping; wood.repeat.set(3, 2);
  const tabletop = box('tabletop', [20, .38, 12], new THREE.MeshStandardMaterial({ map: wood, roughness: .8 }), [0, -.19, 0], desk, .08);
  tabletop.userData.action = 'desk';
  box('front-apron', [19.2, .5, .15], steel, [0, -.62, 5.4], desk);
  box('rear-apron', [19.2, .5, .15], steel, [0, -.62, -5.4], desk);
  for (const x of [-8.8, 8.8]) {
    for (const z of [-5, 5]) {
      box('desk-leg', [.28, 3.8, .28], steel, [x, -2.28, z], desk);
      box('rubber-foot', [.4, .14, .4], black, [x, -4.17, z], desk);
    }
    box('side-brace', [.2, .22, 10.1], steel, [x, -3.05, 0], desk);
  }
  // A broad silicone service mat with a gridded work area and component pockets.
  const matCanvas = document.createElement('canvas');
  matCanvas.width = 1400; matCanvas.height = 1000;
  const matContext = matCanvas.getContext('2d')!;
  matContext.fillStyle = '#276b91'; matContext.fillRect(0, 0, 1400, 1000);
  matContext.strokeStyle = '#5294b5'; matContext.lineWidth = 3;
  matContext.strokeRect(24, 24, 1352, 952);
  matContext.strokeStyle = '#367c9f'; matContext.lineWidth = 1;
  for (let x = 50; x <= 1350; x += 50) {
    matContext.beginPath(); matContext.moveTo(x, 220); matContext.lineTo(x, 890); matContext.stroke();
  }
  for (let y = 240; y <= 890; y += 50) {
    matContext.beginPath(); matContext.moveTo(50, y); matContext.lineTo(1350, y); matContext.stroke();
  }
  matContext.font = '18px monospace'; matContext.textAlign = 'left';
  for (let i = 0; i < 6; i++) {
    const x = 50 + i * 218;
    matContext.fillStyle = '#205c7f'; matContext.fillRect(x, 55, 202, 128);
    matContext.strokeStyle = '#5294b5'; matContext.lineWidth = 3;
    matContext.strokeRect(x, 55, 202, 128);
    matContext.fillStyle = '#9ac5d8'; matContext.fillText(`0${i + 1}`, x + 14, 84);
  }
  matContext.strokeStyle = '#88b7cf'; matContext.lineWidth = 2;
  for (let i = 0; i <= 100; i++) {
    const x = 50 + i * 13;
    matContext.beginPath(); matContext.moveTo(x, 970);
    matContext.lineTo(x, i % 5 === 0 ? 948 : 958); matContext.stroke();
  }
  matContext.fillStyle = '#b8d6e4'; matContext.font = 'bold 22px monospace';
  matContext.fillText('ELECTRONICS / SERVICE MAT', 50, 930);
  const matTexture = new THREE.CanvasTexture(matCanvas); matTexture.colorSpace = THREE.SRGBColorSpace;
  const mat = box('repair-mat', [10.5, .045, 7.4], new THREE.MeshStandardMaterial({
    color: '#ffffff', map: matTexture, roughness: .95,
  }), [-3.2, .024, 1.5], desk, .05);
  mat.userData.action = 'desk';

  const tray = new THREE.Group(); tray.name = 'parts-tray'; scene.add(tray);
  box('tray-base', [2.7, .10, 1.9], black, [3.82, .06, 3.7], tray);
  for (const z of [2.8, 3.7, 4.6]) box('tray-divider', [2.7, .10, .04], steel, [3.82, .15, z], tray);
  for (const x of [2.49, 5.15]) box('tray-side', [.04, .10, 1.9], steel, [x, .15, 3.7], tray);
  for (const [text, z] of [['FAN', 3.04], ['COOLER', 3.82]] as const) {
    const marking = label(text, .8, .16, '#171b21', '#d0c9b7');
    marking.rotation.x = -Math.PI / 2; marking.position.set(3.82, .116, z); tray.add(marking);
  }

  const floor = box('floor', [180, .2, 180], material('#292b30', 0, .95), [0, -4.35, 0], scene);
  floor.castShadow = false;

  const toolbox = new THREE.Group(); toolbox.name = 'toolbox'; toolbox.position.set(4.55, .015, -.75);
  toolbox.userData.action = 'toolbox'; scene.add(toolbox);
  const paint = material('#a34b2f', .35, .45);
  const darkPaint = material('#713421', .25, .57);
  box('toolbox-bottom', [3.7, .18, 2.3], darkPaint, [0, .15, 0], toolbox);
  for (const z of [-1.08, 1.08]) box('toolbox-wall', [3.7, .92, .14], paint, [0, .65, z], toolbox);
  for (const x of [-1.78, 1.78]) box('toolbox-end', [.14, .92, 2.16], paint, [x, .65, 0], toolbox);
  box('toolbox-lining', [3.42, .13, 2.02], black, [0, .29, 0], toolbox);
  for (const x of [-1.7, 1.7]) for (const z of [-1, 1]) box('toolbox-foot', [.28, .08, .28], black, [x, .035, z], toolbox);
  const frontLabel = label('TOOLBOX', 1.65, .36, '#1d2127', '#e7e1d5');
  frontLabel.name = 'toolbox-label'; frontLabel.position.set(0, .67, 1.157); toolbox.add(frontLabel);
  const lid = new THREE.Group(); lid.name = 'toolbox-lid-hinge'; lid.position.set(0, 1.13, -1.13); toolbox.add(lid);
  box('toolbox-lid', [3.76, .17, 2.34], paint, [0, 0, 1.13], lid);
  box('lid-inside', [3.45, .025, 2.0], darkPaint, [0, -.094, 1.13], lid);
  for (const x of [-.58, .58]) box('handle-mount', [.14, .23, .16], black, [x, .2, 1.13], lid);
  box('toolbox-handle', [1.3, .16, .18], black, [0, .32, 1.13], lid);
  for (const x of [-1.25, 1.25]) {
    box('lid-latch', [.22, .27, .07], silver, [x, -.1, 2.34], lid);
    const hinge = cylinder('lid-hinge', .07, .45, silver, [x, 0, 0], lid); hinge.rotation.z = Math.PI / 2;
  }

  const screwdriver = new THREE.Group(); screwdriver.name = 'screwdriver'; screwdriver.userData.action = 'screwdriver';
  toolbox.add(screwdriver);
  const homePosition = new THREE.Vector3(0, .57, .05);
  screwdriver.position.copy(homePosition);
  const orange = material('#e28c32', 0, .48);
  const handle = cylinder('screwdriver-handle', .195, .88, orange, [-.67, 0, 0], screwdriver); handle.rotation.z = Math.PI / 2;
  for (const x of [-.97, -.72, -.47]) {
    const grip = cylinder('handle-grip', .201, .10, black, [x, 0, 0], screwdriver); grip.rotation.z = Math.PI / 2;
  }
  const collar = cylinder('screwdriver-collar', .125, .16, silver, [-.15, 0, 0], screwdriver); collar.rotation.z = Math.PI / 2;
  const shaft = cylinder('screwdriver-shaft', .046, 1.28, silver, [.53, 0, 0], screwdriver); shaft.rotation.z = Math.PI / 2;
  box('screwdriver-tip', [.15, .025, .073], silver, [1.215, 0, 0], screwdriver, .006);

  const blower = new THREE.Group(); blower.name = 'air-blower'; blower.userData.action = 'blower';
  const blowerHomePosition = new THREE.Vector3(0, .57, -.65);
  blower.position.copy(blowerHomePosition); toolbox.add(blower);
  const teal = material('#267e80', .15, .5);
  const blowerGrip = cylinder('blower-grip', .17, .72, teal, [-.50, 0, 0], blower);
  blowerGrip.rotation.z = Math.PI / 2;
  const blowerCollar = cylinder('blower-collar', .18, .12, silver, [-.10, 0, 0], blower);
  blowerCollar.rotation.z = Math.PI / 2;
  const nozzle = cylinder('blower-nozzle', .036, 1.0, silver, [.46, 0, 0], blower);
  nozzle.rotation.z = Math.PI / 2;
  box('blower-trigger', [.24, .05, .10], black, [-.4, .16, 0], blower, .01);

  const lamp = new THREE.Group(); lamp.name = 'desk-light'; scene.add(lamp);
  cylinder('lamp-base', .62, .14, steel, [-5.65, .07, -2.9], lamp);
  function arm(a: THREE.Vector3, b: THREE.Vector3) {
    const middle = a.clone().add(b).multiplyScalar(.5);
    const mesh = cylinder('lamp-arm', .085, a.distanceTo(b), steel, middle.toArray() as [number, number, number], lamp);
    mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), b.clone().sub(a).normalize());
    const joint = new THREE.Mesh(new THREE.SphereGeometry(.16, 20, 12), black); joint.position.copy(b); lamp.add(joint);
  }
  const elbow = new THREE.Vector3(-5.45, 2.65, -2.9), head = new THREE.Vector3(-3.25, 4.15, -2.5);
  arm(new THREE.Vector3(-5.65, .18, -2.9), elbow); arm(elbow, head);
  const aim = new THREE.Vector3(-2.3, .05, .7);
  const shade = new THREE.Group(); shade.position.copy(head);
  shade.quaternion.setFromUnitVectors(new THREE.Vector3(0, -1, 0), aim.clone().sub(head).normalize()); lamp.add(shade);
  const shell = new THREE.Mesh(new THREE.CylinderGeometry(.2, .58, .48, 40, 1, true), new THREE.MeshStandardMaterial({ color: '#3b414a', metalness: .5, roughness: .38, side: THREE.DoubleSide }));
  shell.castShadow = true; shade.add(shell);
  const diffuser = new THREE.Mesh(new THREE.CircleGeometry(.52, 40), new THREE.MeshBasicMaterial({ color: '#fff2d8', side: THREE.DoubleSide }));
  diffuser.rotation.x = Math.PI / 2; diffuser.position.y = -.235; shade.add(diffuser);
  const light = new THREE.SpotLight('#ffe9cf', 65, 20, .82, .65, 2);
  light.position.copy(head).add(aim.clone().sub(head).normalize().multiplyScalar(.3));
  light.target.position.copy(aim); light.castShadow = true;
  light.shadow.mapSize.set(1024, 1024); light.shadow.normalBias = .025;
  scene.add(light, light.target);

  return { desk, tabletop, mat, toolbox, lid, screwdriver, homePosition, blower, blowerHomePosition };
}

export type Workbench = ReturnType<typeof createWorkbench>;
