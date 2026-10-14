import * as THREE from 'three';
import { linear } from './palette';

type V2 = THREE.Vector2;

export interface BubbleOutline {
  halfWidth: number;
  halfHeight: number;
  corner: number;
  tailBase: [number, number]; // x on the bottom edge where a left-hand tail starts and ends
  tailTip: [number, number];
  mirror: boolean; // true puts the tail on the right
}

// Rounded rectangle with a speech-bubble tail, as a counter-clockwise polyline.
function polyline(s: BubbleOutline): V2[] {
  const { halfWidth: w, halfHeight: h, corner: r } = s;
  const points: V2[] = [];
  const arc = (cx: number, cy: number, a0: number, a1: number) => {
    const n = 32;
    for (let k = 0; k <= n; k++) {
      const a = a0 + ((a1 - a0) * k) / n;
      points.push(new THREE.Vector2(cx + r * Math.cos(a), cy + r * Math.sin(a)));
    }
  };
  points.push(new THREE.Vector2(s.tailBase[1], -h));
  arc(w - r, -h + r, -Math.PI / 2, 0);
  arc(w - r, h - r, 0, Math.PI / 2);
  arc(-w + r, h - r, Math.PI / 2, Math.PI);
  arc(-w + r, -h + r, Math.PI, Math.PI * 1.5);
  points.push(new THREE.Vector2(s.tailBase[0], -h));
  points.push(new THREE.Vector2(s.tailTip[0], s.tailTip[1]));
  if (s.mirror) {
    for (const p of points) p.x = -p.x;
    points.reverse();
  }
  return points;
}

function perimeter(points: V2[]): number {
  let total = 0;
  for (let i = 0; i < points.length; i++) total += points[i].distanceTo(points[(i + 1) % points.length]);
  return total;
}

function resampleClosed(points: V2[], count: number): V2[] {
  const n = points.length;
  const cumulative = [0];
  for (let i = 1; i <= n; i++) cumulative.push(cumulative[i - 1] + points[i % n].distanceTo(points[i - 1]));
  const total = cumulative[n];
  const out: V2[] = [];
  let segment = 0;
  for (let k = 0; k < count; k++) {
    const d = (k / count) * total;
    while (cumulative[segment + 1] < d) segment++;
    const span = cumulative[segment + 1] - cumulative[segment] || 1;
    out.push(new THREE.Vector2().lerpVectors(points[segment], points[(segment + 1) % n], (d - cumulative[segment]) / span));
  }
  return out;
}

function smoothClosed(points: V2[], sigmaSamples: number): V2[] {
  const n = points.length;
  const radius = Math.ceil(sigmaSamples * 3);
  const weights: number[] = [];
  let sum = 0;
  for (let k = -radius; k <= radius; k++) {
    const w = Math.exp(-(k * k) / (2 * sigmaSamples * sigmaSamples));
    weights.push(w);
    sum += w;
  }
  return points.map((_, i) => {
    let x = 0;
    let y = 0;
    for (let k = -radius; k <= radius; k++) {
      const p = points[(i + k + n * 4) % n];
      const w = weights[k + radius];
      x += p.x * w;
      y += p.y * w;
    }
    return new THREE.Vector2(x / sum, y / sum);
  });
}

function minConcaveRadius(points: V2[]): number {
  const n = points.length;
  let min = Infinity;
  for (let i = 0; i < n; i++) {
    const a = points[(i - 1 + n) % n];
    const b = points[i];
    const c = points[(i + 1) % n];
    const ux = b.x - a.x;
    const uy = b.y - a.y;
    const vx = c.x - b.x;
    const vy = c.y - b.y;
    const curvature = (2 * (ux * vy - uy * vx)) / (Math.hypot(ux, uy) * Math.hypot(vx, vy) * Math.hypot(c.x - a.x, c.y - a.y));
    if (curvature < 0) min = Math.min(min, -1 / curvature);
  }
  return min;
}

// The tail's inner corners must be rounder than the glass edge radius,
// otherwise the rounded rim folds over itself. Smooth until they are.
export function bubbleOutline(shape: BubbleOutline, minConcave: number, count = 512): V2[] {
  const dense = resampleClosed(polyline(shape), 4096);
  const spacing = perimeter(dense) / dense.length;
  let sigma = 0.05;
  let result = resampleClosed(smoothClosed(dense, sigma / spacing), count);
  for (let attempt = 0; attempt < 24 && minConcaveRadius(result) < minConcave; attempt++) {
    sigma *= 1.15;
    result = resampleClosed(smoothClosed(dense, sigma / spacing), count);
  }
  return result;
}

export interface SlabOptions {
  halfThickness: number;
  edgeRadius: number;
  dome: number;
  capRings: number;
  arcSteps: number;
}

// A thick glass tile with a pillow-rounded rim and gently domed faces, built as
// one indexed grid (outline index x profile row), so every normal is smooth:
// caps, rim and side band share vertices and refract without seams.
export function buildSlab(outline: V2[], o: SlabOptions): THREE.BufferGeometry {
  const M = outline.length;
  const normals = outline.map((_, i) => {
    const a = outline[(i - 1 + M) % M];
    const b = outline[(i + 1) % M];
    const tx = b.x - a.x;
    const ty = b.y - a.y;
    const l = Math.hypot(tx, ty) || 1;
    return new THREE.Vector2(ty / l, -tx / l);
  });
  const H = o.halfThickness;
  const R = o.edgeRadius;
  const hz = H - R;
  type Row = (i: number, out: THREE.Vector3) => void;
  const rows: Row[] = [];
  const cap = (sign: 1 | -1, rho: number): Row => (i, out) => {
    const p = outline[i];
    const lift = o.dome * Math.pow(1 - rho * rho, 2);
    out.set(p.x * rho, p.y * rho, sign * (H + lift));
  };
  const rim = (zc: number, phi: number): Row => (i, out) => {
    const p = outline[i];
    const n = normals[i];
    const c = Math.cos(phi);
    out.set(p.x + n.x * R * c, p.y + n.y * R * c, zc + R * Math.sin(phi));
  };
  for (let k = 0; k <= o.capRings; k++) rows.push(cap(1, k / o.capRings));
  for (let k = 1; k <= o.arcSteps; k++) rows.push(rim(hz, (Math.PI / 2) * (1 - k / o.arcSteps)));
  for (let k = 0; k <= o.arcSteps; k++) rows.push(rim(-hz, -(Math.PI / 2) * (k / o.arcSteps)));
  for (let k = o.capRings - 1; k >= 0; k--) rows.push(cap(-1, k / o.capRings));

  const P = rows.length;
  const positions = new Float32Array(P * M * 3);
  const v = new THREE.Vector3();
  for (let r = 0; r < P; r++) {
    for (let i = 0; i < M; i++) {
      rows[r](i, v);
      positions.set([v.x, v.y, v.z], (r * M + i) * 3);
    }
  }
  const indices: number[] = [];
  for (let r = 0; r < P - 1; r++) {
    for (let i = 0; i < M; i++) {
      const a = r * M + i;
      const b = r * M + ((i + 1) % M);
      const c = (r + 1) * M + i;
      const d = (r + 1) * M + ((i + 1) % M);
      indices.push(a, c, b, b, c, d);
    }
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geometry.setIndex(indices);
  geometry.computeVertexNormals();
  geometry.computeBoundingSphere();
  return geometry;
}

export interface BubbleSpec {
  outline: BubbleOutline;
  slab: SlabOptions;
  position: [number, number, number];
  rotation: [number, number, number];
  bob: number;
  swing: number;
  phase: number;
  material: THREE.MeshPhysicalMaterialParameters;
}

export function createBubble(spec: BubbleSpec) {
  const outline = bubbleOutline(spec.outline, spec.slab.edgeRadius * 1.3);
  const geometry = buildSlab(outline, spec.slab);
  const material = new THREE.MeshPhysicalMaterial(spec.material);
  const mesh = new THREE.Mesh(geometry, material);
  const group = new THREE.Group();
  group.add(mesh);
  const [px, py, pz] = spec.position;
  const [rx, ry, rz] = spec.rotation;
  return {
    group,
    update(theta: number) {
      const t = theta + spec.phase;
      group.position.set(px, py + spec.bob * Math.sin(t), pz + 0.04 * Math.sin(t + 1.2));
      group.rotation.set(rx + 0.035 * Math.sin(t + 0.7), ry + spec.swing * Math.sin(t), rz + 0.02 * Math.sin(2 * theta + spec.phase));
    },
    dispose() {
      geometry.dispose();
      material.dispose();
    },
  };
}

// Three warm points inside the front bubble, lit one after another like a
// slow typing indicator. Seen through frosted glass they read as soft glows.
export function createTypingDots(parent: THREE.Object3D, pulsesPerLoop: number) {
  const geometry = new THREE.SphereGeometry(0.082, 48, 24);
  const dots = [-0.36, 0, 0.36].map((x) => {
    const material = new THREE.MeshStandardMaterial({
      color: linear('#3a2a1f'),
      roughness: 0.4,
      metalness: 0,
      emissive: linear('#ffe0bd'),
      emissiveIntensity: 0.5,
    });
    const mesh = new THREE.Mesh(geometry, material);
    mesh.position.set(x, 0.03, 0);
    parent.add(mesh);
    return { mesh, material };
  });
  return {
    update(frame: number, total: number) {
      const cycle = total / pulsesPerLoop;
      dots.forEach(({ mesh, material }, i) => {
        const local = ((((frame - i * 10) % cycle) + cycle) % cycle) / cycle;
        const pulse = Math.exp(-Math.pow((local - 0.24) / 0.09, 2));
        material.emissiveIntensity = 0.8 + 3.2 * pulse;
        mesh.scale.setScalar(1 + 0.14 * pulse);
      });
    },
    dispose() {
      geometry.dispose();
      dots.forEach(({ material }) => material.dispose());
    },
  };
}
