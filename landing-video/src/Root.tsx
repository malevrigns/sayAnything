import React from 'react';
import { Composition } from 'remotion';
import { HeroLoop } from './HeroLoop';

// 12 s at 30 fps. Every motion in HeroLoop has a period equal to
// durationInFrames (or an integer fraction of it), so the clip loops seamlessly.
export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="HeroLoop"
      component={HeroLoop}
      durationInFrames={360}
      fps={30}
      width={1920}
      height={1080}
    />
  );
};
