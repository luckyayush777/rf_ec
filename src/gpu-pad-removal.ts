import * as THREE from 'three';

type PadPiece = {
  mesh: THREE.Mesh;
  width: number;
  depth: number;
  position: THREE.Vector3;
  scale: THREE.Vector3;
  progress: number;
};

/** Scraping starts in the band between two concentric pad rectangles. */
export function setupGPUPadRemoval(gpu: THREE.Object3D, coolerRemoved: () => boolean,
  notify: (text: string) => void) {
  const pieces: PadPiece[] = [];
  const byMesh = new Map<THREE.Object3D, PadPiece>();
  gpu.traverse(object => {
    if (!(object instanceof THREE.Mesh)) return;
    const match = /^memory-residue-(\d+)-(\d+)$/.exec(object.name);
    if (!match) return;
    object.geometry.computeBoundingBox();
    const size = object.geometry.boundingBox!.getSize(new THREE.Vector3());
    const piece: PadPiece = {
      mesh: object,
      width: size.x * object.scale.x,
      depth: size.z * object.scale.z,
      position: object.position.clone(), scale: object.scale.clone(), progress: 0,
    };
    object.userData.action = 'residue';
    pieces.push(piece); byMesh.set(object, piece);
  });
  const output = document.querySelector<HTMLOutputElement>('#pad-removal-progress')!;
  let active: {
    piece: PadPiece; plane: THREE.Plane; axis: 0 | 2; outward: number;
    furthestAlong: number; originalMaterial: THREE.Material | THREE.Material[];
    highlighted: THREE.Material[]; guides: THREE.LineLoop[];
  } | null = null;
  function end() {
    if (!active) return;
    active.piece.mesh.material = active.originalMaterial;
    active.highlighted.forEach(material => material.dispose());
    active.guides.forEach(guide => {
      guide.removeFromParent(); guide.geometry.dispose();
      (guide.material as THREE.Material).dispose();
    });
    active = null;
  }
  function rectangleGuide(piece: PadPiece, fraction: number, color: string) {
    const bounds = piece.mesh.geometry.boundingBox!;
    const center = bounds.getCenter(new THREE.Vector3());
    const halfX = (bounds.max.x - bounds.min.x) * fraction / 2;
    const halfZ = (bounds.max.z - bounds.min.z) * fraction / 2;
    const y = bounds.max.y + .003;
    const points = [
      new THREE.Vector3(center.x - halfX, y, center.z - halfZ),
      new THREE.Vector3(center.x + halfX, y, center.z - halfZ),
      new THREE.Vector3(center.x + halfX, y, center.z + halfZ),
      new THREE.Vector3(center.x - halfX, y, center.z + halfZ),
    ];
    const guide = new THREE.LineLoop(new THREE.BufferGeometry().setFromPoints(points),
      new THREE.LineBasicMaterial({ color, depthTest: false }));
    guide.renderOrder = 2;
    piece.mesh.add(guide);
    return guide;
  }
  function update() {
    const progress = pieces.reduce((sum, piece) => sum + piece.progress, 0) / Math.max(1, pieces.length);
    output.value = `${Math.round(progress * 100)}% old pad material cleared`;
  }
  function reset() {
    end();
    for (const piece of pieces) {
      piece.mesh.position.copy(piece.position);
      piece.mesh.scale.copy(piece.scale);
      piece.mesh.visible = true;
      piece.progress = 0;
    }
    update();
  }
  function begin(target: THREE.Object3D | undefined, point: THREE.Vector3) {
    end();
    const piece = target ? byMesh.get(target) : undefined;
    if (!piece || !piece.mesh.visible) return false;
    if (!coolerRemoved()) { notify('Remove the cooler to reach the memory pads.'); return false; }
    piece.mesh.updateWorldMatrix(true, false);
    const local = piece.mesh.parent!.worldToLocal(point.clone());
    const x = local.x - piece.position.x, z = local.z - piece.position.z;
    const halfWidth = piece.width * (1 - piece.progress) / 2;
    const halfDepth = piece.depth * (1 - piece.progress) / 2;
    const inOuter = Math.abs(x) <= halfWidth * 1.05 && Math.abs(z) <= halfDepth * 1.05;
    const inInner = Math.abs(x) < halfWidth * .55 && Math.abs(z) < halfDepth * .55;
    if (!inOuter || inInner) {
      notify('Start in the outer band of the old pad, then drag inward.');
      return false;
    }
    const axis: 0 | 2 = Math.abs(x / halfWidth) >= Math.abs(z / halfDepth) ? 0 : 2;
    const outward = Math.sign(axis === 0 ? x : z) || 1;
    const normal = new THREE.Vector3(0, 1, 0).transformDirection(piece.mesh.parent!.matrixWorld);
    const plane = new THREE.Plane().setFromNormalAndCoplanarPoint(normal,
      piece.mesh.getWorldPosition(new THREE.Vector3()));
    const originalMaterial = piece.mesh.material;
    const highlighted = (Array.isArray(originalMaterial) ? originalMaterial : [originalMaterial]).map(material => {
      const copy = material.clone();
      if (copy instanceof THREE.MeshStandardMaterial) {
        copy.color.lerp(new THREE.Color('#f5a0a0'), .58);
        copy.emissive.set('#ff7777'); copy.emissiveIntensity = .55;
      } else if (copy instanceof THREE.MeshBasicMaterial) copy.color.set('#f5a0a0');
      return copy;
    });
    piece.mesh.material = Array.isArray(originalMaterial) ? highlighted : highlighted[0];
    const guides = [rectangleGuide(piece, 1, '#ffd5d5'), rectangleGuide(piece, .55, '#ff7474')];
    active = { piece, plane, axis, outward,
      furthestAlong: outward * local.getComponent(axis), originalMaterial, highlighted, guides };
    return true;
  }
  function drag(ray: THREE.Ray) {
    if (!active || !coolerRemoved()) return false;
    const { piece, plane, axis, outward } = active;
    const hit = ray.intersectPlane(plane, new THREE.Vector3());
    if (!hit) return false;
    const local = piece.mesh.parent!.worldToLocal(hit);
    const crossAxis = axis === 0 ? 2 : 0;
    const crossExtent = axis === 0 ? piece.depth : piece.width;
    const extent = axis === 0 ? piece.width : piece.depth;
    if (Math.abs(local.getComponent(crossAxis) - piece.position.getComponent(crossAxis)) > crossExtent * .7 + .04) return false;
    const along = THREE.MathUtils.clamp(outward * local.getComponent(axis),
      outward * piece.position.getComponent(axis) - extent * .65,
      outward * piece.position.getComponent(axis) + extent * .65);
    const inwardTravel = Math.max(0, active.furthestAlong - along);
    active.furthestAlong = Math.min(active.furthestAlong, along);
    if (inwardTravel < .001) return false;
    piece.progress = Math.min(1, piece.progress + inwardTravel / (extent * .75));
    const remaining = Math.max(.001, 1 - piece.progress);
    piece.mesh.scale.x = piece.scale.x * remaining;
    piece.mesh.scale.z = piece.scale.z * remaining;
    if (piece.progress === 1) {
      piece.mesh.visible = false;
      end();
      notify('A piece of old pad material has been scraped clear.');
    }
    update();
    return true;
  }
  document.addEventListener('bench-next-job', reset);
  update();
  return { pieces: pieces.map(piece => piece.mesh), begin, drag, end, reset,
    get progress() { return pieces.reduce((sum, piece) => sum + piece.progress, 0) / Math.max(1, pieces.length); },
    dispose() { end(); document.removeEventListener('bench-next-job', reset); } };
}
