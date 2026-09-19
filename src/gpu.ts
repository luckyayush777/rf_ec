import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';

export type PartMetadata = {
  role: 'assembly' | 'fixed' | 'removable' | 'fastener';
  assembledPosition: number[];
  removalDirection?: number[];
  requires?: string[];
  attachment?: string;
};

const material = (color: string, metalness = 0, roughness = 0.5) =>
  new THREE.MeshStandardMaterial({ color, metalness, roughness });

function box(name: string, size: [number, number, number], mat: THREE.Material,
  position: [number, number, number], bevel = 0.015): THREE.Mesh {
  const mesh = new THREE.Mesh(new RoundedBoxGeometry(...size, 2, bevel), mat);
  mesh.name = name;
  mesh.position.set(...position);
  mesh.castShadow = true;
  mesh.receiveShadow = true;
  return mesh;
}

function cylinder(name: string, radius: number, height: number, mat: THREE.Material,
  position: [number, number, number], segments = 40): THREE.Mesh {
  const mesh = new THREE.Mesh(new THREE.CylinderGeometry(radius, radius, height, segments), mat);
  mesh.name = name;
  mesh.position.set(...position);
  mesh.castShadow = true;
  mesh.receiveShadow = true;
  return mesh;
}

function register(object: THREE.Object3D, metadata: Omit<PartMetadata, 'assembledPosition'>) {
  object.userData.part = { ...metadata, assembledPosition: object.position.toArray() } satisfies PartMetadata;
  return object;
}

function screw(name: string, position: [number, number, number], metal: THREE.Material,
  recess: THREE.Material, rear = false): THREE.Group {
  const group = new THREE.Group();
  group.name = name;
  group.position.set(...position);
  if (rear) group.rotation.z = Math.PI;
  group.add(cylinder(`${name}-head`, 0.065, 0.044, metal, [0, 0, 0], 24));
  const shaftLength = rear ? 0.30 : 0.25;
  group.add(cylinder(`${name}-shaft`, 0.029, shaftLength, metal, [0, -shaftLength / 2 - 0.012, 0], 16));
  group.add(box(`${name}-slot-a`, [0.075, 0.003, 0.017], recess, [0, 0.023, 0], 0.001));
  group.add(box(`${name}-slot-b`, [0.017, 0.003, 0.075], recess, [0, 0.023, 0], 0.001));
  register(group, { role: 'fastener', removalDirection: [0, rear ? -1 : 1, 0] });
  return group;
}

function roundedRectangle(width: number, height: number, radius: number) {
  const shape = new THREE.Shape();
  const x = -width / 2, y = -height / 2;
  shape.moveTo(x + radius, y);
  shape.lineTo(x + width - radius, y);
  shape.quadraticCurveTo(x + width, y, x + width, y + radius);
  shape.lineTo(x + width, y + height - radius);
  shape.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
  shape.lineTo(x + radius, y + height);
  shape.quadraticCurveTo(x, y + height, x, y + height - radius);
  shape.lineTo(x, y + radius);
  shape.quadraticCurveTo(x, y, x + radius, y);
  return shape;
}

function fanBlade(mat: THREE.Material) {
  const shape = new THREE.Shape();
  shape.moveTo(0.24, -0.06);
  shape.bezierCurveTo(0.44, -0.12, 0.69, -0.09, 0.85, 0.07);
  shape.quadraticCurveTo(0.90, 0.17, 0.79, 0.32);
  shape.bezierCurveTo(0.61, 0.16, 0.40, 0.11, 0.23, 0.10);
  shape.closePath();
  const geometry = new THREE.ExtrudeGeometry(shape, {
    depth: 0.033, bevelEnabled: true, bevelSegments: 2, steps: 1,
    bevelSize: 0.008, bevelThickness: 0.008, curveSegments: 12,
  });
  geometry.rotateX(-Math.PI / 2);
  const mesh = new THREE.Mesh(geometry, mat);
  mesh.castShadow = mesh.receiveShadow = true;
  return mesh;
}

function ring(name: string, radius: number, tube: number, mat: THREE.Material,
  position: [number, number, number]) {
  const mesh = new THREE.Mesh(new THREE.TorusGeometry(radius, tube, 12, 80), mat);
  mesh.name = name;
  mesh.rotation.x = -Math.PI / 2;
  mesh.position.set(...position);
  mesh.castShadow = mesh.receiveShadow = true;
  return mesh;
}

export function createGPU() {
  const gpu = new THREE.Group();
  gpu.name = 'gpu';
  gpu.position.y = 0.14;

  const boardMat = material('#355b49', 0.08, 0.68);
  const boardEdgeMat = material('#728365', 0, 0.8);
  const aluminum = material('#c3c7c4', 0.83, 0.37);
  const aluminumEdge = material('#d5d9d6', 0.8, 0.3);
  const steel = material('#919995', 0.83, 0.29);
  const gold = material('#c5a55b', 0.7, 0.34);
  const black = material('#111613', 0.08, 0.47);
  const bladeMat = material('#1b211d', 0.13, 0.36);
  const recess = material('#121814', 0.05, 0.72);
  const ivory = material('#d9d4b8', 0, 0.56);
  const cableBlack = material('#202623', 0, 0.58);
  const cableRed = material('#a64e3f', 0, 0.56);

  const board = new THREE.Group();
  board.name = 'board';
  board.add(box('board-substrate', [5.95, 0.115, 2.68], boardEdgeMat, [0, 0, 0], 0.035));
  board.add(box('board-top', [5.93, 0.008, 2.66], boardMat, [0, 0.061, 0], 0.022));
  board.add(box('board-bottom', [5.93, 0.008, 2.66], boardMat, [0, -0.061, 0], 0.022));
  register(board, { role: 'fixed' });
  gpu.add(board);

  const connector = new THREE.Group();
  connector.name = 'edge-connector';
  // Two tongues leave a genuine alignment notch in the connector silhouette.
  connector.add(box('connector-short-tongue', [0.51, 0.105, 0.34], boardEdgeMat, [-1.76, -0.005, 1.43], 0.012));
  connector.add(box('connector-long-tongue', [2.99, 0.105, 0.34], boardEdgeMat, [0.12, -0.005, 1.43], 0.012));
  for (let i = 0; i < 35; i++) {
    const x = -1.965 + i * 0.103;
    if (x > -1.53 && x < -1.34) continue;
    for (const side of [-1, 1]) {
      connector.add(box(`gold-contact-${i}-${side}`, [0.071, 0.009, 0.265], gold, [x, side * 0.054, 1.447], 0.004));
    }
  }
  register(connector, { role: 'fixed' });
  gpu.add(connector);

  // A perforated bracket, including a simplified rectangular display-port opening.
  const bracket = new THREE.Group();
  bracket.name = 'mounting-bracket';
  bracket.position.set(-3.035, 0.52, 0);
  const bracketShape = roundedRectangle(2.81, 1.29, 0.035);
  for (let i = 0; i < 6; i++) {
    const hole = new THREE.Path();
    const x = -1.17 + i * 0.215;
    hole.moveTo(x, -0.34); hole.lineTo(x + 0.09, -0.34);
    hole.lineTo(x + 0.09, 0.37); hole.lineTo(x, 0.37); hole.closePath();
    bracketShape.holes.push(hole);
  }
  const portHole = new THREE.Path();
  portHole.moveTo(0.31, -0.26); portHole.lineTo(1.07, -0.26);
  portHole.lineTo(1.07, 0.14); portHole.lineTo(0.31, 0.14); portHole.closePath();
  bracketShape.holes.push(portHole);
  const bracketMesh = new THREE.Mesh(new THREE.ExtrudeGeometry(bracketShape, {
    depth: 0.055, bevelEnabled: true, bevelSegments: 2, bevelSize: 0.008, bevelThickness: 0.008,
  }), steel);
  bracketMesh.name = 'bracket-plate';
  bracketMesh.rotation.y = Math.PI / 2;
  bracketMesh.castShadow = bracketMesh.receiveShadow = true;
  bracket.add(bracketMesh);
  bracket.add(box('bracket-top-flange', [0.25, 0.055, 2.81], steel, [0.097, 0.64, 0], 0.012));
  bracket.add(box('bracket-foot', [0.16, 0.045, 2.80], steel, [0.064, -0.637, 0], 0.008));
  bracket.add(box('display-port-shell', [0.30, 0.37, 0.73], aluminum, [0.19, -0.06, -0.69], 0.025));
  bracket.add(box('display-port-interior', [0.018, 0.245, 0.58], recess, [-0.016, -0.06, -0.69], 0.018));
  bracket.add(box('display-port-tongue', [0.026, 0.06, 0.43], black, [-0.029, -0.06, -0.69], 0.009));
  register(bracket, { role: 'fixed' });
  gpu.add(bracket);

  const cooler = new THREE.Group();
  cooler.name = 'cooler-assembly';
  const coolerScrewNames = ['cooler-screw-1', 'cooler-screw-2', 'cooler-screw-3', 'cooler-screw-4'];
  register(cooler, { role: 'assembly', removalDirection: [0, 1, 0], requires: ['fan-plug', ...coolerScrewNames] });
  gpu.add(cooler);

  const heatsink = new THREE.Group();
  heatsink.name = 'heatsink';
  heatsink.position.set(-0.22, 0.19, 0);
  heatsink.add(box('heatsink-base', [4.43, 0.14, 2.26], aluminum, [0, 0, 0], 0.035));
  const finGeometry = new RoundedBoxGeometry(0.065, 0.535, 2.20, 2, 0.01);
  for (let i = 0; i < 25; i++) {
    const fin = new THREE.Mesh(finGeometry, aluminum);
    fin.name = `heatsink-fin-${i + 1}`;
    fin.position.set(-2.11 + i * 4.22 / 24, 0.337, 0);
    fin.castShadow = fin.receiveShadow = true;
    heatsink.add(fin);
  }
  register(heatsink, { role: 'fixed', attachment: 'cooler-assembly' });
  cooler.add(heatsink);

  const fanAssembly = new THREE.Group();
  fanAssembly.name = 'fan-assembly';
  fanAssembly.position.set(-0.43, 0.935, 0);
  const fanScrewNames = ['fan-screw-1', 'fan-screw-2', 'fan-screw-3', 'fan-screw-4'];
  register(fanAssembly, { role: 'assembly', removalDirection: [0, 1, 0], requires: ['fan-plug', ...fanScrewNames] });
  cooler.add(fanAssembly);

  const housingShape = roundedRectangle(2.13, 2.13, 0.12);
  const opening = new THREE.Path();
  opening.absarc(0, 0, 0.933, 0, Math.PI * 2, true);
  housingShape.holes.push(opening);
  const housingGeometry = new THREE.ExtrudeGeometry(housingShape, {
    depth: 0.115, bevelEnabled: true, bevelSegments: 3, bevelSize: 0.018, bevelThickness: 0.018, curveSegments: 48,
  });
  housingGeometry.rotateX(-Math.PI / 2);
  const housing = new THREE.Mesh(housingGeometry, black);
  housing.name = 'fan-housing';
  housing.castShadow = housing.receiveShadow = true;
  fanAssembly.add(housing);
  fanAssembly.add(ring('fan-opening-lip', 0.949, 0.023, bladeMat, [0, 0.115, 0]));

  const rotor = new THREE.Group();
  rotor.name = 'fan-rotor';
  rotor.position.y = 0.026;
  for (let i = 0; i < 9; i++) {
    const blade = fanBlade(bladeMat);
    blade.name = `fan-blade-${i + 1}`;
    blade.rotation.y = i * Math.PI * 2 / 9;
    rotor.add(blade);
  }
  rotor.add(cylinder('fan-hub', 0.287, 0.15, black, [0, 0.035, 0]));
  rotor.add(cylinder('fan-hub-cap', 0.237, 0.007, bladeMat, [0, 0.114, 0]));
  rotor.add(ring('hub-inset-ring', 0.194, 0.005, black, [0, 0.12, 0]));
  rotor.add(cylinder('hub-center', 0.04, 0.008, steel, [0, 0.12, 0], 24));
  register(rotor, { role: 'fixed', attachment: 'fan-assembly' });
  fanAssembly.add(rotor);

  for (let i = 0; i < 4; i++) {
    const x = (i < 2 ? -1 : 1) * 0.93;
    const z = (i % 2 ? -1 : 1) * 0.93;
    fanAssembly.add(cylinder(`fan-mount-${i + 1}`, 0.095, 0.145, black, [x, -0.077, z], 24));
    // Bored metal posts run from the heatsink base into the fan's mounting sleeves.
    const postShape = new THREE.Shape(); postShape.absarc(0, 0, .075, 0, Math.PI * 2, false);
    const bore = new THREE.Path(); bore.absarc(0, 0, .028, 0, Math.PI * 2, true); postShape.holes.push(bore);
    const postGeometry = new THREE.ExtrudeGeometry(postShape, { depth: .60, bevelEnabled: false, curveSegments: 24 });
    postGeometry.rotateX(-Math.PI / 2);
    const post = new THREE.Mesh(postGeometry, aluminumEdge); post.name = `fan-standoff-${i + 1}`;
    post.position.set(x - .43, .26, z); post.castShadow = post.receiveShadow = true; cooler.add(post);
    cooler.add(screw(fanScrewNames[i], [x - 0.43, 1.077, z], steel, recess));
  }

  // The cable travels around the heatsink, never through the rotor or fins.
  const cableAssembly = new THREE.Group();
  cableAssembly.name = 'fan-cable';
  const cablePath = [
    [0.595, 0.986, 0.86], [0.84, 0.90, 1.17], [1.29, 0.56, 1.23],
    [2.17, 0.27, 1.15], [2.59, 0.205, 0.86], [2.54, 0.205, 0.39],
  ];
  [cableBlack, cableRed].forEach((mat, index) => {
    const points = cablePath.map(([x, y, z]) => new THREE.Vector3(x, y + index * 0.039, z));
    const curve = new THREE.CatmullRomCurve3(points);
    const wire = new THREE.Mesh(new THREE.TubeGeometry(curve, 56, 0.023, 8, false), mat);
    wire.name = index ? 'fan-positive-wire' : 'fan-ground-wire';
    wire.castShadow = wire.receiveShadow = true;
    cableAssembly.add(wire);
  });
  const plug = new THREE.Group();
  plug.name = 'fan-plug';
  plug.position.set(2.54, 0.202, 0.29);
  plug.add(box('plug-body', [0.21, 0.17, 0.24], ivory, [0, 0, 0], 0.015));
  plug.add(box('plug-tab', [0.09, 0.026, 0.09], ivory, [0, 0.095, 0.01], 0.006));
  register(plug, { role: 'removable', removalDirection: [0, 0, 1], attachment: 'board-fan-socket' });
  cableAssembly.add(plug);
  // Keep the cable under the fan assembly but preserve its assembled world transform.
  cableAssembly.position.copy(fanAssembly.position).multiplyScalar(-1);
  register(cableAssembly, { role: 'fixed', attachment: 'fan-assembly' });
  fanAssembly.add(cableAssembly);

  const socket = new THREE.Group();
  socket.name = 'board-fan-socket';
  socket.position.set(2.54, 0.19, 0.135);
  socket.add(box('socket-base', [0.30, 0.10, 0.23], ivory, [0, -0.053, 0], 0.013));
  socket.add(box('socket-back', [0.30, 0.21, 0.055], ivory, [0, 0, -0.10], 0.01));
  socket.add(box('socket-left', [0.038, 0.17, 0.21], ivory, [-0.135, -0.005, 0], 0.008));
  socket.add(box('socket-right', [0.038, 0.17, 0.21], ivory, [0.135, -0.005, 0], 0.008));
  register(socket, { role: 'fixed' });
  gpu.add(socket);

  for (let i = 0; i < 4; i++) {
    const x = (i < 2 ? -1 : 1) * 1.72 - 0.22;
    const z = (i % 2 ? -1 : 1) * 0.89;
    gpu.add(cylinder(`cooler-standoff-${i + 1}`, 0.085, 0.07, aluminumEdge, [x, 0.092, z], 24));
    gpu.add(screw(coolerScrewNames[i], [x, -0.117, z], steel, recess, true));
  }

  for (const x of [-2.66, 2.71]) {
    for (const z of [-1.09, 1.09]) {
      // Simple plated mounting marks, intentionally no circuit-board detailing.
      board.add(ring(`board-mount-ring-${x}-${z}`, 0.055, 0.009, gold, [x, 0.07, z]));
      board.add(cylinder(`board-mount-inset-${x}-${z}`, 0.041, 0.004, recess, [x, 0.068, z], 20));
    }
  }

  register(gpu, { role: 'assembly' });
  gpu.updateMatrixWorld(true);
  return { gpu, rotor };
}
