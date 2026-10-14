import React from 'react';
import { Composition } from 'remotion';
import { HeroLoop } from './HeroLoop';

// 15 s at 30 fps. Every motion in HeroLoop is periodic over exactly
// durationInFrames, so the clip loops without a seam.
export const RemotionRoot: React.FC = () => {
  return <Composition id="HeroLoop" component={HeroLoop} durationInFrames={450} fps={30} width={1920} height={1080} />;
};
