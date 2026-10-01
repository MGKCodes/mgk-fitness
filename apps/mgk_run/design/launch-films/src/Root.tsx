import React from 'react';
import {Composition} from 'remotion';
import {FPS, H, SCALE, SECONDS, W} from './kit';
import {Slipstream} from './Slipstream';
import {Odometer} from './Odometer';
import {Pace} from './Pace';
import {Route} from './Route';

const films: Array<[string, React.FC]> = [
  ['Slipstream', Slipstream],
  ['Odometer', Odometer],
  ['Pace', Pace],
  ['Route', Route],
];

export const Root: React.FC = () => (
  <>
    {films.map(([id, component]) => (
      <Composition
        key={id}
        id={id}
        component={component}
        durationInFrames={Math.round(SECONDS * FPS)}
        fps={FPS}
        width={W * SCALE}
        height={H * SCALE}
      />
    ))}
  </>
);
