import React from 'react';
import {Composition} from 'remotion';
import {HeaderName, HeaderSlipstream} from './Header';
import {Search} from './Search';
import {Universal} from './Universal';
import {FILM_SECONDS, FPS, SPEC} from './spec';

/**
 * Three options, as App Store Connect would take them:
 *
 * - A · `header-name` + `search`: two pictures, each doing its own job.
 * - B · `header-slipstream` + `search`: the header moves, the search
 *   result is A's.
 * - C · `universal`: one picture for both placements.
 */
export const Root: React.FC = () => (
  <>
    <Composition id="header-name" component={HeaderName} durationInFrames={1} fps={1} width={SPEC.header.w} height={SPEC.header.h} />
    <Composition
      id="header-slipstream"
      component={HeaderSlipstream}
      durationInFrames={FILM_SECONDS * FPS}
      fps={FPS}
      width={SPEC.header.w}
      height={SPEC.header.h}
    />
    <Composition id="search" component={Search} durationInFrames={1} fps={1} width={SPEC.search.w} height={SPEC.search.h} />
    <Composition id="universal" component={Universal} durationInFrames={1} fps={1} width={SPEC.universal.w} height={SPEC.universal.h} />
  </>
);
