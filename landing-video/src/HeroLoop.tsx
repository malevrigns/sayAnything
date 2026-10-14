import React, { useLayoutEffect, useRef } from 'react';
import { AbsoluteFill, useCurrentFrame, useVideoConfig } from 'remotion';
import { createStage, type Stage } from './stage/stage';

/**
 * HeroLoop: "有些话，在这里慢慢说" as a quiet dusk still life.
 *
 * Two frosted glass speech bubbles float in warm evening light, champagne and
 * clay silk drifting behind them; three points inside the front bubble light
 * up one after another like someone typing slowly. The background layer is
 * rendered with real depth of field, the glass stays in focus, and the frame
 * is finished with AgX tone mapping, a soft vignette and film grain.
 *
 * Rendering is plain three.js driven by Remotion's frame: each frame is drawn
 * synchronously from useCurrentFrame(), so every Remotion render tab produces
 * identical pixels. All motion uses integer multiples of one loop period, so
 * the last frame flows straight into the first.
 */
export const HeroLoop: React.FC = () => {
  const frame = useCurrentFrame();
  const { width, height, durationInFrames } = useVideoConfig();
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const stageRef = useRef<Stage | null>(null);

  useLayoutEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return undefined;
    const stage = createStage(canvas, width, height);
    stageRef.current = stage;
    return () => {
      stage.dispose();
      stageRef.current = null;
    };
  }, [width, height]);

  useLayoutEffect(() => {
    stageRef.current?.render(frame, durationInFrames);
  }, [frame, durationInFrames, width, height]);

  return (
    <AbsoluteFill style={{ backgroundColor: '#090c0a' }}>
      <canvas ref={canvasRef} width={width} height={height} style={{ width: '100%', height: '100%' }} />
    </AbsoluteFill>
  );
};
