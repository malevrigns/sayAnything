import * as THREE from 'three';
import { TAU, lerp, mulberry32 } from './loop';
import { linear } from './palette';

export interface MoteOptions {
  count: number;
  seed: number;
  min: [number, number, number];
  max: [number, number, number];
  brightness: [number, number];
  color: string;
  cocScale: number; // pixels of blur per unit of |1/focus - 1/depth|, shared with the DOF pass
  maxCoc: number;
  minSize: number;
  falloff: number;
}

// Dust in the light. Each mote is drawn as a lens-shaped disc whose size is
// its circle of confusion, so motes near the glass sparkle and motes far from
// it open up into soft bokeh. Every path is a closed Lissajous loop.
export function createMotes(o: MoteOptions) {
  const rand = mulberry32(o.seed);
  const motes = Array.from({ length: o.count }, () => ({
    x: lerp(o.min[0], o.max[0], rand()),
    y: lerp(o.min[1], o.max[1], rand()),
    z: lerp(o.min[2], o.max[2], rand()),
    ax: 0.06 + rand() * 0.22,
    ay: 0.08 + rand() * 0.26,
    az: 0.05 + rand() * 0.15,
    p1: rand() * TAU,
    p2: rand() * TAU,
    p3: rand() * TAU,
    p4: rand() * TAU,
    p5: rand() * TAU,
    k: 1 + Math.floor(rand() * 3),
    b: lerp(o.brightness[0], o.brightness[1], rand()),
  }));
  const positions = new Float32Array(o.count * 3);
  const bright = new Float32Array(o.count);
  const geometry = new THREE.BufferGeometry();
  const position = new THREE.BufferAttribute(positions, 3).setUsage(THREE.DynamicDrawUsage);
  const brightness = new THREE.BufferAttribute(bright, 1).setUsage(THREE.DynamicDrawUsage);
  geometry.setAttribute('position', position);
  geometry.setAttribute('aBright', brightness);

  const material = new THREE.ShaderMaterial({
    transparent: true,
    depthWrite: false,
    depthTest: true,
    blending: THREE.AdditiveBlending,
    uniforms: {
      uFocus: { value: 10 },
      uK: { value: o.cocScale },
      uMax: { value: o.maxCoc },
      uMin: { value: o.minSize },
      uFalloff: { value: o.falloff },
      uColor: { value: linear(o.color) },
    },
    vertexShader: /* glsl */ `
      uniform float uFocus, uK, uMax, uMin, uFalloff;
      attribute float aBright;
      varying float vIntensity;
      varying float vSize;
      void main() {
        vec4 mv = modelViewMatrix * vec4(position, 1.0);
        float depth = -mv.z;
        float coc = min(abs(1.0 / uFocus - 1.0 / depth) * uK, uMax);
        float size = max(2.0 * coc + uMin, uMin);
        gl_PointSize = size;
        vSize = size;
        vIntensity = aBright * pow(uMin / size, uFalloff);
        gl_Position = projectionMatrix * mv;
      }`,
    fragmentShader: /* glsl */ `
      uniform vec3 uColor;
      varying float vIntensity;
      varying float vSize;
      void main() {
        vec2 p = gl_PointCoord * 2.0 - 1.0;
        float r = length(p);
        float aa = 3.0 / vSize;
        float disc = 1.0 - smoothstep(1.0 - aa, 1.0, r);
        if (disc <= 0.0) discard;
        // Large discs get the faint bright rim of real bokeh; tiny ones stay soft points.
        float rim = mix(0.84, 1.16, smoothstep(0.45, 0.96, r));
        float point = 1.0 - smoothstep(0.0, 1.0, r);
        float shape = mix(point * 1.8, rim, smoothstep(5.0, 12.0, vSize));
        gl_FragColor = vec4(uColor * vIntensity * disc * shape, 1.0);
      }`,
  });
  const points = new THREE.Points(geometry, material);
  points.frustumCulled = false;
  points.renderOrder = 10;

  return {
    points,
    update(theta: number, focus: number) {
      material.uniforms.uFocus.value = focus;
      motes.forEach((m, i) => {
        positions[i * 3] = m.x + m.ax * Math.sin(theta + m.p1);
        positions[i * 3 + 1] = m.y + m.ay * Math.sin(theta + m.p2) + 0.12 * Math.sin(2 * theta + m.p3);
        positions[i * 3 + 2] = m.z + m.az * Math.sin(theta + m.p4);
        bright[i] = m.b * (0.7 + 0.3 * Math.sin(m.k * theta + m.p5));
      });
      position.needsUpdate = true;
      brightness.needsUpdate = true;
    },
    dispose() {
      geometry.dispose();
      material.dispose();
    },
  };
}
