import * as THREE from 'three';

// Single-pass golden-angle depth of field (after Dennis Gustafsson's
// "Bokeh depth of field in a single pass"), applied to the background layer
// only. The glass subject is rendered afterwards, sharp, on top of this
// result, so there are no halos where a blurred background meets a sharp
// foreground edge. Samples behind the centre pixel are limited to twice its
// own blur, which keeps the background from bleeding over nearer silk.
export function createDofMaterial(width: number, height: number) {
  return new THREE.ShaderMaterial({
    depthTest: false,
    depthWrite: false,
    uniforms: {
      tColor: { value: null as THREE.Texture | null },
      tDepth: { value: null as THREE.Texture | null },
      uResolution: { value: new THREE.Vector2(width, height) },
      uNear: { value: 0.5 },
      uFar: { value: 80 },
      uFocus: { value: 10 },
      uK: { value: 420 },
      uMax: { value: 18 },
    },
    vertexShader: /* glsl */ `
      varying vec2 vUv;
      void main() {
        vUv = uv;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }`,
    fragmentShader: /* glsl */ `
      #include <packing>
      uniform sampler2D tColor;
      uniform sampler2D tDepth;
      uniform vec2 uResolution;
      uniform float uNear, uFar, uFocus, uK, uMax;
      varying vec2 vUv;

      float distanceAt(vec2 uv) {
        return -perspectiveDepthToViewZ(texture2D(tDepth, uv).x, uNear, uFar);
      }
      float coc(float depth) {
        return min(abs(1.0 / uFocus - 1.0 / depth) * uK, uMax);
      }

      void main() {
        vec2 pixel = 1.0 / uResolution;
        float centerDepth = distanceAt(vUv);
        float centerSize = coc(centerDepth);
        vec3 color = texture2D(tColor, vUv).rgb;
        float total = 1.0;
        float radius = 0.6;
        float angle = 0.0;
        for (int i = 0; i < 480; i++) {
          if (radius >= uMax) break;
          vec2 uv = vUv + vec2(cos(angle), sin(angle)) * pixel * radius;
          vec3 sampleColor = texture2D(tColor, uv).rgb;
          float sampleDepth = distanceAt(uv);
          float sampleSize = coc(sampleDepth);
          if (sampleDepth > centerDepth) sampleSize = clamp(sampleSize, 0.0, centerSize * 2.0);
          float m = smoothstep(radius - 0.5, radius + 0.5, sampleSize);
          color += mix(color / total, sampleColor, m);
          total += 1.0;
          angle += 2.39996323;
          radius += 0.6 / radius;
        }
        gl_FragColor = vec4(color / total, 1.0);
      }`,
  });
}
