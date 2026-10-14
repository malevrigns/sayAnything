import * as THREE from 'three';
import { bubbleOutline } from '../stage/glass';
import { TAU, mulberry32 } from '../stage/loop';
import { HEX, linear } from '../stage/palette';

// The one engine: every particle orbits in the signal disk; about a quarter of
// them also own a target on the speech bubble. The beam front decides when a
// particle leaves its orbit and lands; the erase front sends it back. Position
// is a pure function of the loop phase plus those two fronts, so any frame can
// be rendered on its own.

export const BUBBLE_SHAPE = {
  halfWidth: 1.0,
  halfHeight: 0.72,
  corner: 0.4,
  tailBase: [-0.6, -0.16] as [number, number],
  tailTip: [-0.95, -1.22] as [number, number],
  mirror: false,
};
export const FRONT_Z = 0.11;
export const DOT_X = [-0.36, 0, 0.36];
export const DOT_Y = 0.03;
const DOT_Z = 0.13;
const DOT_RADIUS = 0.085;

// Roles: 0 disk only · 1 front rim · 2 back rim / side wall · 3 face dot matrix · 4–6 typing dots
interface Target {
  role: number;
  x: number;
  y: number;
  z: number;
  bright: number;
}

const gauss = (rand: () => number) => Math.sqrt(-2 * Math.log(rand() + 1e-9)) * Math.cos(TAU * rand());

function insidePolygon(x: number, y: number, poly: THREE.Vector2[]) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const a = poly[i];
    const b = poly[j];
    if (a.y > y !== b.y > y && x < ((b.x - a.x) * (y - a.y)) / (b.y - a.y) + a.x) inside = !inside;
  }
  return inside;
}

export function bubbleOutlinePoints() {
  return bubbleOutline(BUBBLE_SHAPE, 0.08, 720);
}

function bubbleTargets(rand: () => number): Target[] {
  const outline = bubbleOutlinePoints();
  const lengths = [0];
  for (let i = 1; i <= outline.length; i++) lengths.push(lengths[i - 1] + outline[i % outline.length].distanceTo(outline[i - 1]));
  const total = lengths[outline.length];
  const at = (s: number) => {
    const d = s * total;
    let k = 0;
    while (lengths[k + 1] < d) k++;
    const span = lengths[k + 1] - lengths[k] || 1;
    const p = new THREE.Vector2().lerpVectors(outline[k], outline[(k + 1) % outline.length], (d - lengths[k]) / span);
    const q = outline[(k + 1) % outline.length].clone().sub(outline[k]).normalize();
    return { p, n: new THREE.Vector2(q.y, -q.x) };
  };

  const targets: Target[] = [];
  for (let i = 0; i < 9000; i++) {
    const { p, n } = at(rand());
    const jitter = gauss(rand) * 0.0035;
    targets.push({ role: 1, x: p.x + n.x * jitter, y: p.y + n.y * jitter, z: FRONT_Z, bright: 0.065 });
  }
  for (let i = 0; i < 4200; i++) {
    const { p } = at(rand());
    targets.push({ role: 2, x: p.x, y: p.y, z: -FRONT_Z, bright: 0.04 });
  }
  for (let i = 0; i < 2400; i++) {
    const { p } = at(rand());
    targets.push({ role: 2, x: p.x, y: p.y, z: (rand() * 2 - 1) * FRONT_Z, bright: 0.03 });
  }
  // Face: a dot matrix on the front pane, brighter toward the upper right.
  const step = 0.072;
  for (let gx = -1; gx <= 1; gx += step) {
    for (let gy = -0.72; gy <= 0.72; gy += step) {
      if (!insidePolygon(gx, gy, outline)) continue;
      let edge = Infinity;
      for (const o of outline) edge = Math.min(edge, Math.hypot(o.x - gx, o.y - gy));
      if (edge < 0.07) continue;
      if (DOT_X.some((dx) => Math.hypot(gx - dx, gy - DOT_Y) < DOT_RADIUS + 0.05)) continue;
      const shade = 0.35 + 0.65 * THREE.MathUtils.smoothstep(gx * 0.6 + gy * 0.8, -0.9, 0.9);
      for (let k = 0; k < 3; k++) {
        targets.push({ role: 3, x: gx + gauss(rand) * 0.003, y: gy + gauss(rand) * 0.003, z: FRONT_Z - 0.004, bright: 0.11 * shade });
      }
    }
  }
  // Typing dots: filled discs. Their target is stored as an offset from the
  // dot centre so the lock can spring the cluster open from nothing.
  for (let d = 0; d < 3; d++) {
    for (let i = 0; i < 2600; i++) {
      const r = DOT_RADIUS * Math.sqrt(rand());
      const a = TAU * rand();
      targets.push({ role: 4 + d, x: r * Math.cos(a), y: r * Math.sin(a), z: (rand() - 0.5) * 0.012, bright: 0.2 });
    }
  }
  return targets;
}

// Concentric density bands give the disk an engineered, ring-like structure
// that is invariant under rotation, so differential orbit speeds never smear it.
const BANDS = [
  { weight: 0.24, r: 1.7, w: 0.03, bright: 0.17 },
  { weight: 0.16, r: 2.22, w: 0.05, bright: 0.15 },
  { weight: 0.14, r: 2.95, w: 0.08, bright: 0.12 },
  { weight: 0.46, r: 0, w: 0, bright: 0.07 },
];

function diskSample(rand: () => number) {
  let pick = rand();
  let band = BANDS[BANDS.length - 1];
  for (const b of BANDS) {
    if (pick < b.weight) {
      band = b;
      break;
    }
    pick -= b.weight;
  }
  const r = band.r > 0 ? band.r + gauss(rand) * band.w : 1.55 + 3.1 * Math.pow(rand(), 1.45);
  const y = gauss(rand) * (0.012 + 0.016 * Math.max(0, r - 1.5));
  return { r, phi: TAU * rand(), y, laps: r < 2.0 ? 2 : 1, bright: band.bright * (0.6 + 0.8 * rand()) };
}

export interface ParticleUniforms {
  uT: { value: number };
  uTheta: { value: number };
  uDisk: { value: THREE.Matrix4 };
  uBubble: { value: THREE.Matrix4 };
  uScanX: { value: number };
  uEraseX: { value: number };
  uScanGlow: { value: number };
  uDotPop: { value: THREE.Vector3 };
  uDotGlow: { value: THREE.Vector3 };
  uFlash: { value: number };
  uFocus: { value: number };
}

export function createSignalParticles(options: { seed: number; diskCount: number; cocScale: number; maxCoc: number }) {
  const rand = mulberry32(options.seed);
  const targets = bubbleTargets(rand);
  const count = options.diskCount + targets.length;

  const aDisk = new Float32Array(count * 4);
  const aRand = new Float32Array(count * 4);
  const aTarget = new Float32Array(count * 3);
  const aRole = new Float32Array(count);
  const aBright = new Float32Array(count * 2);
  const aColor = new Float32Array(count * 3);
  const silver = linear(HEX.silver);
  const electric = linear(HEX.electric);
  const warmWhite = linear('#f3efe6');

  for (let i = 0; i < count; i++) {
    const d = diskSample(rand);
    aDisk.set([d.r, d.phi, d.y, d.laps], i * 4);
    aRand.set([rand(), rand(), rand(), rand()], i * 4);
    const accent = rand() < 0.07;
    const base = accent ? electric : rand() < 0.25 ? warmWhite : silver;
    aColor.set([base.r, base.g, base.b], i * 3);
    aBright[i * 2] = d.bright * (accent ? 1.2 : 1);
    const target = i >= options.diskCount ? targets[i - options.diskCount] : null;
    if (target) {
      aTarget.set([target.x, target.y, target.z], i * 3);
      aRole[i] = target.role;
      aBright[i * 2 + 1] = target.bright;
    }
  }

  const geometry = new THREE.BufferGeometry();
  // Positions are computed in the vertex shader; this attribute only sizes the draw.
  geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(count * 3), 3));
  geometry.setAttribute('aDisk', new THREE.BufferAttribute(aDisk, 4));
  geometry.setAttribute('aRand', new THREE.BufferAttribute(aRand, 4));
  geometry.setAttribute('aTarget', new THREE.BufferAttribute(aTarget, 3));
  geometry.setAttribute('aRole', new THREE.BufferAttribute(aRole, 1));
  geometry.setAttribute('aBright', new THREE.BufferAttribute(aBright, 2));
  geometry.setAttribute('aColor', new THREE.BufferAttribute(aColor, 3));

  const uniforms: ParticleUniforms & Record<string, THREE.IUniform> = {
    uT: { value: 0 },
    uTheta: { value: 0 },
    uDisk: { value: new THREE.Matrix4() },
    uBubble: { value: new THREE.Matrix4() },
    uScanX: { value: 9 },
    uEraseX: { value: -9 },
    uScanGlow: { value: 0 },
    uDotPop: { value: new THREE.Vector3(1, 1, 1) },
    uDotGlow: { value: new THREE.Vector3() },
    uFlash: { value: 0 },
    uFocus: { value: 10 },
    uK: { value: options.cocScale },
    uMax: { value: options.maxCoc },
    uMin: { value: 1.6 },
    uFalloff: { value: 1.55 },
    uLime: { value: linear(HEX.electric) },
    uRim: { value: linear('#f4f8ff') },
    uDotX: { value: new THREE.Vector3(...DOT_X) },
    uDotYZ: { value: new THREE.Vector2(DOT_Y, DOT_Z) },
  };

  const material = new THREE.ShaderMaterial({
    uniforms,
    transparent: true,
    depthTest: false,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
    vertexShader: /* glsl */ `
      uniform float uT, uTheta, uScanX, uEraseX, uScanGlow, uFlash;
      uniform mat4 uDisk, uBubble;
      uniform vec3 uDotPop, uDotGlow, uLime, uRim, uDotX;
      uniform vec2 uDotYZ;
      uniform float uFocus, uK, uMax, uMin, uFalloff;
      attribute vec4 aDisk;
      attribute vec4 aRand;
      attribute vec3 aTarget;
      attribute float aRole;
      attribute vec2 aBright;
      attribute vec3 aColor;
      varying vec3 vColor;
      varying float vSize;
      const float TAU = 6.28318530718;
      const float LEAD = 0.55;

      float pick(vec3 v, float i) { return i < 0.5 ? v.x : (i < 1.5 ? v.y : v.z); }

      void main() {
        // Orbit: integer laps per loop keep every particle periodic.
        float phi = aDisk.y + TAU * aDisk.w * uT;
        float wobble = 0.035 * sin(3.0 * phi + uTheta + aRand.x * TAU) + 0.02 * sin(5.0 * phi - 2.0 * uTheta + aRand.y * TAU);
        float r = aDisk.x * (1.0 + 0.06 * wobble);
        vec3 local = vec3(cos(phi) * r, aDisk.z + 0.012 * aDisk.x * sin(2.0 * phi + uTheta + aRand.z * TAU), sin(phi) * r);
        vec3 diskPos = (uDisk * vec4(local, 1.0)).xyz;
        vec3 tangent = normalize((uDisk * vec4(-sin(phi), 0.0, cos(phi), 0.0)).xyz);

        float w = 0.0;
        float glow = 0.0;
        float typing = 0.0;
        vec3 targetLocal = aTarget;
        vec3 targetColor = uRim;
        if (aRole > 0.5) {
          float land;
          float frontX = aTarget.x;
          if (aRole > 3.5) {
            float idx = aRole - 4.0;
            float pop = pick(uDotPop, idx);
            vec3 centre = vec3(pick(uDotX, idx), uDotYZ.x, uDotYZ.y);
            targetLocal = centre + aTarget * max(pop, 0.0);
            land = clamp(pop * 1.6, 0.0, 1.0);
            frontX = centre.x;
            typing = pick(uDotGlow, idx);
            targetColor = mix(uLime, uRim, 0.08);
          } else {
            land = clamp((uScanX - (aTarget.x - LEAD)) / LEAD, 0.0, 1.0);
            land = 1.0 - pow(1.0 - land, 3.0);
            glow = exp(-pow((aTarget.x - uScanX) / 0.06, 2.0)) * uScanGlow;
          }
          float leave = clamp((uEraseX - frontX + aRand.w * 0.35) / 0.55, 0.0, 1.0);
          w = land * (1.0 - leave * leave * leave);
        }

        vec3 targetPos = (uBubble * vec4(targetLocal, 1.0)).xyz;
        vec3 swirl = normalize(vec3(aRand.x - 0.5, aRand.y - 0.5, aRand.z - 0.5) * 1.4 + tangent);
        vec3 pos = mix(diskPos, targetPos, w) + swirl * sin(3.14159265 * w) * 0.38 * (0.35 + aRand.w);

        // Relativistic-beaming read: the side of the disk turning toward the
        // camera is brighter, the receding left side falls away behind the copy.
        vec3 toCamera = normalize(cameraPosition - diskPos);
        float beaming = clamp(0.5 + 0.9 * dot(tangent, toCamera), 0.12, 1.4);
        float diskBright = aBright.x * beaming;
        float bright = mix(diskBright, aBright.y * (1.0 + 1.4 * uFlash), w);
        bright *= 1.0 + 3.5 * glow + 4.0 * typing * w;
        vec3 color = mix(aColor, targetColor, w);
        color = mix(color, uLime * 1.3, clamp(glow * 1.2 + typing * w * 0.8, 0.0, 1.0));

        vec4 mv = viewMatrix * vec4(pos, 1.0);
        vec4 clip = projectionMatrix * mv;
        float ndcX = clip.x / clip.w;
        bright *= mix(0.22, 1.0, smoothstep(-0.85, 0.05, ndcX));

        float depth = -mv.z;
        float coc = min(abs(1.0 / uFocus - 1.0 / depth) * uK, uMax);
        float size = max(2.0 * coc + uMin, uMin);
        gl_PointSize = size;
        vSize = size;
        vColor = color * bright * pow(uMin / size, uFalloff);
        gl_Position = clip;
      }`,
    fragmentShader: /* glsl */ `
      varying vec3 vColor;
      varying float vSize;
      void main() {
        vec2 p = gl_PointCoord * 2.0 - 1.0;
        float r = length(p);
        float aa = 2.5 / vSize;
        float disc = 1.0 - smoothstep(1.0 - aa, 1.0, r);
        if (disc <= 0.0) discard;
        float rim = mix(0.86, 1.14, smoothstep(0.45, 0.96, r));
        float point = 1.0 - smoothstep(0.0, 1.0, r);
        float shape = mix(point * 1.9, rim, smoothstep(5.0, 12.0, vSize));
        gl_FragColor = vec4(vColor * disc * shape, 1.0);
      }`,
  });

  const points = new THREE.Points(geometry, material);
  points.frustumCulled = false;
  points.renderOrder = 10;
  return {
    points,
    uniforms,
    dispose() {
      geometry.dispose();
      material.dispose();
    },
  };
}
