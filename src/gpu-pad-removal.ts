import * as THREE from 'three';

const MASK_SIZE = 64;
const MASK_CELLS = MASK_SIZE * MASK_SIZE;

type PadPiece = {
  mesh: THREE.Mesh;
  bounds: THREE.Box3;
  size: THREE.Vector3;
  mask: Uint8Array;
  texture: THREE.DataTexture;
  remaining: number;
  sourceMaterial: THREE.Material | THREE.Material[];
  workingMaterial: THREE.Material | THREE.Material[];
  originalRaycast: THREE.Mesh['raycast'];
  sourceCastShadow: boolean;
};
type Rectangle = { minX: number; maxX: number; minZ: number; maxZ: number };

/** A held inward drag erases a strip of residue, leaving untouched material in place. */
export function setupGPUPadRemoval(gpu: THREE.Object3D, coolerRemoved: () => boolean,
  notify: (text: string) => void) {
  const pieces: PadPiece[] = [];
  const byMesh = new Map<THREE.Object3D, PadPiece>();
  function pixelAt(piece: PadPiece, point: THREE.Vector3) {
    const u = (point.x - piece.bounds.min.x) / piece.size.x;
    const v = (point.z - piece.bounds.min.z) / piece.size.z;
    if (u < 0 || u > 1 || v < 0 || v > 1) return -1;
    return Math.min(MASK_SIZE - 1, Math.floor(v * MASK_SIZE)) * MASK_SIZE +
      Math.min(MASK_SIZE - 1, Math.floor(u * MASK_SIZE));
  }
  function visibleAt(piece: PadPiece, point: THREE.Vector3) {
    const pixel = pixelAt(piece, point);
    return pixel >= 0 && piece.mask[pixel] !== 0;
  }
  function remainingRectangle(piece: PadPiece): Rectangle | null {
    let minX = MASK_SIZE, maxX = -1, minZ = MASK_SIZE, maxZ = -1;
    for (let z = 0; z < MASK_SIZE; z++) for (let x = 0; x < MASK_SIZE; x++) {
      if (!piece.mask[z * MASK_SIZE + x]) continue;
      minX = Math.min(minX, x); maxX = Math.max(maxX, x);
      minZ = Math.min(minZ, z); maxZ = Math.max(maxZ, z);
    }
    if (maxX < 0) return null;
    return {
      minX: piece.bounds.min.x + minX / MASK_SIZE * piece.size.x,
      maxX: piece.bounds.min.x + (maxX + 1) / MASK_SIZE * piece.size.x,
      minZ: piece.bounds.min.z + minZ / MASK_SIZE * piece.size.z,
      maxZ: piece.bounds.min.z + (maxZ + 1) / MASK_SIZE * piece.size.z,
    };
  }
  function paintSegment(piece: PadPiece, from: THREE.Vector3, to: THREE.Vector3) {
    const radius = Math.min(piece.size.x, piece.size.z) * .18;
    const dx = to.x - from.x, dz = to.z - from.z;
    const lengthSquared = dx * dx + dz * dz;
    let erased = 0;
    for (let z = 0; z < MASK_SIZE; z++) for (let x = 0; x < MASK_SIZE; x++) {
      const index = z * MASK_SIZE + x;
      if (!piece.mask[index]) continue;
      const px = piece.bounds.min.x + (x + .5) / MASK_SIZE * piece.size.x;
      const pz = piece.bounds.min.z + (z + .5) / MASK_SIZE * piece.size.z;
      const t = lengthSquared ? THREE.MathUtils.clamp(((px - from.x) * dx + (pz - from.z) * dz) / lengthSquared, 0, 1) : 0;
      const distanceX = px - from.x - t * dx, distanceZ = pz - from.z - t * dz;
      if (distanceX * distanceX + distanceZ * distanceZ > radius * radius) continue;
      piece.mask[index] = 0;
      erased++;
    }
    if (erased) { piece.remaining -= erased; piece.texture.needsUpdate = true; }
    return erased;
  }
  gpu.traverse(object => {
    if (!(object instanceof THREE.Mesh) || !/^memory-residue-\d+-\d+$/.test(object.name)) return;
    object.geometry.computeBoundingBox();
    const bounds = object.geometry.boundingBox!.clone();
    const size = bounds.getSize(new THREE.Vector3());
    const mask = new Uint8Array(MASK_CELLS).fill(255);
    const texture = new THREE.DataTexture(mask, MASK_SIZE, MASK_SIZE, THREE.RedFormat);
    texture.minFilter = texture.magFilter = THREE.NearestFilter;
    texture.needsUpdate = true;
    const sourceMaterial = object.material;
    const workingMaterials = (Array.isArray(sourceMaterial) ? sourceMaterial : [sourceMaterial]).map(source => {
      const material = source.clone();
      const previousCompile = source.onBeforeCompile;
      material.onBeforeCompile = (shader: Parameters<THREE.Material['onBeforeCompile']>[0],
        renderer: THREE.WebGLRenderer) => {
        previousCompile.call(material, shader, renderer);
        shader.uniforms.residueMask = { value: texture };
        shader.uniforms.residueBounds = { value: new THREE.Vector4(bounds.min.x, bounds.min.z, size.x, size.z) };
        shader.vertexShader = 'varying vec2 residueUv; uniform vec4 residueBounds;\n' + shader.vertexShader;
        shader.vertexShader = shader.vertexShader.replace('#include <begin_vertex>',
          '#include <begin_vertex>\nresidueUv = (position.xz - residueBounds.xy) / residueBounds.zw;');
        shader.fragmentShader = 'varying vec2 residueUv; uniform sampler2D residueMask;\n' + shader.fragmentShader;
        shader.fragmentShader = shader.fragmentShader.replace('#include <clipping_planes_fragment>',
          '#include <clipping_planes_fragment>\nif (texture2D(residueMask, clamp(residueUv, 0.0, 0.9999)).r < 0.5) discard;');
      };
      material.customProgramCacheKey = () => 'gpu-pad-scrape-v1';
      return material;
    });
    const workingMaterial = Array.isArray(sourceMaterial) ? workingMaterials : workingMaterials[0];
    const piece: PadPiece = {
      mesh: object, bounds, size, mask, texture, remaining: MASK_CELLS,
      sourceMaterial, workingMaterial, originalRaycast: object.raycast, sourceCastShadow: object.castShadow,
    };
    object.material = workingMaterial;
    object.raycast = (raycaster, intersections) => {
      const start = intersections.length;
      piece.originalRaycast.call(object, raycaster, intersections);
      for (let i = intersections.length - 1; i >= start; i--) {
        if (!visibleAt(piece, object.worldToLocal(intersections[i].point.clone()))) intersections.splice(i, 1);
      }
    };
    object.userData.action = 'residue';
    object.castShadow = false;
    pieces.push(piece); byMesh.set(object, piece);
  });
  const output = document.querySelector<HTMLOutputElement>('#pad-removal-progress')!;
  let active: {
    piece: PadPiece; plane: THREE.Plane; axis: 0 | 2; outward: number;
    furthestAlong: number; lastPoint: THREE.Vector3;
    highlighted: THREE.Material[]; guides: THREE.LineLoop[];
  } | null = null;
  function end() {
    if (!active) return;
    active.piece.mesh.material = active.piece.workingMaterial;
    active.highlighted.forEach(material => material.dispose());
    active.guides.forEach(guide => {
      guide.removeFromParent(); guide.geometry.dispose();
      (guide.material as THREE.Material).dispose();
    });
    active = null;
  }
  function rectangleGuide(piece: PadPiece, rect: Rectangle, fraction: number, color: string) {
    const centerX = (rect.minX + rect.maxX) / 2, centerZ = (rect.minZ + rect.maxZ) / 2;
    const halfX = (rect.maxX - rect.minX) * fraction / 2;
    const halfZ = (rect.maxZ - rect.minZ) * fraction / 2;
    const y = piece.bounds.max.y + .003;
    const points = [
      new THREE.Vector3(centerX - halfX, y, centerZ - halfZ),
      new THREE.Vector3(centerX + halfX, y, centerZ - halfZ),
      new THREE.Vector3(centerX + halfX, y, centerZ + halfZ),
      new THREE.Vector3(centerX - halfX, y, centerZ + halfZ),
    ];
    const guide = new THREE.LineLoop(new THREE.BufferGeometry().setFromPoints(points),
      new THREE.LineBasicMaterial({ color, depthTest: false }));
    guide.renderOrder = 2;
    piece.mesh.add(guide);
    return guide;
  }
  function update() {
    const total = pieces.length * MASK_CELLS;
    const remaining = pieces.reduce((sum, piece) => sum + piece.remaining, 0);
    output.value = `${total ? Math.round((1 - remaining / total) * 100) : 100}% old pad material cleared`;
  }
  function reset() {
    end();
    for (const piece of pieces) {
      piece.mask.fill(255); piece.texture.needsUpdate = true;
      piece.remaining = MASK_CELLS; piece.mesh.visible = true;
    }
    update();
  }
  function begin(target: THREE.Object3D | undefined, point: THREE.Vector3) {
    end();
    const piece = target ? byMesh.get(target) : undefined;
    if (!piece || !piece.mesh.visible) return false;
    if (!coolerRemoved()) { notify('Remove the cooler to reach the memory pads.'); return false; }
    piece.mesh.updateWorldMatrix(true, false);
    const local = piece.mesh.worldToLocal(point.clone());
    const rect = remainingRectangle(piece);
    if (!rect || !visibleAt(piece, local)) return false;
    const centerX = (rect.minX + rect.maxX) / 2, centerZ = (rect.minZ + rect.maxZ) / 2;
    const halfX = (rect.maxX - rect.minX) / 2, halfZ = (rect.maxZ - rect.minZ) / 2;
    const x = local.x - centerX, z = local.z - centerZ;
    const inOuter = Math.abs(x) <= halfX * 1.05 && Math.abs(z) <= halfZ * 1.05;
    const inInner = Math.abs(x) < halfX * .55 && Math.abs(z) < halfZ * .55;
    if (!inOuter || inInner) {
      notify('Start in the outer band of the old pad, then drag toward the opposite edge.');
      return false;
    }
    const axis: 0 | 2 = Math.abs(x / halfX) >= Math.abs(z / halfZ) ? 0 : 2;
    const outward = Math.sign(axis === 0 ? x : z) || 1;
    const boundary = axis === 0 ? outward > 0 ? rect.maxX : rect.minX : outward > 0 ? rect.maxZ : rect.minZ;
    const lastPoint = local.clone().setComponent(axis, boundary);
    const normal = new THREE.Vector3(0, 1, 0).transformDirection(piece.mesh.matrixWorld);
    const plane = new THREE.Plane().setFromNormalAndCoplanarPoint(normal, point);
    const highlighted = (Array.isArray(piece.workingMaterial) ? piece.workingMaterial : [piece.workingMaterial]).map(material => {
      const copy = material.clone();
      copy.onBeforeCompile = material.onBeforeCompile;
      copy.customProgramCacheKey = material.customProgramCacheKey;
      if (copy instanceof THREE.MeshStandardMaterial) {
        copy.color.lerp(new THREE.Color('#f5a0a0'), .58);
        copy.emissive.set('#ff7777'); copy.emissiveIntensity = .55;
      } else if (copy instanceof THREE.MeshBasicMaterial) copy.color.set('#f5a0a0');
      return copy;
    });
    piece.mesh.material = Array.isArray(piece.workingMaterial) ? highlighted : highlighted[0];
    const guides = [rectangleGuide(piece, rect, 1, '#ffd5d5'), rectangleGuide(piece, rect, .55, '#ff7474')];
    active = { piece, plane, axis, outward,
      furthestAlong: outward * local.getComponent(axis), lastPoint, highlighted, guides };
    return true;
  }
  function drag(ray: THREE.Ray) {
    if (!active || !coolerRemoved()) return false;
    const { piece, plane, axis, outward } = active;
    const hit = ray.intersectPlane(plane, new THREE.Vector3());
    if (!hit) return false;
    const local = piece.mesh.worldToLocal(hit);
    const crossAxis = axis === 0 ? 2 : 0;
    const center = piece.bounds.getCenter(new THREE.Vector3());
    if (Math.abs(local.getComponent(crossAxis) - center.getComponent(crossAxis)) >
      piece.size.getComponent(crossAxis) * .65) return false;
    const along = outward * local.getComponent(axis);
    if (along >= active.furthestAlong - .001) return false;
    active.furthestAlong = along;
    const erased = paintSegment(piece, active.lastPoint, local);
    active.lastPoint.copy(local);
    if (!erased) return false;
    if (piece.remaining / MASK_CELLS <= .02) {
      piece.mask.fill(0); piece.remaining = 0; piece.texture.needsUpdate = true;
      piece.mesh.visible = false; end();
      notify('A piece of old pad material has been scraped clear.');
    }
    update();
    return true;
  }
  document.addEventListener('bench-next-job', reset);
  update();
  return { pieces: pieces.map(piece => piece.mesh), begin, drag, end, reset,
    get progress() {
      const total = pieces.length * MASK_CELLS;
      return total ? 1 - pieces.reduce((sum, piece) => sum + piece.remaining, 0) / total : 1;
    },
    dispose() {
      end(); document.removeEventListener('bench-next-job', reset);
      for (const piece of pieces) {
        piece.mesh.raycast = piece.originalRaycast;
        piece.mesh.material = piece.sourceMaterial;
        piece.mesh.castShadow = piece.sourceCastShadow;
        (Array.isArray(piece.workingMaterial) ? piece.workingMaterial : [piece.workingMaterial]).forEach(material => material.dispose());
        piece.texture.dispose();
      }
    },
  };
}
