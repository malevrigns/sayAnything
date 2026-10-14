import * as THREE from 'three';
import { TAU } from '../stage/loop';
import { HEX, linear } from '../stage/palette';
import { FRONT_Z, bubbleOutlinePoints } from './particles';

// Garnish around the one engine: a thin HUD reticle that searches while the
// disk orbits and locks when the bubble resolves, the bubble's own outline
// written behind the beam, the beam itself, and a drifting crosshair.

const lineMaterial = (color: THREE.Color) =>
  new THREE.ShaderMaterial({
    transparent: true,
    depthTest: false,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
    uniforms: {
      uColor: { value: color },
      uAlpha: { value: 1 },
      uReveal: { value: 1 },
      uScanX: { value: 9 },
      uEraseX: { value: -9 },
    },
    vertexShader: /* glsl */ `
      attribute float aS;
      varying float vS;
      varying float vX;
      void main() {
        vS = aS;
        vX = position.x;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }`,
    fragmentShader: /* glsl */ `
      uniform vec3 uColor;
      uniform float uAlpha, uReveal, uScanX, uEraseX;
      varying float vS;
      varying float vX;
      void main() {
        if (vS > uReveal || vX > uScanX || vX < uEraseX) discard;
        gl_FragColor = vec4(uColor * uAlpha, 1.0);
      }`,
  });

function segments(pairs: number[], s: number[]) {
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(pairs), 3));
  geometry.setAttribute('aS', new THREE.BufferAttribute(new Float32Array(s), 1));
  return geometry;
}

function arc(out: number[], s: number[], radius: number, a0: number, a1: number, steps: number, z = 0) {
  for (let k = 0; k < steps; k++) {
    const t0 = k / steps;
    const t1 = (k + 1) / steps;
    const b0 = a0 + (a1 - a0) * t0;
    const b1 = a0 + (a1 - a0) * t1;
    out.push(radius * Math.cos(b0), radius * Math.sin(b0), z, radius * Math.cos(b1), radius * Math.sin(b1), z);
    s.push(t0, t1);
  }
}

const DEG = Math.PI / 180;

export function createHud() {
  const group = new THREE.Group();
  const disposables: Array<{ dispose(): void }> = [];
  const add = (geometry: THREE.BufferGeometry, material: THREE.ShaderMaterial, parent: THREE.Object3D) => {
    const lines = new THREE.LineSegments(geometry, material);
    lines.frustumCulled = false;
    lines.renderOrder = 20;
    parent.add(lines);
    disposables.push(geometry, material);
    return lines;
  };
  const white = linear(HEX.silver);
  const lime = linear(HEX.electric);

  // Ring A · ticks (pattern period 30°): hairline circle + 5° ticks, majors every 30°.
  const ringA = new THREE.Group();
  {
    const pos: number[] = [];
    const s: number[] = [];
    arc(pos, s, 1.62, 0, TAU, 360);
    for (let k = 0; k < 72; k++) {
      const a = k * 5 * DEG;
      const len = k % 6 === 0 ? 0.075 : 0.028;
      pos.push(1.62 * Math.cos(a), 1.62 * Math.sin(a), 0, (1.62 - len) * Math.cos(a), (1.62 - len) * Math.sin(a), 0);
      s.push(0, 0);
    }
    const material = lineMaterial(white.clone().multiplyScalar(0.3));
    add(segments(pos, s), material, ringA);
  }
  // Ring B · lime arcs (pattern period 120°), stroke-written on lock.
  const ringB = new THREE.Group();
  const arcMaterial = lineMaterial(lime.clone().multiplyScalar(0.55));
  {
    const pos: number[] = [];
    const s: number[] = [];
    for (let g = 0; g < 3; g++) {
      const base = g * 120 * DEG + 18 * DEG;
      arc(pos, s, 1.9, base, base + 34 * DEG, 68);
      arc(pos, s, 1.9, base + 38 * DEG, base + 44 * DEG, 12);
    }
    add(segments(pos, s), arcMaterial, ringB);
  }
  // Ring C · dashes (pattern period 6°).
  const ringC = new THREE.Group();
  {
    const pos: number[] = [];
    const s: number[] = [];
    for (let k = 0; k < 60; k++) arc(pos, s, 1.36, k * 6 * DEG, (k * 6 + 2.4) * DEG, 3);
    for (let i = 0; i < s.length; i++) s[i] = 0;
    add(segments(pos, s), lineMaterial(white.clone().multiplyScalar(0.18)), ringC);
  }
  const reticle = new THREE.Group();
  reticle.position.set(0, -0.06, -0.04);
  reticle.add(ringA, ringB, ringC);
  group.add(reticle);
  const ringMaterials = [ringA, ringB, ringC].map((g) => (g.children[0] as THREE.LineSegments).material as THREE.ShaderMaterial);

  // The bubble outline, front and back, written behind the beam.
  const outline = bubbleOutlinePoints();
  const outlineMaterials: THREE.ShaderMaterial[] = [];
  for (const [z, strength] of [
    [FRONT_Z + 0.002, 0.55],
    [-FRONT_Z, 0.22],
  ]) {
    const pos: number[] = [];
    const s: number[] = [];
    for (let i = 0; i < outline.length; i++) {
      const a = outline[i];
      const b = outline[(i + 1) % outline.length];
      pos.push(a.x, a.y, z, b.x, b.y, z);
      s.push(0, 0);
    }
    const material = lineMaterial(linear('#f4f8ff').multiplyScalar(strength));
    outlineMaterials.push(material);
    add(segments(pos, s), material, group);
  }

  // Crosshair: a registration mark with four corner brackets.
  const cross = new THREE.Group();
  const crossMaterial = lineMaterial(white.clone().multiplyScalar(0.8));
  {
    const pos: number[] = [];
    const s: number[] = [];
    const g = 0.025;
    const l = 0.08;
    pos.push(-l, 0, 0, -g, 0, 0, g, 0, 0, l, 0, 0, 0, -l, 0, 0, -g, 0, 0, g, 0, 0, l, 0);
    const c = 0.16;
    const k = 0.05;
    for (const [sx, sy] of [
      [1, 1],
      [-1, 1],
      [-1, -1],
      [1, -1],
    ]) {
      pos.push(sx * c, sy * c, 0, sx * (c - k), sy * c, 0, sx * c, sy * c, 0, sx * c, sy * (c - k), 0);
    }
    for (let i = 0; i < pos.length / 3; i++) s.push(0);
    add(segments(pos, s), crossMaterial, cross);
  }
  cross.position.z = FRONT_Z + 0.04;
  group.add(cross);

  // The beam: a thin lime sheet standing just in front of the bubble face.
  const beamGeometry = new THREE.PlaneGeometry(0.5, 2.5);
  const beamMaterial = new THREE.ShaderMaterial({
    transparent: true,
    depthTest: false,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
    uniforms: { uColor: { value: lime }, uGlow: { value: 0 } },
    vertexShader: /* glsl */ `
      varying vec2 vUv;
      void main() {
        vUv = uv;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }`,
    fragmentShader: /* glsl */ `
      uniform vec3 uColor;
      uniform float uGlow;
      varying vec2 vUv;
      void main() {
        float x = (vUv.x - 0.5) * 0.5;
        float core = exp(-pow(x / 0.0035, 2.0));
        float halo = exp(-pow(x / 0.05, 2.0)) * 0.22 + exp(-pow(x / 0.16, 2.0)) * 0.05;
        float v = smoothstep(0.0, 0.18, vUv.y) * smoothstep(1.0, 0.82, vUv.y);
        gl_FragColor = vec4(uColor * (core * 2.4 + halo) * v * uGlow, 1.0);
      }`,
  });
  disposables.push(beamGeometry, beamMaterial);
  const beam = new THREE.Mesh(beamGeometry, beamMaterial);
  beam.position.set(0, -0.12, FRONT_Z + 0.015);
  beam.frustumCulled = false;
  beam.renderOrder = 30;
  group.add(beam);

  return {
    group,
    update(state: {
      spin: number;
      arcs: number;
      ringAlpha: number;
      outlineAlpha: number;
      scanX: number;
      eraseX: number;
      scanGlow: number;
      crosshair: { alpha: number; x: number; y: number };
    }) {
      // Each ring turns by a whole multiple of its own pattern period per
      // cycle, so the locked pose at the end equals the locked pose at frame 0.
      ringA.rotation.z = -state.spin * (120 * DEG);
      ringB.rotation.z = state.spin * (240 * DEG);
      ringC.rotation.z = state.spin * (360 * DEG);
      ringMaterials.forEach((m) => (m.uniforms.uAlpha.value = state.ringAlpha));
      arcMaterial.uniforms.uReveal.value = state.arcs;
      outlineMaterials.forEach((m) => {
        m.uniforms.uAlpha.value = state.outlineAlpha;
        m.uniforms.uScanX.value = state.scanX;
        m.uniforms.uEraseX.value = state.eraseX;
      });
      crossMaterial.uniforms.uAlpha.value = state.crosshair.alpha;
      cross.position.x = state.crosshair.x;
      cross.position.y = state.crosshair.y;
      cross.visible = state.crosshair.alpha > 0.001;
      beam.position.x = state.scanX;
      beamMaterial.uniforms.uGlow.value = state.scanGlow;
      beam.visible = state.scanGlow > 0.001;
    },
    dispose() {
      disposables.forEach((d) => d.dispose());
    },
  };
}
