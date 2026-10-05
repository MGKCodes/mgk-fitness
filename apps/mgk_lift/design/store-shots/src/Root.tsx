import React from 'react';
import {Composition, useCurrentFrame} from 'remotion';
import {Kind} from './Device';
import {Feature} from './Feature';
import {Plain, Slipstream, Still} from './Layouts';
import {useFonts} from './kit';
import {SHOTS, TIME} from './shots';

type SetProps = {
  kind: Kind;
  design: 'still' | 'slipstream' | 'plain';
  width: number;
  height: number;
  /** The status bar's clock. `render.sh` passes the one the screens were drawn by. */
  time?: string;
};

/**
 * One design for one store: six pictures, one a frame. Rendered as an image
 * sequence, so a whole set is one run of the renderer and not six.
 */
const Set: React.FC<SetProps> = ({kind, design, width, height, time = TIME}) => {
  const ready = useFonts();
  const frame = useCurrentFrame();
  if (!ready) return null;
  const shot = SHOTS[frame % SHOTS.length];
  if (design === 'still') {
    return <Still shot={shot} kind={kind} width={width} height={height} time={time} />;
  }
  if (design === 'slipstream') {
    return (
      <Slipstream shot={shot} kind={kind} width={width} height={height} time={time} index={frame} />
    );
  }
  return <Plain shot={shot} kind={kind} width={width} height={height} time={time} />;
};

/**
 * The sizes each store takes. App Store Connect wants a 6.9" iPhone at
 * 1290x2796. Play refuses a picture more than twice as tall as it is wide, and
 * features an app only on 9:16 ones, so its captioned sets are 1080x1920 and
 * the plain one is the screen itself at 1080x2160.
 */
const sets: Array<[string, SetProps]> = [
  ['ios-still', {kind: 'iphone', design: 'still', width: 1290, height: 2796}],
  ['ios-slipstream', {kind: 'iphone', design: 'slipstream', width: 1290, height: 2796}],
  ['ios-plain', {kind: 'iphone', design: 'plain', width: 1290, height: 2796}],
  ['play-still', {kind: 'android', design: 'still', width: 1080, height: 1920}],
  ['play-slipstream', {kind: 'android', design: 'slipstream', width: 1080, height: 1920}],
  ['play-plain', {kind: 'android', design: 'plain', width: 1080, height: 2160}],
];

export const Root: React.FC = () => (
  <>
    {sets.map(([id, props]) => (
      <Composition
        key={id}
        id={id}
        component={Set}
        defaultProps={props}
        durationInFrames={SHOTS.length}
        fps={1}
        width={props.width}
        height={props.height}
      />
    ))}
    <Composition
      id="play-feature"
      component={Feature}
      durationInFrames={1}
      fps={1}
      width={1024}
      height={500}
    />
  </>
);
