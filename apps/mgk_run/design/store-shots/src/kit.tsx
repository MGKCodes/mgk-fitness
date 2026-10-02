import React, {useEffect, useState} from 'react';
import {continueRender, delayRender, staticFile} from 'remotion';
import {loadFont} from '@remotion/fonts';
import {measureText} from '@remotion/layout-utils';

/** AppColors, and the two greys the icon is drawn in. */
export const C = {
  bg: '#1A1A1A',
  lift: '#3A3A3A',
  silver: '#C0C0C0',
  white: '#FFFFFF',
  dim: '#8A8F98',
};

const faces: Array<[string, string]> = [
  ['Black', '900'],
  ['ExtraBold', '800'],
  ['Bold', '700'],
  ['SemiBold', '600'],
  ['Medium', '500'],
  ['Regular', '400'],
];

const fonts = Promise.all(
  faces.map(([name, weight]) =>
    loadFont({family: 'Inter', url: staticFile(`Inter-${name}.ttf`), weight}),
  ),
);

/** True once Inter is in, so nothing is measured or drawn in a fallback. */
export const useFonts = (): boolean => {
  const [ready, setReady] = useState(false);
  const [handle] = useState(() => delayRender('Inter'));
  useEffect(() => {
    fonts.then(() => {
      setReady(true);
      continueRender(handle);
    });
  }, [handle]);
  return ready;
};

/** The width of [text] as Inter will set it. Call only once fonts are ready. */
export const widthOf = (
  text: string,
  fontSize: number,
  fontWeight: string,
  letterSpacing = 0,
): number =>
  measureText({
    text,
    fontFamily: 'Inter',
    fontSize,
    fontWeight,
    letterSpacing: `${letterSpacing}px`,
  }).width;

/** The icon's ground: one soft light from the mark's heading. */
export const Ground: React.FC<{opacity?: number; at?: string}> = ({
  opacity = 1,
  at = '78% 22%',
}) => (
  <div
    style={{
      position: 'absolute',
      inset: 0,
      opacity,
      background: `radial-gradient(120% 70% at ${at}, rgba(58,58,58,0.6) 0%, rgba(26,26,26,0) 62%)`,
    }}
  />
);

/** The mark's proportions at a canvas of [m], as tool/build_app_icons.py has them. */
export const markOf = (m: number) => {
  const w = 0.61 * m;
  return {
    stroke: 0.09 * m,
    half: 0.215 * w,
    lean: 0.2 * w,
    gap: 0.36 * w,
    rise: 0.215 * w,
    /** Ink bounds, for laying it out beside type. */
    width: 0.36 * w + 0.2 * w + 0.09 * m,
    height: 2 * 0.215 * w + 0.215 * w + 0.09 * m,
  };
};

/** The whole mark, centred on (cx, cy), at a canvas of [m]. */
export const Mark: React.FC<{
  cx: number;
  cy: number;
  m: number;
  opacity?: number;
  trailing?: string;
  leading?: string;
}> = ({cx, cy, m, opacity = 1, trailing = C.silver, leading = C.white}) => {
  const g = markOf(m);
  return (
    <g opacity={opacity}>
      {[0, 1].map((i) => {
        const x = cx - g.gap / 2 - g.lean / 2 + i * g.gap;
        const y = cy + g.rise / 2 - i * g.rise;
        return (
          <polyline
            key={i}
            points={`${x},${y - g.half} ${x + g.lean},${y} ${x},${y + g.half}`}
            fill="none"
            stroke={i === 0 ? trailing : leading}
            strokeWidth={g.stroke}
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        );
      })}
    </g>
  );
};
