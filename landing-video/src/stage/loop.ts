export const TAU = Math.PI * 2;

// Every animated value is a function of theta = TAU * frame / durationInFrames
// using integer multiples only, so the last frame flows straight into frame 0.

export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

// Small deterministic PRNG: the same seed gives the same scene in every
// Remotion render tab, which matters because frames render in parallel.
export function mulberry32(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
