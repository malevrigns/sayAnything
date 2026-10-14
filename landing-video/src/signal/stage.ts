import * as THREE from 'three';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { ShaderPass } from 'three/examples/jsm/postprocessing/ShaderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { GradeShader } from '../stage/grade';
import { TAU } from '../stage/loop';
import { createLightGrid, createVoid } from './field';
import { createHud } from './hud';
import { createSignalParticles } from './particles';
import { beatAt, H4 } from './timeline';

// Pixels of blur per unit of |1/focus - 1/depth|, shared by the disk and the
// light grid so the whole frame reads as one lens.
const COC_SCALE = 340;

// The subject sits right of centre; the left ~40% of the frame stays dark for
// the page copy that is laid over the video.
const BUBBLE_AT = new THREE.Vector3(1.8, 0.1, 0);
const LOOK_AT = new THREE.Vector3(0.6, 0.05, 0);

export interface SignalStage {
  render(frame: number, total: number): void;
  dispose(): void;
}

export function createSignalStage(canvas: HTMLCanvasElement, width: number, height: number): SignalStage {
  const renderer = new THREE.WebGLRenderer({
    canvas,
    antialias: false,
    alpha: false,
    depth: false,
    stencil: false,
    preserveDrawingBuffer: true,
    powerPreference: 'high-performance',
  });
  renderer.setPixelRatio(1);
  renderer.setSize(width, height, false);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.NoToneMapping;
  renderer.setClearColor(0x000000, 1);

  const camera = new THREE.PerspectiveCamera(25, width / height, 0.5, 80);
  const scene = new THREE.Scene();

  const ground = createVoid(width / height);
  const grid = createLightGrid({ z: -16, spacing: 0.95, cocScale: COC_SCALE, maxCoc: 22, centre: new THREE.Vector2(BUBBLE_AT.x + 1.2, BUBBLE_AT.y) });
  const particles = createSignalParticles({ seed: 20261014, diskCount: 68000, cocScale: COC_SCALE, maxCoc: 24 });
  const hud = createHud();
  const bubble = new THREE.Group();
  bubble.add(hud.group);
  scene.add(ground.mesh, grid.points, particles.points, bubble);

  // The disk is tilted toward the camera (we look down onto it) and rolled a
  // little so its ellipse cuts the frame on a diagonal.
  const diskMatrix = new THREE.Matrix4()
    .makeTranslation(BUBBLE_AT.x, BUBBLE_AT.y - 0.05, BUBBLE_AT.z)
    .multiply(new THREE.Matrix4().makeRotationZ(-0.16))
    .multiply(new THREE.Matrix4().makeRotationX(0.32));
  particles.uniforms.uDisk.value.copy(diskMatrix);

  const composer = new EffectComposer(renderer, new THREE.WebGLRenderTarget(width, height, { type: THREE.HalfFloatType, samples: 4 }));
  composer.setPixelRatio(1);
  composer.setSize(width, height);
  composer.addPass(new RenderPass(scene, camera));
  const bloom = new UnrealBloomPass(new THREE.Vector2(width, height), 0.6, 0.35, 0.32);
  composer.addPass(bloom);
  const grade = new ShaderPass(GradeShader);
  grade.uniforms.uResolution.value.set(width, height);
  grade.uniforms.uGrain.value = 0.008;
  grade.uniforms.uCleanBlacks.value = 1;
  grade.uniforms.uVignette.value = 0.5;
  grade.uniforms.uAberration.value = 0.0008;
  grade.uniforms.uPower.value = 1.08;
  // The frame is achromatic apart from the lime accent; extra saturation only
  // lands on the lime, which AgX would otherwise pull toward olive.
  grade.uniforms.uSaturation.value = 1.32;
  grade.uniforms.uShadowTint.value.set(0, 0, 0);
  grade.uniforms.uHighlightTint.value.set(0, 0, 0);
  composer.addPass(grade);

  const bubbleWorld = new THREE.Vector3();

  return {
    render(frame: number, total: number) {
      const t = frame / total;
      const theta = t * TAU;
      const beat = beatAt(frame);

      // A slow camera float: one closed orbit per loop.
      const azimuth = -0.12 + 0.05 * Math.sin(theta);
      const elevation = 0.085 + 0.025 * Math.sin(theta + 1.2);
      const distance = 10.6 - 0.18 * (0.5 - 0.5 * Math.cos(theta));
      camera.position.set(
        LOOK_AT.x + distance * Math.sin(azimuth) * Math.cos(elevation),
        LOOK_AT.y + distance * Math.sin(elevation),
        LOOK_AT.z + distance * Math.cos(azimuth) * Math.cos(elevation),
      );
      camera.up.set(0.004 * Math.sin(2 * theta), 1, 0).normalize();
      camera.lookAt(LOOK_AT);
      camera.updateMatrixWorld();

      // The bubble faces the camera with a gentle drift; it never spins.
      bubble.position.set(BUBBLE_AT.x, BUBBLE_AT.y + 0.035 * Math.sin(theta + 0.5), BUBBLE_AT.z);
      bubble.rotation.set(0.05 + 0.02 * Math.sin(theta + 1.0), -0.26 + 0.045 * Math.sin(theta), 0.025 * Math.sin(theta + 2.0));
      bubble.updateMatrixWorld(true);
      bubbleWorld.setFromMatrixPosition(bubble.matrixWorld).applyMatrix4(camera.matrixWorldInverse);
      const focus = -bubbleWorld.z;

      const u = particles.uniforms;
      u.uT.value = t;
      u.uTheta.value = theta;
      u.uBubble.value.copy(bubble.matrixWorld);
      u.uScanX.value = beat.scanX;
      u.uEraseX.value = beat.eraseX;
      u.uScanGlow.value = beat.scanGlow;
      u.uDotPop.value.set(...beat.dotPop);
      u.uDotGlow.value.set(...beat.dotGlow);
      u.uFlash.value = beat.flash;
      u.uFocus.value = focus;

      hud.update(beat);
      grid.update(focus, beat.ripple);
      ground.update(frame >= H4 ? Math.max(0, 1 - beat.ripple / 3.5) : 0);

      grade.uniforms.uSeed.value = frame;
      grade.uniforms.uExposure.value = 1 + 0.08 * beat.flash;
      renderer.setRenderTarget(null);
      composer.render();
    },
    dispose() {
      ground.dispose();
      grid.dispose();
      particles.dispose();
      hud.dispose();
      bloom.dispose();
      composer.dispose();
      renderer.dispose();
    },
  };
}
