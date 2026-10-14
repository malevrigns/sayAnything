import * as THREE from 'three';
import { HEX, linear } from './palette';

// Full-frame dusk gradient drawn first in the background layer: forest-black
// on the left where the hero copy sits, warming to espresso and umber on the
// right, with a breathing amber light behind the glass. Output is linear HDR.
export function createBackdrop(aspect: number) {
  const material = new THREE.ShaderMaterial({
    depthTest: false,
    depthWrite: false,
    uniforms: {
      uAspect: { value: aspect },
      uTheta: { value: 0 },
      cInk: { value: linear(HEX.ink) },
      cForest: { value: linear(HEX.forestDeep) },
      cEspresso: { value: linear(HEX.espresso) },
      cUmber: { value: linear(HEX.umber) },
      cAmber: { value: linear(HEX.amber) },
      cCore: { value: linear(HEX.apricot) },
      cLime: { value: linear(HEX.lime) },
      uGlow: { value: new THREE.Vector2(0.71, 0.6) },
    },
    vertexShader: /* glsl */ `
      varying vec2 vUv;
      void main() {
        vUv = uv;
        gl_Position = vec4(position.xy, 0.0, 1.0);
      }`,
    fragmentShader: /* glsl */ `
      uniform float uAspect, uTheta;
      uniform vec3 cInk, cForest, cEspresso, cUmber, cAmber, cCore, cLime;
      uniform vec2 uGlow;
      varying vec2 vUv;

      float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
      float noise(vec2 p) {
        vec2 i = floor(p), f = fract(p);
        vec2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
      }
      float fbm(vec2 p) { float a = 0.5, s = 0.0; for (int i = 0; i < 5; i++) { s += a * noise(p); p *= 2.03; a *= 0.5; } return s; }

      void main() {
        vec2 p = vec2((vUv.x - 0.5) * uAspect, vUv.y - 0.5);
        float warm = smoothstep(-0.95, 0.95, p.x * 0.85 + p.y * 0.25);
        vec3 col = mix(cInk, mix(cForest, cEspresso, 0.45), warm) * 0.85;
        col = mix(col, cUmber * 0.45, smoothstep(0.35, 1.3, p.x * 0.7 - p.y * 0.2) * 0.2);

        // Slow drifting texture: the sample point travels a circle, so it loops.
        vec2 drift = 0.35 * vec2(cos(uTheta), sin(uTheta));
        col *= 0.8 + 0.4 * fbm(p * 1.6 + drift + 3.7);

        vec2 g = vec2((uGlow.x - 0.5) * uAspect, uGlow.y - 0.5) + 0.03 * vec2(sin(uTheta), 0.6 * cos(uTheta));
        float d = length(p - g);
        float breath = 1.0 + 0.07 * sin(uTheta + 0.6);
        col += cAmber * exp(-d * d * 12.0) * 0.32 * breath;
        col += cCore * exp(-d * d * 60.0) * 0.55 * breath;
        vec2 q = p - vec2(0.75, -0.42);
        col += cLime * exp(-dot(q, q) * 9.0) * 0.035;
        gl_FragColor = vec4(col, 1.0);
      }`,
  });
  const geometry = new THREE.PlaneGeometry(2, 2);
  const mesh = new THREE.Mesh(geometry, material);
  mesh.frustumCulled = false;
  mesh.renderOrder = -1000;
  return {
    mesh,
    update(theta: number) {
      material.uniforms.uTheta.value = theta;
    },
    dispose() {
      geometry.dispose();
      material.dispose();
    },
  };
}
