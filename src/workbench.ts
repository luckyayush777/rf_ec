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

export function createWorkbench(scene: THREE.Scene, gpu: THREE.Object3D) {
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

  // A low-profile PCB holder grips the long board edges without covering components.
  const boardBounds = new THREE.Box3().setFromObject(gpu.getObjectByName('board-substrate') ?? gpu);
  const boardCenter = boardBounds.getCenter(new THREE.Vector3());
  const boardSize = boardBounds.getSize(new THREE.Vector3());
  const pcbHolder = new THREE.Group(); pcbHolder.name = 'pcb-holder';
  pcbHolder.position.set(boardCenter.x, .055, boardCenter.z); scene.add(pcbHolder);
  const holderMetal = material('#777f83', .75, .35);
  const holderJaw = material('#38444a', .35, .55);
  const holderPad = material('#222c31', .05, .88);
  const halfZ = boardSize.z / 2;
  for (const side of [-1, 1]) {
    box('pcb-holder-rail', [boardSize.x * .87, .075, .11], holderMetal,
      [0, .035, side * (halfZ + .31)], pcbHolder, .02);
  }
  const holderJaws: { group: THREE.Group; side: number }[] = [];
  for (const side of [-1, 1]) {
    const row = new THREE.Group(); row.name = side < 0 ? 'pcb-holder-rear-jaws' : 'pcb-holder-front-jaws';
    row.position.z = side * (halfZ + .12); pcbHolder.add(row);
    for (const x of [-boardSize.x * .34, boardSize.x * .34]) {
      box('pcb-holder-jaw', [.40, .20, .22], holderJaw, [x, .15, 0], row, .026);
      box('pcb-holder-soft-pad', [.32, .13, .045], holderPad, [x, .15, -side * .12], row, .012);
      const screw = cylinder('pcb-holder-adjuster', .07, .15, holderMetal,
        [x, .15, side * .18], row); screw.rotation.x = Math.PI / 2;
      const knob = cylinder('pcb-holder-knob', .11, .055, holderMetal,
        [x, .15, side * .27], row); knob.rotation.x = Math.PI / 2;
    }
    holderJaws.push({ group: row, side });
  }
  const holderLabel = label('PCB HOLDER', 1.22, .16, '#313b40', '#dce1dc');
  holderLabel.rotation.x = -Math.PI / 2;
  holderLabel.position.set(0, .083, halfZ + .31); pcbHolder.add(holderLabel);
  function updatePCBHolder(engaged: boolean, delta: number) {
    for (const { group, side } of holderJaws) {
      const target = side * (halfZ + (engaged ? .12 : .38));
      group.position.z = THREE.MathUtils.damp(group.position.z, target, 13, delta);
    }
  }

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

  const scraper = new THREE.Group(); scraper.name = 'plastic-scraper'; scraper.userData.action = 'scraper';
  const scraperHomePosition = new THREE.Vector3(-.78, .53, .72);
  scraper.position.copy(scraperHomePosition); toolbox.add(scraper);
  box('scraper-handle', [1.02, .19, .28], material('#e6c26e', 0, .78), [-.35, 0, 0], scraper, .06);
  box('scraper-neck', [.27, .10, .19], black, [.27, 0, 0], scraper, .025);
  box('scraper-blade', [.48, .045, .58], material('#e9e5d8', 0, .65), [.61, 0, 0], scraper, .012);
  const scraperMark = label('SCRAPER', .58, .105, '#6c5534', '#f8edcf');
  scraperMark.rotation.x = -Math.PI / 2; scraperMark.position.set(-.35, .103, 0); scraper.add(scraperMark);

  // Replacement supplies have a dedicated box. Its compartments are empty for now.
  const spareParts = new THREE.Group(); spareParts.name = 'spare-parts-box'; spareParts.position.set(8, .02, -3.75); scene.add(spareParts);
  const sparePaint = material('#52606c', .18, .65);
  box('spares-bottom', [2.75, .13, 2.25], black, [0, .10, 0], spareParts);
  for (const z of [-1.05, 1.05]) box('spares-wall', [2.75, .48, .13], sparePaint, [0, .39, z], spareParts);
  for (const x of [-1.31, 1.31]) box('spares-wall', [.13, .48, 2.1], sparePaint, [x, .39, 0], spareParts);
  box('spares-divider', [.07, .32, 2.05], sparePaint, [.12, .32, 0], spareParts);
  const spareLabel = label('SPARE PARTS', 1.6, .24, '#242d35', '#e2e8e9');
  spareLabel.position.set(0, .42, 1.125); spareParts.add(spareLabel);

  const alcohol = new THREE.Group(); alcohol.name = 'cleaning-alcohol'; alcohol.position.set(7.25, .02, 1.5); scene.add(alcohol);
  const bottle = material('#e6eee9', .08, .18);
  cylinder('alcohol-bottle', .30, 1.03, bottle, [0, .57, 0], alcohol);
  cylinder('alcohol-neck', .17, .18, bottle, [0, 1.16, 0], alcohol);
  cylinder('alcohol-cap', .20, .20, material('#286d7e', .1, .42), [0, 1.34, 0], alcohol);
  const alcoholLabel = label('ALCOHOL', .55, .33, '#f4faf9', '#245765');
  alcoholLabel.position.set(0, .59, .305); alcohol.add(alcoholLabel);

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

  return { desk, tabletop, mat, pcbHolder, updatePCBHolder, toolbox, lid, screwdriver, homePosition,
    blower, blowerHomePosition, scraper, scraperHomePosition, spareParts, alcohol };
}

export type Workbench = ReturnType<typeof createWorkbench>;
