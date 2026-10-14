import * as THREE from 'three';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { FullScreenQuad } from 'three/examples/jsm/postprocessing/Pass.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { ShaderPass } from 'three/examples/jsm/postprocessing/ShaderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { createBackdrop } from './backdrop';
import { createDofMaterial } from './dof';
import { buildEnvironment } from './environment';
import { type BubbleSpec, createBubble, createTypingDots } from './glass';
import { GradeShader } from './grade';
import { TAU } from './loop';
import { createMotes } from './motes';
import { HEX, linear } from './palette';
import { type RibbonSpec, createRibbon } from './silk';

// Blur, in pixels, per unit of |1/focus - 1/depth|. Shared by the background
// depth of field and the bokeh motes so both read as one lens.
const COC_SCALE = 340;
const MAX_BACKGROUND_COC = 18;

const FRONT_BUBBLE: BubbleSpec = {
  outline: { halfWidth: 1.0, halfHeight: 0.72, corner: 0.4, tailBase: [-0.6, -0.16], tailTip: [-0.95, -1.22], mirror: false },
  slab: { halfThickness: 0.26, edgeRadius: 0.15, dome: 0.045, capRings: 18, arcSteps: 12 },
  position: [1.2, -0.12, 0],
  rotation: [0.06, -0.3, 0.035],
  bob: 0.055,
  swing: 0.09,
  phase: 0,
  material: {
    color: linear('#ffffff'),
    metalness: 0,
    roughness: 0.2,
    transmission: 1,
    thickness: 1.1,
    ior: 1.5,
    dispersion: 0.3,
    attenuationColor: linear('#ffeedd'),
    attenuationDistance: 2.8,
    clearcoat: 1,
    clearcoatRoughness: 0.03,
    iridescence: 0.22,
    iridescenceIOR: 1.3,
    iridescenceThicknessRange: [140, 420],
    specularIntensity: 1,
    envMapIntensity: 1.6,
  },
};

const BACK_BUBBLE: BubbleSpec = {
  outline: { halfWidth: 0.82, halfHeight: 0.6, corner: 0.34, tailBase: [-0.48, -0.12], tailTip: [-0.8, -1.02], mirror: true },
  slab: { halfThickness: 0.22, edgeRadius: 0.13, dome: 0.04, capRings: 16, arcSteps: 10 },
  position: [2.3, 0.78, -1.4],
  rotation: [0.05, -0.2, -0.07],
  bob: 0.07,
  swing: 0.11,
  phase: 2.0,
  material: {
    color: linear('#ffffff'),
    metalness: 0,
    roughness: 0.32,
    transmission: 1,
    thickness: 0.8,
    ior: 1.48,
    dispersion: 0.2,
    attenuationColor: linear('#e9f1cd'),
    attenuationDistance: 1.6,
    clearcoat: 1,
    clearcoatRoughness: 0.05,
    iridescence: 0.12,
    iridescenceIOR: 1.3,
    iridescenceThicknessRange: [140, 420],
    specularIntensity: 1,
    envMapIntensity: 1.1,
  },
};

const IVORY_SATIN: RibbonSpec = {
  points: [
    [-9.5, -4.6, -5.0],
    [-5.6, -3.4, -3.2],
    [-2.4, -1.9, -2.0],
    [0.3, -0.85, -2.0],
    [2.6, 0.35, -3.0],
    [4.8, 1.6, -3.6],
    [7.2, 2.6, -3.0],
    [10.5, 3.4, -4.5],
  ],
  halfWidth: 0.3,
  widthSwell: 0.22,
  color: '#b3aa9c',
  sheenColor: '#fff1dc',
  roughness: 0.26,
  sheenRoughness: 0.28,
  twistBase: 0.5,
  twistA: 0.9,
  twistFreqA: 1.1,
  twistB: 0.28,
  twistFreqB: 1.7,
  rippleA: 0.11,
  rippleFreqA: 3.0,
  rippleB: 0.045,
  rippleFreqB: 7.0,
  curl: 0.16,
  sway: 0.14,
  phase: 0,
};

const FOREST_VELVET: RibbonSpec = {
  points: [
    [-9, -2.6, -9.5],
    [-4.5, -3.4, -8.4],
    [0, -3.0, -7.6],
    [3.5, -2.0, -7.2],
    [6.5, -0.4, -7.8],
    [10.5, 0.9, -9.0],
  ],
  halfWidth: 0.42,
  widthSwell: 0.3,
  color: '#10231b',
  sheenColor: '#9fb06a',
  roughness: 0.62,
  sheenRoughness: 0.45,
  twistBase: -0.3,
  twistA: 0.6,
  twistFreqA: 0.6,
  twistB: 0.5,
  twistFreqB: 1.3,
  rippleA: 0.1,
  rippleFreqA: 1.8,
  rippleB: 0.04,
  rippleFreqB: 4.2,
  curl: 0.14,
  sway: 0.2,
  phase: 1.9,
};

export interface Stage {
  render(frame: number, total: number): void;
  dispose(): void;
}

export function createStage(canvas: HTMLCanvasElement, width: number, height: number): Stage {
  const renderer = new THREE.WebGLRenderer({
    canvas,
    antialias: false,
    alpha: false,
    depth: true,
    stencil: false,
    preserveDrawingBuffer: true,
    powerPreference: 'high-performance',
  });
  renderer.setPixelRatio(1);
  renderer.setSize(width, height, false);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.NoToneMapping;
  renderer.setClearColor(0x000000, 1);

  const environment = buildEnvironment(renderer);
  const camera = new THREE.PerspectiveCamera(25, width / height, 0.5, 80);
  const look = new THREE.Vector3(0, 0.05, 0);
  const lights = () => {
    const key = new THREE.DirectionalLight(linear(HEX.apricot), 2.6);
    key.position.set(6, 5, 7);
    const rim = new THREE.DirectionalLight(linear(HEX.paper), 1.2);
    rim.position.set(-7, 3, -5);
    return [key, rim];
  };

  // Background layer: dusk backdrop, silk, the second bubble. Blurred by depth.
  const background = new THREE.Scene();
  background.environment = environment;
  const backdrop = createBackdrop(width / height);
  const ribbons = [createRibbon(IVORY_SATIN), createRibbon(FOREST_VELVET)];
  const backBubble = createBubble(BACK_BUBBLE);
  background.add(backdrop.mesh, ...lights(), ...ribbons.map((r) => r.mesh), backBubble.group);

  // Subject layer: the front bubble stays in focus and refracts the blurred
  // background, which three.js includes in its transmission pass.
  const subject = new THREE.Scene();
  subject.environment = environment;
  const frontBubble = createBubble(FRONT_BUBBLE);
  const dots = createTypingDots(frontBubble.group, 5);
  const dust = createMotes({
    count: 18,
    seed: 7,
    min: [-0.6, -2.0, -1.1],
    max: [5.4, 2.6, -0.35],
    brightness: [0.9, 2.0],
    color: HEX.apricot,
    cocScale: COC_SCALE,
    maxCoc: MAX_BACKGROUND_COC,
    minSize: 3,
    falloff: 1.25,
  });
  const bokeh = createMotes({
    count: 6,
    seed: 23,
    min: [0.6, -1.8, 2.6],
    max: [5.5, 2.4, 5.8],
    brightness: [6, 10],
    color: HEX.apricot,
    cocScale: COC_SCALE,
    maxCoc: 40,
    minSize: 3,
    falloff: 1.35,
  });
  subject.add(...lights(), frontBubble.group, dust.points, bokeh.points);

  const backgroundTarget = new THREE.WebGLRenderTarget(width, height, {
    type: THREE.HalfFloatType,
    depthTexture: new THREE.DepthTexture(width, height),
  });
  const blurredTarget = new THREE.WebGLRenderTarget(width, height, { type: THREE.HalfFloatType, depthBuffer: false });
  subject.background = blurredTarget.texture;
  const dof = createDofMaterial(width, height);
  dof.uniforms.uK.value = COC_SCALE;
  dof.uniforms.uMax.value = MAX_BACKGROUND_COC;
  dof.uniforms.uNear.value = camera.near;
  dof.uniforms.uFar.value = camera.far;
  const dofQuad = new FullScreenQuad(dof);

  const composer = new EffectComposer(
    renderer,
    new THREE.WebGLRenderTarget(width, height, { type: THREE.HalfFloatType, samples: 4 }),
  );
  composer.setPixelRatio(1);
  composer.setSize(width, height);
  composer.addPass(new RenderPass(subject, camera));
  const bloom = new UnrealBloomPass(new THREE.Vector2(width, height), 0.38, 0.55, 0.92);
  composer.addPass(bloom);
  const grade = new ShaderPass(GradeShader);
  grade.uniforms.uResolution.value.set(width, height);
  composer.addPass(grade);

  const focusPoint = new THREE.Vector3();

  return {
    render(frame: number, total: number) {
      const theta = (frame / total) * TAU;

      const azimuth = -0.2 + 0.075 * Math.sin(theta);
      const elevation = 0.06 + 0.03 * Math.sin(theta + 1.3);
      const distance = 10.6 - 0.22 * (0.5 - 0.5 * Math.cos(theta));
      camera.position.set(
        look.x + distance * Math.sin(azimuth) * Math.cos(elevation),
        look.y + distance * Math.sin(elevation),
        look.z + distance * Math.cos(azimuth) * Math.cos(elevation),
      );
      camera.up.set(0.006 * Math.sin(2 * theta), 1, 0).normalize();
      camera.lookAt(look);
      camera.updateMatrixWorld();

      const environmentYaw = 0.5 * Math.sin(theta + 0.4);
      background.environmentRotation.set(0, environmentYaw, 0);
      subject.environmentRotation.set(0, environmentYaw, 0);

      backdrop.update(theta);
      ribbons.forEach((ribbon) => ribbon.update(theta));
      backBubble.update(theta);
      frontBubble.update(theta);
      dots.update(frame, total);
      frontBubble.group.updateMatrixWorld(true);
      focusPoint.setFromMatrixPosition(frontBubble.group.matrixWorld).applyMatrix4(camera.matrixWorldInverse);
      const focus = -focusPoint.z;
      dust.update(theta, focus);
      bokeh.update(theta, focus);

      renderer.setRenderTarget(backgroundTarget);
      renderer.clear();
      renderer.render(background, camera);

      dof.uniforms.tColor.value = backgroundTarget.texture;
      dof.uniforms.tDepth.value = backgroundTarget.depthTexture;
      dof.uniforms.uFocus.value = focus;
      renderer.setRenderTarget(blurredTarget);
      dofQuad.render(renderer);

      renderer.setRenderTarget(null);
      grade.uniforms.uSeed.value = frame;
      composer.render();
    },
    dispose() {
      backdrop.dispose();
      ribbons.forEach((ribbon) => ribbon.dispose());
      backBubble.dispose();
      frontBubble.dispose();
      dots.dispose();
      dust.dispose();
      bokeh.dispose();
      backgroundTarget.depthTexture?.dispose();
      backgroundTarget.dispose();
      blurredTarget.dispose();
      dof.dispose();
      dofQuad.dispose();
      bloom.dispose();
      composer.dispose();
      environment.dispose();
      renderer.dispose();
    },
  };
}
