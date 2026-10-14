import * as THREE from 'three';
import { HEX, linear } from '../stage/palette';

// The ground behind the engine: a near-black void with a faint cool lift
// behind the subject, and far behind it a precise grid of lights so deep in
// the background that the lens turns each one into a soft disc. The grid only
// moves once per loop: a single signal ripple travels outward when the bubble
// locks.

export function createVoid(aspect: number) {
  const material = new THREE.ShaderMaterial({
    depthTest: false,
    depthWrite: false,
    uniforms: {
      uAspect: { value: aspect },
      uCentre: { value: new THREE.Vector2(0.64, 0.52) },
      cVoid: { value: linear(HEX.void) },
      cLift: { value: linear('#0b1210') },
      cLime: { value: linear(HEX.electric) },
      uLock: { value: 0 },
    },
    vertexShader: /* glsl */ `
      varying vec2 vUv;
      void main() {
        vUv = uv;
        gl_Position = vec4(position.xy, 0.0, 1.0);
      }`,
    fragmentShader: /* glsl */ `
      uniform float uAspect, uLock;
      uniform vec2 uCentre;
      uniform vec3 cVoid, cLift, cLime;
      varying vec2 vUv;
      void main() {
        vec2 p = (vUv - uCentre) * vec2(uAspect, 1.0);
        float d2 = dot(p, p);
        vec3 col = cVoid + cLift * exp(-d2 * 2.2) * 0.9;
        col += cLime * exp(-d2 * 9.0) * (0.006 + 0.012 * uLock);
        gl_FragColor = vec4(col, 1.0);
      }`,
  });
  const geometry = new THREE.PlaneGeometry(2, 2);
  const mesh = new THREE.Mesh(geometry, material);
  mesh.frustumCulled = false;
  mesh.renderOrder = -1000;
  return {
    mesh,
    update(lock: number) {
      material.uniforms.uLock.value = lock;
    },
    dispose() {
      geometry.dispose();
      material.dispose();
    },
  };
}

export function createLightGrid(options: { z: number; spacing: number; cocScale: number; maxCoc: number; centre: THREE.Vector2 }) {
  const positions: number[] = [];
  for (let x = -13; x <= 19; x += options.spacing) {
    for (let y = -9; y <= 9.5; y += options.spacing) positions.push(x, y, options.z);
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(positions), 3));
  const material = new THREE.ShaderMaterial({
    transparent: true,
    depthTest: false,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
    uniforms: {
      uFocus: { value: 10 },
      uK: { value: options.cocScale },
      uMax: { value: options.maxCoc },
      uMin: { value: 2.0 },
      uCentre: { value: options.centre },
      uRipple: { value: -1 },
      cBase: { value: linear('#c9d3e3') },
      cWave: { value: linear(HEX.electric) },
    },
    vertexShader: /* glsl */ `
      uniform float uFocus, uK, uMax, uMin, uRipple;
      uniform vec2 uCentre;
      uniform vec3 cBase, cWave;
      varying vec3 vColor;
      varying float vSize;
      void main() {
        vec4 mv = modelViewMatrix * vec4(position, 1.0);
        vec4 clip = projectionMatrix * mv;
        float depth = -mv.z;
        float coc = min(abs(1.0 / uFocus - 1.0 / depth) * uK, uMax);
        float size = max(2.0 * coc + uMin, uMin);
        gl_PointSize = size;
        vSize = size;

        float d = length(position.xy - uCentre);
        float presence = exp(-d * d / 60.0);
        // Keep the copy side quiet: both the resting grid and the ripple fade
        // out toward the left of the frame.
        float ndcX = clip.x / clip.w;
        float copySide = mix(0.06, 1.0, smoothstep(-0.85, 0.2, ndcX));

        float wave = 0.0;
        if (uRipple >= 0.0) {
          float t = uRipple / 3.2;
          float radius = 16.0 * (1.0 - pow(1.0 - clamp(t, 0.0, 1.0), 3.0));
          wave = exp(-pow((d - radius) / 1.4, 2.0)) * (1.0 - smoothstep(0.55, 1.0, t));
        }
        vec3 col = (cBase * 0.05 * presence + cWave * wave * 0.55 * (0.35 + presence)) * copySide;
        vColor = col * pow(uMin / size, 1.2);
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
        float rim = mix(0.82, 1.18, smoothstep(0.5, 0.96, r));
        gl_FragColor = vec4(vColor * disc * rim, 1.0);
      }`,
  });
  const points = new THREE.Points(geometry, material);
  points.frustumCulled = false;
  points.renderOrder = 0;
  return {
    points,
    update(focus: number, ripple: number) {
      material.uniforms.uFocus.value = focus;
      material.uniforms.uRipple.value = ripple;
    },
    dispose() {
      geometry.dispose();
      material.dispose();
    },
  };
}
