import * as THREE from 'three';
import { TAU } from './loop';
import { linear } from './palette';

export interface RibbonSpec {
  points: Array<[number, number, number]>;
  halfWidth: number;
  widthSwell: number;
  color: string;
  sheenColor: string;
  roughness: number;
  sheenRoughness: number;
  twistBase: number;
  twistA: number;
  twistFreqA: number;
  twistB: number;
  twistFreqB: number;
  rippleA: number;
  rippleFreqA: number;
  rippleB: number;
  rippleFreqB: number;
  curl: number; // cross-section bend, so light rolls across the width like draped fabric
  sway: number;
  phase: number;
  segmentsU?: number;
  segmentsV?: number;
}

// A satin ribbon: a strip swept along a spline, twisted around the spline and
// rippled across its width. Positions are rebuilt on the CPU for every frame,
// which keeps the motion exact and loop-safe; normals are recomputed so the
// sheen follows every fold.
export function createRibbon(spec: RibbonSpec) {
  const NU = spec.segmentsU ?? 320;
  const NV = spec.segmentsV ?? 40;
  const curve = new THREE.CatmullRomCurve3(
    spec.points.map(([x, y, z]) => new THREE.Vector3(x, y, z)),
    false,
    'centripetal',
  );
  const frames = curve.computeFrenetFrames(NU - 1, false);
  const centers = Array.from({ length: NU }, (_, i) => curve.getPointAt(i / (NU - 1)));

  const positions = new Float32Array(NU * NV * 3);
  const uvs = new Float32Array(NU * NV * 2);
  const indices: number[] = [];
  for (let i = 0; i < NU; i++) {
    for (let j = 0; j < NV; j++) {
      uvs[(i * NV + j) * 2] = i / (NU - 1);
      uvs[(i * NV + j) * 2 + 1] = j / (NV - 1);
    }
  }
  for (let i = 0; i < NU - 1; i++) {
    for (let j = 0; j < NV - 1; j++) {
      const a = i * NV + j;
      const b = (i + 1) * NV + j;
      const c = (i + 1) * NV + j + 1;
      const d = i * NV + j + 1;
      indices.push(a, b, d, b, c, d);
    }
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setIndex(indices);
  const position = new THREE.BufferAttribute(positions, 3).setUsage(THREE.DynamicDrawUsage);
  geometry.setAttribute('position', position);
  geometry.setAttribute('uv', new THREE.BufferAttribute(uvs, 2));

  const material = new THREE.MeshPhysicalMaterial({
    color: linear(spec.color),
    roughness: spec.roughness,
    metalness: 0,
    sheen: 1,
    sheenRoughness: spec.sheenRoughness,
    sheenColor: linear(spec.sheenColor),
    specularIntensity: 0.9,
    envMapIntensity: 1.2,
    side: THREE.DoubleSide,
  });
  const mesh = new THREE.Mesh(geometry, material);
  mesh.frustumCulled = false;

  const across = new THREE.Vector3();
  const lift = new THREE.Vector3();
  const center = new THREE.Vector3();

  return {
    mesh,
    update(theta: number) {
      for (let i = 0; i < NU; i++) {
        const u = i / (NU - 1);
        const N = frames.normals[i];
        const B = frames.binormals[i];
        center.copy(centers[i]);
        center.y += spec.sway * Math.sin(TAU * 0.9 * u + theta + spec.phase);
        center.z += spec.sway * 1.3 * Math.sin(TAU * 0.55 * u - theta + spec.phase + 1.0);
        const twist =
          spec.twistBase +
          spec.twistA * Math.sin(TAU * spec.twistFreqA * u + theta + spec.phase) +
          spec.twistB * Math.sin(TAU * spec.twistFreqB * u - theta + 1.7 * spec.phase);
        const cs = Math.cos(twist);
        const sn = Math.sin(twist);
        across.copy(B).multiplyScalar(cs).addScaledVector(N, sn);
        lift.copy(N).multiplyScalar(cs).addScaledVector(B, -sn);
        const halfWidth = spec.halfWidth + spec.widthSwell * Math.sin(Math.PI * u);
        for (let j = 0; j < NV; j++) {
          const v = (j / (NV - 1)) * 2 - 1;
          const bend = spec.curl * (v * v - 0.35) * (1 + 0.3 * Math.sin(TAU * 1.3 * u - theta + spec.phase));
          const ripple =
            bend +
            (spec.rippleA * Math.sin(TAU * spec.rippleFreqA * u + 1.4 * v - theta + spec.phase) +
              spec.rippleB * Math.sin(TAU * spec.rippleFreqB * u - 2.2 * v + 2 * theta + spec.phase)) *
            (0.55 + 0.45 * v * v);
          const k = (i * NV + j) * 3;
          positions[k] = center.x + across.x * v * halfWidth + lift.x * ripple;
          positions[k + 1] = center.y + across.y * v * halfWidth + lift.y * ripple;
          positions[k + 2] = center.z + across.z * v * halfWidth + lift.z * ripple;
        }
      }
      position.needsUpdate = true;
      geometry.computeVertexNormals();
    },
    dispose() {
      geometry.dispose();
      material.dispose();
    },
  };
}
