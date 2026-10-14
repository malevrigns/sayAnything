import React, { useEffect, useLayoutEffect, useMemo, useRef } from 'react';
import { AbsoluteFill, random, useCurrentFrame, useVideoConfig } from 'remotion';
import { ThreeCanvas } from '@remotion/three';
import { useThree } from '@react-three/fiber';
import * as THREE from 'three';

/**
 * HeroLoop — a quiet campus evening, rendered abstractly.
 *
 * Warm cream → pale clay backdrop, ~30 soft translucent rounded shapes
 * (tiles, pills, speech-bubble silhouettes) drifting slowly, depth fog toward
 * cream, a few dozen tiny light motes rising, and a slow camera dolly + sway.
 *
 * Everything derives from the current frame; every motion has a period equal
 * to durationInFrames (or an integer division of it), so frame N wraps to
 * frame 0 without a visible seam. No wall-clock, no Math.random().
 */

// —— Palette: mirrors the CSS custom properties in server/web/styles.css ——
const PALETTE = {
  cream: '#faf6ee',
  paper: '#f3eee4',
  paper2: '#ebe4d6',
  line: '#d8d0c0',
  lineStrong: '#c4bbab',
  clay: '#c45c2a',
  clayHot: '#d46834',
  forest: '#1a332a',
  forestMid: '#254437',
  lime: '#dce8a8',
} as const;

const TAU = Math.PI * 2;
const CAMERA_Z = 20;
const FOV_DEG = 38;
const SHAPE_COUNT = 30;
const MOTE_COUNT = 64;

const CAMERA = {
  fov: FOV_DEG,
  near: 0.1,
  far: 120,
  position: [0, 0, CAMERA_Z] as [number, number, number],
};

const halfHeightAt = (z: number) => (CAMERA_Z - z) * Math.tan((FOV_DEG / 2) * (Math.PI / 180));

type Tint = { color: string; opacity: number; weight: number };

// Soft tints: mostly lime / sand / paper, with a few clay and forest accents
// so the clip reads warm and light rather than busy.
const TINTS: Tint[] = [
  { color: PALETTE.lime, opacity: 0.86, weight: 3 },
  { color: PALETTE.lineStrong, opacity: 0.72, weight: 3 },
  { color: PALETTE.paper2, opacity: 0.92, weight: 2 },
  { color: PALETTE.clay, opacity: 0.42, weight: 2 },
  { color: PALETTE.clayHot, opacity: 0.36, weight: 1 },
  { color: PALETTE.forestMid, opacity: 0.32, weight: 2 },
  { color: PALETTE.forest, opacity: 0.26, weight: 1 },
];

const pickTint = (seed: string): Tint => {
  const total = TINTS.reduce((sum, t) => sum + t.weight, 0);
  let r = random(seed) * total;
  for (const tint of TINTS) {
    r -= tint.weight;
    if (r <= 0) return tint;
  }
  return TINTS[0];
};

// —— Geometry ——————————————————————————————————————————————————————————

const roundedRectShape = (w: number, h: number, r: number, tail: boolean) => {
  const s = new THREE.Shape();
  const x0 = -w / 2;
  const y0 = -h / 2;
  const x1 = w / 2;
  const y1 = h / 2;
  s.moveTo(x0 + r, y0);
  if (tail) {
    // Small speech-bubble tail hanging from the bottom-left edge.
    const tx = x0 + w * 0.24;
    s.lineTo(tx, y0);
    s.lineTo(tx - w * 0.07, y0 - h * 0.24);
    s.lineTo(tx + w * 0.16, y0);
  }
  s.lineTo(x1 - r, y0);
  s.quadraticCurveTo(x1, y0, x1, y0 + r);
  s.lineTo(x1, y1 - r);
  s.quadraticCurveTo(x1, y1, x1 - r, y1);
  s.lineTo(x0 + r, y1);
  s.quadraticCurveTo(x0, y1, x0, y1 - r);
  s.lineTo(x0, y0 + r);
  s.quadraticCurveTo(x0, y0, x0 + r, y0);
  return s;
};

const softExtrude = (shape: THREE.Shape, depth: number, bevel: number) => {
  const geometry = new THREE.ExtrudeGeometry(shape, {
    depth,
    bevelEnabled: true,
    bevelThickness: bevel,
    bevelSize: bevel,
    bevelSegments: 5,
    curveSegments: 14,
  });
  geometry.center();
  return geometry;
};

const buildGeometries = (): THREE.BufferGeometry[] => [
  softExtrude(roundedRectShape(2.2, 1.4, 0.45, false), 0.32, 0.12), // 0 tile, landscape
  softExtrude(roundedRectShape(1.5, 1.5, 0.6, false), 0.36, 0.14), // 1 tile, squircle
  softExtrude(roundedRectShape(2.4, 1.5, 0.5, true), 0.32, 0.12), // 2 speech bubble
  softExtrude(roundedRectShape(1.8, 1.15, 0.42, true), 0.3, 0.1), // 3 small bubble
  new THREE.CapsuleGeometry(0.42, 1.6, 8, 18), // 4 pill, vertical
  new THREE.CapsuleGeometry(0.3, 2.4, 8, 18), // 5 pill, long
  new THREE.SphereGeometry(0.78, 28, 18), // 6 pebble
];

const pickGeometryIndex = (seed: string) => {
  const r = random(seed);
  if (r < 0.2) return 0;
  if (r < 0.36) return 1;
  if (r < 0.54) return 2;
  if (r < 0.68) return 3;
  if (r < 0.8) return 4;
  if (r < 0.9) return 5;
  return 6;
};

// —— Shape specs (deterministic, seeded) ———————————————————————————————

type ShapeSpec = {
  geometryIndex: number;
  tint: Tint;
  base: [number, number, number];
  scale: number;
  drift: { ax: number; ay: number; az: number; kx: number; ky: number; px: number; py: number; pz: number };
  spin: { base: [number, number, number]; ax: number; ay: number; az: number; k: number; p: number };
};

const buildShapes = (aspect: number): ShapeSpec[] => {
  const cols = 6;
  const rows = SHAPE_COUNT / cols;
  const specs: ShapeSpec[] = [];
  for (let i = 0; i < SHAPE_COUNT; i++) {
    const col = i % cols;
    const row = Math.floor(i / cols);
    const z = -16 + 19 * random(`z${i}`); // depth from far (-16) to near (+3)
    const halfH = halfHeightAt(z);
    const halfW = halfH * aspect;
    // Jittered grid in screen space so shapes cover the frame without clumping.
    const u = (col + 0.15 + 0.7 * random(`u${i}`)) / cols;
    const v = (row + 0.15 + 0.7 * random(`v${i}`)) / rows;
    // Partially compensate perspective: far shapes stay smaller, but not tiny.
    const depthScale = Math.sqrt((CAMERA_Z - z) / CAMERA_Z);
    specs.push({
      geometryIndex: pickGeometryIndex(`g${i}`),
      tint: pickTint(`tint${i}`),
      base: [(u * 2 - 1) * halfW * 1.08, (v * 2 - 1) * halfH * 1.02, z],
      scale: (0.6 + random(`s${i}`) * 1.0) * depthScale,
      drift: {
        ax: 0.5 + random(`ax${i}`) * 1.1,
        ay: 0.4 + random(`ay${i}`) * 0.9,
        az: 0.25 + random(`az${i}`) * 0.35,
        kx: random(`kx${i}`) > 0.65 ? 2 : 1,
        ky: random(`ky${i}`) > 0.65 ? 2 : 1,
        px: random(`px${i}`) * TAU,
        py: random(`py${i}`) * TAU,
        pz: random(`pz${i}`) * TAU,
      },
      spin: {
        base: [
          (random(`bx${i}`) - 0.5) * 1.0,
          (random(`by${i}`) - 0.5) * 1.2,
          (random(`bz${i}`) - 0.5) * 0.6,
        ],
        ax: 0.12 + random(`sx${i}`) * 0.3,
        ay: 0.15 + random(`sy${i}`) * 0.35,
        az: 0.1 + random(`sz${i}`) * 0.25,
        k: random(`sk${i}`) > 0.7 ? 2 : 1,
        p: random(`sp${i}`) * TAU,
      },
    });
  }
  return specs;
};

// —— Components ————————————————————————————————————————————————————————

const Backdrop: React.FC<{ t: number }> = ({ t }) => {
  // Two soft glows wander on closed loops over the static cream → clay gradient.
  const gx = 70 + 9 * Math.sin(TAU * t);
  const gy = 32 + 7 * Math.cos(TAU * t);
  const cx = 28 + 8 * Math.sin(TAU * t + 2.1);
  const cy = 76 + 6 * Math.cos(TAU * t + 0.8);
  return (
    <AbsoluteFill
      style={{
        background: [
          `radial-gradient(44% 48% at ${gx}% ${gy}%, rgba(220,232,168,0.6) 0%, rgba(220,232,168,0) 70%)`,
          `radial-gradient(48% 54% at ${cx}% ${cy}%, rgba(226,170,134,0.58) 0%, rgba(226,170,134,0) 70%)`,
          `linear-gradient(205deg, ${PALETTE.cream} 0%, ${PALETTE.paper} 46%, #ecd0ba 100%)`,
        ].join(','),
      }}
    />
  );
};

const CameraRig: React.FC<{ t: number }> = ({ t }) => {
  const camera = useThree((state) => state.camera);
  useLayoutEffect(() => {
    // Slow dolly along z with a subtle figure-eight sway; period = clip length.
    camera.position.set(
      0.55 * Math.sin(TAU * t),
      0.28 * Math.sin(TAU * 2 * t + 0.9),
      CAMERA_Z + 1.1 * Math.sin(TAU * t + 0.6)
    );
    camera.lookAt(0.4 * Math.sin(TAU * t + 1.2), 0, 0);
  }, [camera, t]);
  return null;
};

const Drifters: React.FC<{ t: number; aspect: number }> = ({ t, aspect }) => {
  const geometries = useMemo(buildGeometries, []);
  useEffect(() => () => geometries.forEach((g) => g.dispose()), [geometries]);
  const shapes = useMemo(() => buildShapes(aspect), [aspect]);

  return (
    <>
      {shapes.map((s, i) => {
        const { drift, spin } = s;
        const x = s.base[0] + drift.ax * Math.sin(TAU * drift.kx * t + drift.px);
        const y = s.base[1] + drift.ay * Math.sin(TAU * drift.ky * t + drift.py);
        const z = s.base[2] + drift.az * Math.sin(TAU * t + drift.pz);
        const rx = spin.base[0] + spin.ax * Math.sin(TAU * spin.k * t + spin.p);
        const ry = spin.base[1] + spin.ay * Math.sin(TAU * spin.k * t + spin.p + 1.3);
        const rz = spin.base[2] + spin.az * Math.sin(TAU * spin.k * t + spin.p + 2.2);
        return (
          <mesh
            key={i}
            geometry={geometries[s.geometryIndex]}
            position={[x, y, z]}
            rotation={[rx, ry, rz]}
            scale={s.scale}
          >
            <meshStandardMaterial
              color={s.tint.color}
              transparent
              opacity={s.tint.opacity}
              roughness={0.58}
              metalness={0}
              depthWrite={false}
            />
          </mesh>
        );
      })}
    </>
  );
};

type MoteSpec = {
  x: number;
  z: number;
  halfH: number;
  y0: number;
  cycles: number;
  swayK: number;
  swayA: number;
  phase: number;
  size: number;
  color: string;
};

const MOTE_COLORS = ['#ffffff', '#fff6e4', PALETTE.lime, '#f3cfb4', '#f0b996', '#e8f0c8'];

const buildMotes = (aspect: number): MoteSpec[] =>
  Array.from({ length: MOTE_COUNT }, (_, i) => {
    const z = -7 + 13 * random(`mz${i}`);
    const halfH = halfHeightAt(z);
    return {
      x: (random(`mx${i}`) * 2 - 1) * halfH * aspect * 1.02,
      z,
      halfH,
      y0: random(`my${i}`),
      cycles: random(`mc${i}`) > 0.55 ? 2 : 1, // integer → wraps exactly at the loop point
      swayK: 1 + Math.floor(random(`mk${i}`) * 3),
      swayA: 0.15 + random(`ma${i}`) * 0.4,
      phase: random(`mp${i}`) * TAU,
      size: 0.55 + random(`ms${i}`) * 1.0,
      color: MOTE_COLORS[Math.floor(random(`mcol${i}`) * MOTE_COLORS.length)],
    };
  });

const Motes: React.FC<{ t: number; aspect: number }> = ({ t, aspect }) => {
  const ref = useRef<THREE.InstancedMesh>(null);
  const motes = useMemo(() => buildMotes(aspect), [aspect]);
  const dummy = useMemo(() => new THREE.Object3D(), []);

  useLayoutEffect(() => {
    const mesh = ref.current;
    if (!mesh) return;
    const color = new THREE.Color();
    motes.forEach((m, i) => {
      color.set(m.color);
      mesh.setColorAt(i, color);
    });
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
  }, [motes]);

  useLayoutEffect(() => {
    const mesh = ref.current;
    if (!mesh) return;
    motes.forEach((m, i) => {
      // Rise through the frustum height; the wrap happens just outside the frame.
      const yFrac = (m.y0 + m.cycles * t) % 1;
      const y = (yFrac * 2 - 1) * m.halfH * 1.12;
      const x = m.x + m.swayA * Math.sin(TAU * m.swayK * t + m.phase);
      dummy.position.set(x, y, m.z);
      dummy.scale.setScalar(m.size);
      dummy.updateMatrix();
      mesh.setMatrixAt(i, dummy.matrix);
    });
    mesh.instanceMatrix.needsUpdate = true;
  }, [motes, t, dummy]);

  return (
    <instancedMesh ref={ref} args={[undefined, undefined, MOTE_COUNT]} frustumCulled={false}>
      <sphereGeometry args={[0.1, 10, 8]} />
      <meshBasicMaterial transparent opacity={0.9} depthWrite={false} />
    </instancedMesh>
  );
};

export const HeroLoop: React.FC = () => {
  const frame = useCurrentFrame();
  const { width, height, durationInFrames } = useVideoConfig();
  const t = frame / durationInFrames; // 0 → 1 over the clip; sin(TAU·t) is seamless
  const aspect = width / height;

  return (
    <AbsoluteFill style={{ backgroundColor: PALETTE.paper }}>
      <Backdrop t={t} />
      <ThreeCanvas
        width={width}
        height={height}
        camera={CAMERA}
        flat
        gl={{ antialias: true, alpha: true, powerPreference: 'high-performance' }}
        style={{ background: 'transparent' }}
      >
        <fog attach="fog" args={['#f7eee2', 15, 38]} />
        <hemisphereLight args={['#fff8ec', '#e6bfa2', 1.35]} />
        <directionalLight position={[8, 12, 10]} intensity={1.7} color="#fff3df" />
        <directionalLight position={[-10, -5, 6]} intensity={0.7} color={PALETTE.lime} />
        <CameraRig t={t} />
        <Drifters t={t} aspect={aspect} />
        <Motes t={t} aspect={aspect} />
      </ThreeCanvas>
    </AbsoluteFill>
  );
};
