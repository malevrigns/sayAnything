import React, { useLayoutEffect, useRef } from 'react';
import { AbsoluteFill, useCurrentFrame, useVideoConfig } from 'remotion';
import { HEX } from '../stage/palette';
import { createSignalStage, type SignalStage } from '../signal/stage';
import { SIGNAL_COVER_FRAME, SIGNAL_LOOP_FRAMES } from '../signal/timeline';

/**
 * SignalLoop — the sayAnything hero background in the black tech register.
 *
 * Engine (frame-smith): particle assembly. A disk of fine silver particles
 * orbits in a black void; a lime beam sweeps across and the particles it
 * passes leave their orbit and land as a glowing 3D speech bubble, a HUD
 * reticle locks around it and three dots start typing. Then the shell peels
 * off and streams back into orbit, and the loop begins again.
 *
 * The beat table lives in ../signal/timeline.ts. Frame 0 is the composed
 * payoff (bubble resolved), so the poster and the loop seam are the same
 * picture. Muted web background: no audio track by design.
 */
export { SIGNAL_LOOP_FRAMES };

const Scene: React.FC<{ frame: number }> = ({ frame }) => {
  const { width, height } = useVideoConfig();
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const stageRef = useRef<SignalStage | null>(null);

  useLayoutEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return undefined;
    const stage = createSignalStage(canvas, width, height);
    stageRef.current = stage;
    return () => {
      stage.dispose();
      stageRef.current = null;
    };
  }, [width, height]);

  // Drawn synchronously from the frame number, so every render tab produces
  // identical pixels for the same frame.
  useLayoutEffect(() => {
    stageRef.current?.render(frame, SIGNAL_LOOP_FRAMES);
  }, [frame, width, height]);

  return (
    <AbsoluteFill style={{ backgroundColor: HEX.void }}>
      <canvas ref={canvasRef} width={width} height={height} style={{ width: '100%', height: '100%' }} />
    </AbsoluteFill>
  );
};

export const SignalLoop: React.FC = () => <Scene frame={useCurrentFrame()} />;

export const SignalLoopCover: React.FC = () => <Scene frame={SIGNAL_COVER_FRAME} />;
