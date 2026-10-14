import * as THREE from 'three';
import { HEX, linear } from './palette';

// A small studio built from emissive "softboxes" inside a dark dome, baked
// into a prefiltered environment map. Glass and silk read their reflections
// and most of their light from it, which is what gives them a photographic
// finish: long soft highlights instead of point-light dots.
export function buildEnvironment(renderer: THREE.WebGLRenderer): THREE.Texture {
  const scene = new THREE.Scene();
  const geometries: THREE.BufferGeometry[] = [];
  const materials: THREE.Material[] = [];

  const domeGeometry = new THREE.SphereGeometry(40, 64, 32);
  const domeMaterial = new THREE.ShaderMaterial({
    side: THREE.BackSide,
    depthWrite: false,
    uniforms: {
      cTop: { value: linear(HEX.espresso, 0.55) },
      cMid: { value: linear(HEX.umber, 0.32) },
      cLow: { value: linear(HEX.forestDeep, 0.22) },
    },
    vertexShader: /* glsl */ `
      varying vec3 vDir;
      void main() {
        vDir = normalize(position);
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }`,
    fragmentShader: /* glsl */ `
      uniform vec3 cTop, cMid, cLow;
      varying vec3 vDir;
      void main() {
        float y = vDir.y;
        vec3 c = y > 0.0 ? mix(cMid, cTop, smoothstep(0.0, 0.9, y)) : mix(cMid, cLow, smoothstep(0.0, -0.7, y));
        gl_FragColor = vec4(c, 1.0);
      }`,
  });
  geometries.push(domeGeometry);
  materials.push(domeMaterial);
  scene.add(new THREE.Mesh(domeGeometry, domeMaterial));

  const panel = (w: number, h: number, hex: string, intensity: number, at: [number, number, number]) => {
    const geometry = new THREE.PlaneGeometry(w, h);
    const material = new THREE.MeshBasicMaterial({ color: linear(hex, intensity), side: THREE.DoubleSide });
    geometries.push(geometry);
    materials.push(material);
    const mesh = new THREE.Mesh(geometry, material);
    mesh.position.set(...at);
    mesh.lookAt(0, 0, 0);
    scene.add(mesh);
  };
  panel(7, 5, HEX.apricot, 10, [9, 7, 8]); // warm key, upper right
  panel(11, 3.6, HEX.paper, 4.2, [3, 5, 14]); // wide strip behind the camera: the sweep across the glass faces
  panel(1.1, 13, HEX.cream, 9, [-11, 1, -5]); // tall rim strip behind left
  panel(16, 3, HEX.paper, 1.6, [0, 13, 1]); // soft overhead
  panel(10, 6, HEX.amber, 0.6, [-7, -2, 11]); // faint warm fill
  panel(0.7, 8, HEX.lime, 2.6, [8, -1, -9]); // thin lime accent
  panel(4, 2.5, HEX.clayHot, 3.5, [13, -5, 3]); // low clay kicker

  const pmrem = new THREE.PMREMGenerator(renderer);
  const target = pmrem.fromScene(scene, 0, 0.1, 100);
  pmrem.dispose();
  geometries.forEach((g) => g.dispose());
  materials.forEach((m) => m.dispose());
  return target.texture;
}
