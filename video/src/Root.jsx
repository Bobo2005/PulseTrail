import React from 'react';
import { Composition, registerRoot } from 'remotion';
import { PulseTrailVideo } from './PulseTrailVideo.jsx';
import { VIDEO_META } from './timeline.js';

export const RemotionRoot = () => {
  return (
    <>
      <Composition
        id="PulseTrailDesktop"
        component={PulseTrailVideo}
        durationInFrames={VIDEO_META.durationInFrames}
        fps={VIDEO_META.fps}
        width={VIDEO_META.desktop.width}
        height={VIDEO_META.desktop.height}
        defaultProps={{ orientation: 'desktop' }}
      />
      <Composition
        id="PulseTrailVertical"
        component={PulseTrailVideo}
        durationInFrames={VIDEO_META.durationInFrames}
        fps={VIDEO_META.fps}
        width={VIDEO_META.vertical.width}
        height={VIDEO_META.vertical.height}
        defaultProps={{ orientation: 'vertical' }}
      />
    </>
  );
};

registerRoot(RemotionRoot);
export default RemotionRoot;

