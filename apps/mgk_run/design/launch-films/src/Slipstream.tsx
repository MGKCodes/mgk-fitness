import React from 'react';
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
  markOf,
  seg,
  useFonts,
  useSeconds,
  widthOf,
} from './kit';

/**
 * 01 · Slipstream.
 *
 * The mark winds back, then goes, and the word is what it leaves behind it.
 * It comes to rest as the last character of its own name: RUN ».
 */
export const Slipstream: React.FC = () => {
  const ready = useFonts();
  const t = useSeconds();
  if (!ready) return null;

  const SIZE = 60;
  const TRACK = 3;
  const cy = H / 2 - 10;

  // The lockup: the word, a space, the mark at cap height.
  const wordW = widthOf('RUN', SIZE, '800', TRACK) - TRACK;
  const small = 92;
  const g = markOf(small);
  const space = 13;
  const lockW = wordW + space + g.width;
  const left = (W - lockW) / 2;
  const markHome = left + wordW + space + g.width / 2;

  // Three beats: the wind-up, the dash, the rest.
  const back = seg(t, 0.2, 0.56, E.inOut);
  const dash = seg(t, 0.56, 1.02, E.out);
  const big = 150;
  const m = lerp(big, small, back);
  const crouch = left - 6 + markOf(small).width / 2;
  const cx = lerp(lerp(W / 2, crouch, back), markHome, dash);
  // Drawn in on itself as it winds back, and opening out again as it lands.
  const spread = lerp(lerp(1, 0.78, back), 1, seg(t, 0.56, 0.9, E.out));

  // The word is uncovered up to the mark's trailing edge.
  const trailing = cx - markOf(m).width / 2 - 6;
  // Nothing before the dash: the mark starts in the middle of where the word
  // will be, and a word half uncovered by a mark standing still is a mistake.
  const shown = dash <= 0 ? 0 : Math.max(0, Math.min(wordW, trailing - left));

  // What moving fast looks like: the mark a moment ago, fainter.
  const speed = Math.abs(
    lerp(crouch, markHome, seg(t, 0.56, 1.02, E.out)) -
      lerp(crouch, markHome, seg(t - 0.03, 0.56, 1.02, E.out)),
  );
  const ghosts = [1, 2, 3].map((k) => ({
    dx: -speed * k * 0.55,
    opacity: Math.min(0.28, speed / 60) / k,
  }));

  // The air going past. Each line is a fixed length, fixed lane, own moment.
  const lines = [
    {y: -58, len: 54, at: 0.58, o: 0.22},
    {y: -31, len: 96, at: 0.63, o: 0.14},
    {y: 37, len: 72, at: 0.6, o: 0.2},
    {y: 61, len: 120, at: 0.66, o: 0.12},
    {y: 88, len: 40, at: 0.7, o: 0.18},
    {y: -84, len: 30, at: 0.72, o: 0.14},
  ];

  return (
    <Phone ground={<Ground opacity={seg(t, 0.4, 1.1, E.out)} />}>
      <Layer>
        {lines.map((l, i) => {
          const p = seg(t, l.at, l.at + 0.42, E.linear);
          if (p <= 0 || p >= 1) return null;
          const x = lerp(W * 0.86, W * 0.06, E.out(p));
          const fade = Math.sin(Math.PI * p);
          return (
            <line
              key={i}
              x1={x}
              x2={x + l.len * (0.4 + 0.6 * fade)}
              y1={cy + l.y}
              y2={cy + l.y}
              stroke={C.white}
              strokeWidth={1.25}
              strokeLinecap="round"
              opacity={l.o * fade}
            />
          );
        })}
      </Layer>

      <div
        style={{
          position: 'absolute',
          left,
          top: cy - SIZE * 0.61,
          width: shown,
          height: SIZE * 1.22,
          overflow: 'hidden',
        }}
      >
        <div
          style={{
            fontWeight: 800,
            fontSize: SIZE,
            lineHeight: 1.22,
            letterSpacing: TRACK,
            whiteSpace: 'nowrap',
          }}
        >
          RUN
        </div>
      </div>

      <Layer>
        {ghosts.map((gh, i) => (
          <Mark key={i} cx={cx + gh.dx} cy={cy} m={m} spread={spread} opacity={gh.opacity} />
        ))}
        <Mark cx={cx} cy={cy} m={m} spread={spread} />
      </Layer>

      <Caption y={cy + 46} at={1.0} />
    </Phone>
  );
};
