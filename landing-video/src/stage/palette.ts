import * as THREE from 'three';

// sRGB hex values, derived from the site palette in server/web/styles.css
// (forest, clay, lime, paper, cream) plus darker dusk tones for the backdrop.
// THREE.Color converts hex to the linear working space automatically.
export const HEX = {
  ink: '#090c0a',
  forestDeep: '#0e1a15',
  forest: '#1a332a',
  espresso: '#1d1510',
  umber: '#4a2c1c',
  clay: '#c45c2a',
  clayHot: '#d46834',
  amber: '#f2a46c',
  apricot: '#ffd3a6',
  champagne: '#eadcc6',
  paper: '#f3eee4',
  cream: '#faf6ee',
  lime: '#dce8a8',
} as const;

export const linear = (hex: string, intensity = 1): THREE.Color =>
  new THREE.Color(hex).multiplyScalar(intensity);
