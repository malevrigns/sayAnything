import { Easing, interpolate, spring } from 'remotion';

// Motion craft floor (frame-smith): 30 fps, time authored in seconds, every
// time-range interpolate clamped, one locked easing vocabulary.
export const FPS = 30;
export const f = (s: number) => Math.round(s * FPS);
export const clampOpts = { extrapolateLeft: 'clamp' as const, extrapolateRight: 'clamp' as const };

const power3Out = Easing.out(Easing.cubic);
const power3In = Easing.in(Easing.cubic);
const power2In = Easing.in(Easing.quad);
const power2InOut = Easing.inOut(Easing.quad);
const scanEase = Easing.inOut(Easing.cubic);
const backOut = Easing.out(Easing.back(1.6));
const unlockLock = Easing.inOut(Easing.back(1.25)); // a small wind-up on release, an overshoot on lock

// Beat table. The loop opens on its payoff, so frame 0 is also the poster and
// the last frame flows straight back into it.
export const H0 = f(0); //     HOLD    bubble resolved, HUD locked, three dots typing
export const H1 = f(2.6); //   RELEASE the shell peels off left to right, particles stream back into orbit
export const H2 = f(5.6); //   ORBIT   the signal disk alone; a crosshair searches the dark
export const H3 = f(8.2); //   SCAN    a lime beam sweeps left to right, particles land behind it
export const H4 = f(11.0); //  LOCK    HUD arcs snap in, typing dots pop, one ripple crosses the matrix
export const HEND = f(15.0);
export const SIGNAL_LOOP_FRAMES = HEND;
export const SIGNAL_COVER_FRAME = f(13.2); // inside HOLD, after the lock flash has settled

// Bubble-local x range the beam and the eraser travel. They start and end
// beyond the bubble so no particle is caught mid-flight at a beat boundary.
const SWEEP_FROM = -1.6;
const SWEEP_TO = 1.6;
const OFF = 9; // "everything has passed" / "nothing has passed yet"

// The typing indicator cycles on a period that divides the loop, so the
// pulse phase at the last frame continues into frame 0.
const TYPING_PERIOD = f(1.5);

export interface Beat {
  scanX: number; // particles whose target x is left of this have landed
  eraseX: number; // particles whose target x is left of this have left again
  scanGlow: number; // beam visibility
  dotPop: [number, number, number]; // spring scale of the three typing dots
  dotGlow: [number, number, number]; // typing pulse brightness
  spin: number; // HUD ring spin progress, 0 = locked pose, 1 = one full pattern period later
  arcs: number; // stroke-write progress of the lime HUD arcs (overshoots on lock)
  ringAlpha: number;
  outlineAlpha: number;
  crosshair: { alpha: number; x: number; y: number };
  ripple: number; // seconds since lock, or -1 when no ripple is travelling
  flash: number; // lock exposure swell on the bubble
}

const typingPulse = (frame: number, index: number) => {
  const local = (((frame - index * f(0.25)) % TYPING_PERIOD) + TYPING_PERIOD) % TYPING_PERIOD;
  const rise = interpolate(local, [0, f(0.16)], [0, 1], { ...clampOpts, easing: power3Out });
  const fall = interpolate(local, [f(0.16), f(0.75)], [0, 1], { ...clampOpts, easing: power2InOut });
  return rise * (1 - fall);
};

export function beatAt(frame: number): Beat {
  const holding = frame < H1 || frame >= H4;

  // Assembly front (scan) and dissolution front (erase), both left to right:
  // the exit continues the vector the bubble was printed with.
  let scanX: number;
  let eraseX: number;
  if (frame >= H3 && frame < H4) {
    scanX = interpolate(frame, [H3, H4 - f(0.35)], [SWEEP_FROM, SWEEP_TO], { ...clampOpts, easing: scanEase });
    eraseX = -OFF;
  } else if (frame >= H2 && frame < H3) {
    scanX = -OFF;
    eraseX = OFF;
  } else {
    scanX = OFF;
    eraseX =
      frame >= H1 && frame < H2
        ? interpolate(frame, [H1, H2 - f(0.2)], [SWEEP_FROM, SWEEP_TO + 0.6], { ...clampOpts, easing: power2InOut })
        : -OFF;
  }
  const scanGlow = interpolate(frame, [H3, H3 + f(0.3), H4 - f(0.5), H4 - f(0.1)], [0, 1, 1, 0], clampOpts);

  // Typing dots: they are not printed by the beam; they spring in on the lock.
  const dotPop = [0, 1, 2].map((i) => {
    if (frame < H1) return 1;
    if (frame < H4) return frame < H2 ? 1 : 0;
    return spring({ frame: frame - (H4 + f(0.35) + i * f(0.08)), fps: FPS, config: { damping: 11, stiffness: 160, mass: 0.8 } });
  }) as [number, number, number];
  const dotGlow = [0, 1, 2].map((i) => (holding ? typingPulse(frame, i) : 0)) as [number, number, number];

  // HUD reticle: winds up and starts spinning on release, searches, then
  // decelerates and overshoots into the locked pose at H4.
  const spin = frame < H1 ? 0 : interpolate(frame, [H1 + f(0.1), H4 + f(0.7)], [0, 1], { ...clampOpts, easing: unlockLock });
  let arcs = 1;
  if (frame >= H1 && frame < H4) arcs = interpolate(frame, [H1, H1 + f(0.7)], [1, 0], { ...clampOpts, easing: power3In });
  else if (frame >= H4) arcs = interpolate(frame, [H4 + f(0.1), H4 + f(0.65)], [0, 1], { ...clampOpts, easing: backOut });
  let ringAlpha = 1;
  if (frame >= H1 && frame < H4) ringAlpha = interpolate(frame, [H1, H1 + f(0.8)], [1, 0.42], { ...clampOpts, easing: power2InOut });
  else if (frame >= H4) ringAlpha = interpolate(frame, [H4, H4 + f(0.45)], [0.42, 1], { ...clampOpts, easing: power3Out });

  const outlineAlpha = frame >= H1 && frame < H2 ? interpolate(frame, [H1, H2 - f(0.4)], [1, 0], { ...clampOpts, easing: power2In }) : 1;

  // Crosshair: appears in the dark while the disk orbits alone, drifts on a
  // two-frequency path, then glides to the target as the beam starts.
  const crossAlpha = interpolate(frame, [H2 + f(0.2), H2 + f(0.7), H3 + f(0.9), H3 + f(1.5)], [0, 0.85, 0.85, 0], clampOpts);
  const t = Math.max(0, frame - H2) / FPS;
  const homing = interpolate(frame, [H3 - f(0.2), H3 + f(0.9)], [0, 1], { ...clampOpts, easing: power3Out });
  const crosshair = {
    alpha: crossAlpha,
    x: (1 - homing) * (0.42 * Math.sin(t * 1.15 + 0.4) - 0.2),
    y: (1 - homing) * (0.3 * Math.cos(t * 0.83 + 1.1)),
  };

  const ripple = frame >= H4 ? (frame - H4) / FPS : -1;
  const flash =
    frame >= H4
      ? interpolate(frame, [H4 + f(0.3), H4 + f(0.5)], [0, 1], { ...clampOpts, easing: power3Out }) *
        (1 - interpolate(frame, [H4 + f(0.5), H4 + f(2.0)], [0, 1], { ...clampOpts, easing: power2InOut }))
      : 0;

  return { scanX, eraseX, scanGlow, dotPop, dotGlow, spin, arcs, ringAlpha, outlineAlpha, crosshair, ripple, flash };
}
