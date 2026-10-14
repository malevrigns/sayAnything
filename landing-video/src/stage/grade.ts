import * as THREE from 'three';

// Final pass: lens character (slight radial chromatic aberration, vignette),
// AgX tone mapping with a gentle "punchy" look, split toning toward forest in
// the shadows and warm amber in the highlights, then film grain and an 8-bit
// dither so dark gradients survive H.264 without banding.
export const GradeShader = {
  name: 'SayAnythingGrade',
  uniforms: {
    tDiffuse: { value: null as THREE.Texture | null },
    uResolution: { value: new THREE.Vector2(1920, 1080) },
    uExposure: { value: 1.0 },
    uSeed: { value: 0 },
    uGrain: { value: 0.02 },
    uVignette: { value: 0.42 },
    uAberration: { value: 0.0016 },
    uPower: { value: 1.12 },
    uSaturation: { value: 1.1 },
    uShadowTint: { value: new THREE.Vector3(-0.004, 0.006, 0.003) },
    uHighlightTint: { value: new THREE.Vector3(0.016, 0.006, -0.01) },
    // 1 = keep true blacks clean: no grain or dither where the frame is black,
    // so a black page around the video matches and the encoder spends no bits there.
    uCleanBlacks: { value: 0 },
  },
  vertexShader: /* glsl */ `
    varying vec2 vUv;
    void main() {
      vUv = uv;
      gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
    }`,
  fragmentShader: /* glsl */ `
    uniform sampler2D tDiffuse;
    uniform vec2 uResolution;
    uniform float uExposure, uSeed, uGrain, uVignette, uAberration, uPower, uSaturation, uCleanBlacks;
    uniform vec3 uShadowTint, uHighlightTint;
    varying vec2 vUv;

    const mat3 SRGB_TO_REC2020 = mat3(vec3(0.6274, 0.0691, 0.0164), vec3(0.3293, 0.9195, 0.0880), vec3(0.0433, 0.0113, 0.8956));
    const mat3 REC2020_TO_SRGB = mat3(vec3(1.6605, -0.1246, -0.0182), vec3(-0.5876, 1.1329, -0.1006), vec3(-0.0728, -0.0083, 1.1187));
    const mat3 AGX_INSET = mat3(
      vec3(0.856627153315983, 0.137318972929847, 0.11189821299995),
      vec3(0.0951212405381588, 0.761241990602591, 0.0767994186031903),
      vec3(0.0482516061458583, 0.101439036467562, 0.811302368396859));
    const mat3 AGX_OUTSET = mat3(
      vec3(1.1271005818144368, -0.1413297634984383, -0.14132976349843826),
      vec3(-0.11060664309660323, 1.157823702216272, -0.11060664309660294),
      vec3(-0.016493938717834573, -0.016493938717834257, 1.2519364065950405));
    const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

    vec3 agxContrast(vec3 x) {
      vec3 x2 = x * x;
      vec3 x4 = x2 * x2;
      return 15.5 * x4 * x2 - 40.14 * x4 * x + 31.96 * x4 - 6.868 * x2 * x + 0.4298 * x2 + 0.1191 * x - 0.00232;
    }
    vec3 agx(vec3 color) {
      const float minEv = -12.47393;
      const float maxEv = 4.026069;
      color = AGX_INSET * (SRGB_TO_REC2020 * color);
      color = clamp((log2(max(color, 1e-10)) - minEv) / (maxEv - minEv), 0.0, 1.0);
      color = agxContrast(color);
      color = pow(max(color, 0.0), vec3(uPower));
      float luma = dot(color, LUMA);
      color = luma + uSaturation * (color - luma);
      color = AGX_OUTSET * color;
      color = pow(max(color, 0.0), vec3(2.2));
      return clamp(REC2020_TO_SRGB * color, 0.0, 1.0);
    }
    vec3 encodeSRGB(vec3 c) {
      return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
    }
    float hash12(vec2 p) {
      vec3 p3 = fract(vec3(p.xyx) * 0.1031);
      p3 += dot(p3, p3.yzx + 33.33);
      return fract((p3.x + p3.y) * p3.z);
    }

    void main() {
      vec2 c = vUv - 0.5;
      float aspect = uResolution.x / uResolution.y;
      vec2 ca = c * vec2(aspect, 1.0);
      float r2 = dot(ca, ca);
      vec2 shift = c * uAberration * r2 * 4.0;
      vec3 col = vec3(
        texture2D(tDiffuse, vUv + shift).r,
        texture2D(tDiffuse, vUv).g,
        texture2D(tDiffuse, vUv - shift).b);
      col *= uExposure;
      col *= 1.0 - uVignette * smoothstep(0.12, 1.1, r2 * 1.35);
      col = agx(col);
      float l = dot(col, LUMA);
      col = max(col + uShadowTint * (1.0 - l) * (1.0 - l) + uHighlightTint * l * l, 0.0);
      vec3 outColor = encodeSRGB(clamp(col, 0.0, 1.0));

      vec2 fc = gl_FragCoord.xy;
      float grain = hash12(fc + uSeed * vec2(17.13, 91.71)) + hash12(fc * 1.618 + uSeed * vec2(53.17, 11.93)) - 1.0;
      float lo = dot(outColor, LUMA);
      float blackGate = mix(1.0, smoothstep(0.006, 0.05, lo), uCleanBlacks);
      outColor += grain * uGrain * mix(0.45 + 2.2 * lo * (1.0 - lo), 2.4 * lo * (1.0 - lo), uCleanBlacks) * blackGate;
      float dither = hash12(fc + uSeed * vec2(3.71, 7.37)) - hash12(fc * 0.731 + uSeed * vec2(9.13, 1.97));
      outColor += dither / 255.0 * blackGate;
      gl_FragColor = vec4(outColor, 1.0);
    }`,
};
