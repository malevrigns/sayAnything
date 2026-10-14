import React from 'react';
import { Composition, Folder } from 'remotion';
import { HeroLoop } from './HeroLoop';
import { SIGNAL_LOOP_FRAMES, SignalLoop, SignalLoopCover } from './compositions/SignalLoop';

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Folder name="Hero">
        {/* The live site hero: black tech register, 15 s seamless loop. */}
        <Composition
          id="SignalLoop"
          component={SignalLoop as React.ComponentType<any>}
          durationInFrames={SIGNAL_LOOP_FRAMES}
          fps={30}
          width={1920}
          height={1080}
          defaultProps={{}}
        />
        <Composition
          id="SignalLoopCover"
          component={SignalLoopCover as React.ComponentType<any>}
          durationInFrames={1}
          fps={30}
          width={1920}
          height={1440}
          defaultProps={{}}
        />
      </Folder>
      <Folder name="Archive">
        {/* Previous direction (warm dusk glass and silk), kept for comparison. */}
        <Composition id="HeroDusk" component={HeroLoop} durationInFrames={450} fps={30} width={1920} height={1080} />
      </Folder>
    </>
  );
};
