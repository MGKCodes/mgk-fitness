import React from 'react';
import {evolvePath, getLength, getPointAtLength} from '@remotion/paths';
import {
  C,
  Caption,
  E,
  Ground,
  H,
  Layer,
  Mark,
  Phone,
  W,
  lerp,
  seg,
  useFonts,
  useSeconds,
  widthOf,
} from './kit';

/**
 * 04 · Route.
 *
 * What the app is for, in a second and a half: a run draws itself across a
 * map, and where it ends is the mark. The name comes up under it.
 */
export const Route: React.FC = () => {
  const ready = useFonts();
  const t = useSeconds();
  if (!ready) return null;

  const cx = W / 2;
  const cy = H / 2 - 28;

  // A run through streets: in from the lower left, a long bend, and home.
  // It keeps clear of where the name will stand: under it, up the right-hand
  // side, over the top, and in to the mark from the left.
  const route =
    `M -24 772 C 70 760 84 676 168 672 S 318 716 338 612 ` +
    `S 372 392 312 318 S 166 262 118 322 S 92 ${cy} ${cx - 44} ${cy}`;
  const length = getLength(route);
  const drawn = seg(t, 0.12, 1.0, E.inOut);
  const {strokeDasharray, strokeDashoffset} = evolvePath(drawn, route);
  const head = getPointAtLength(route, length * drawn);

  // The streets it runs through. Fixed: a map is not a pattern.
  const streets = [
    'M -10 560 L 410 470',
    'M -10 690 L 410 612',
    'M -10 410 L 410 318',
    'M -10 800 L 410 742',
    'M 60 -10 L 150 870',
    'M 214 -10 L 300 870',
    'M 330 -10 L 392 560',
    'M -10 250 L 410 196',
    'M -10 120 Q 200 150 410 84',
  ];
  const map = seg(t, 0.0, 0.5, E.out);
  const settle = seg(t, 1.0, 1.4, E.inOut);

  // The mark opens out of the point the run ends on.
  const open = seg(t, 0.96, 1.34, E.back);
  const dot = 1 - seg(t, 0.96, 1.12, E.out);

  const SIZE = 30;
  const tracking = lerp(15, 7, seg(t, 1.06, 1.5, E.out));
  const word = seg(t, 1.06, 1.4, E.out);
  // Tracking-in moves the ink; this keeps it centred on the mark throughout.
  const wordW = widthOf('RUN', SIZE, '800', tracking) - tracking;

  return (
    <Phone ground={<Ground opacity={seg(t, 0.2, 1.0, E.out)} />}>
      <Layer style={{opacity: map * lerp(1, 0.55, settle)}}>
        {streets.map((d) => (
          <path key={d} d={d} fill="none" stroke={C.white} strokeWidth={1} opacity={0.07} />
        ))}
      </Layer>

      <Layer>
        <path
          d={route}
          fill="none"
          stroke={C.white}
          strokeWidth={11}
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeDasharray={strokeDasharray}
          strokeDashoffset={strokeDashoffset}
          opacity={0.07 * lerp(1, 0.4, settle)}
        />
        <path
          d={route}
          fill="none"
          stroke={C.white}
          strokeWidth={3}
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeDasharray={strokeDasharray}
          strokeDashoffset={strokeDashoffset}
          opacity={lerp(0.95, 0.3, settle)}
        />
        {dot > 0 && drawn > 0 ? (
          <g opacity={dot}>
            <circle cx={head.x} cy={head.y} r={11} fill={C.white} opacity={0.14} />
            <circle cx={head.x} cy={head.y} r={5} fill={C.white} />
          </g>
        ) : null}
        <g
          transform={`translate(${cx} ${cy}) scale(${lerp(0.25, 1, open)}) translate(${-cx} ${-cy})`}
          opacity={Math.min(1, seg(t, 0.96, 1.1, E.out))}
        >
          <Mark cx={cx} cy={cy} m={128} />
        </g>
      </Layer>

      <div
        style={{
          position: 'absolute',
          left: (W - wordW) / 2,
          top: cy + 56 + lerp(8, 0, word),
          fontWeight: 800,
          fontSize: SIZE,
          letterSpacing: tracking,
          whiteSpace: 'nowrap',
          opacity: word,
        }}
      >
        RUN
      </div>

      <Caption y={cy + 104} at={1.2} />
    </Phone>
  );
};
