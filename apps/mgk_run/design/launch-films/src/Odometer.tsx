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
  seg,
  useFonts,
  useSeconds,
  widthOf,
} from './kit';

/**
 * 02 · Odometer.
 *
 * The app's icon is on the screen as it was on the home screen. The mark
 * rolls out of it and an R rolls in; the tile opens to make room and U and N
 * roll in after it, the way a watch's digits turn. Then the tile lets go and
 * the word is left.
 */
export const Odometer: React.FC = () => {
  const ready = useFonts();
  const t = useSeconds();
  if (!ready) return null;

  const SIZE = 58;
  const TRACK = 3;
  const cy = H / 2 - 10;
  const TILE = 112;
  const PAD = 28;

  const letters = ['R', 'U', 'N'];
  const widths = letters.map((l) => widthOf(l, SIZE, '800', 0));
  const wordW = widths.reduce((a, b) => a + b, 0) + TRACK * 2;

  // The tile opens from a square to the width of the word.
  const open = seg(t, 0.62, 1.04, E.back);
  const tileW = lerp(TILE, wordW + PAD * 2, open);
  const tileX = (W - tileW) / 2;
  const tileY = cy - TILE / 2;

  // And then lets go.
  const release = seg(t, 1.12, 1.42, E.inOut);
  const arrive = seg(t, 0.0, 0.22, E.out);

  // Each thing rolls: out of the top, or in from the bottom.
  const markOut = seg(t, 0.3, 0.56, E.in);
  const rollIn = (at: number) => seg(t, at, at + 0.38, E.back);
  const rolls = [rollIn(0.4), rollIn(0.68), rollIn(0.78)];

  // R sits centred in the square tile, then steps left as it opens.
  const xs = (() => {
    const start = [(TILE - widths[0]) / 2, 0, 0];
    const end: number[] = [];
    let x = PAD;
    widths.forEach((w, i) => {
      end[i] = x;
      x += w + TRACK;
    });
    return letters.map((_, i) => (i === 0 ? lerp(start[0], end[0], open) : end[i]));
  })();

  // The lanes: a hairline out to each edge of the phone, level with the tile.
  const lanes = seg(t, 0.14, 0.5, E.out) * (1 - release);

  return (
    <Phone ground={<Ground opacity={seg(t, 0.2, 1.0, E.out)} />}>
      <Layer>
        {[-1, 1].map((side) => {
          const from = side < 0 ? tileX - 14 : tileX + tileW + 14;
          const to = side < 0 ? lerp(from, 18, lanes) : lerp(from, W - 18, lanes);
          return (
            <g key={side}>
              {[-18, 0, 18].map((dy) => (
                <line
                  key={dy}
                  x1={from}
                  x2={to}
                  y1={cy + dy}
                  y2={cy + dy}
                  stroke={C.white}
                  strokeWidth={1}
                  opacity={(dy === 0 ? 0.2 : 0.09) * lanes}
                />
              ))}
            </g>
          );
        })}
      </Layer>

      <div
        style={{
          position: 'absolute',
          left: tileX,
          top: tileY,
          width: tileW,
          height: TILE,
          borderRadius: 27,
          overflow: 'hidden',
          opacity: arrive,
          transform: `scale(${lerp(0.9, 1, arrive)})`,
        }}
      >
        {/* The tile itself, which fades while what is in it stays. */}
        <div
          style={{
            position: 'absolute',
            inset: 0,
            borderRadius: 27,
            background: `linear-gradient(115deg, #1E1E1E 0%, #343434 100%)`,
            boxShadow: 'inset 0 0 0 1px rgba(255,255,255,0.09), inset 0 1px 0 rgba(255,255,255,0.12)',
            opacity: 1 - release,
          }}
        />
        <svg
          width={TILE}
          height={TILE}
          style={{
            position: 'absolute',
            left: (tileW - TILE) / 2,
            top: 0,
            transform: `translateY(${-markOut * TILE}px)`,
            opacity: 1 - markOut * 0.6,
          }}
        >
          <Mark cx={TILE / 2} cy={TILE / 2} m={TILE} />
        </svg>
        {letters.map((l, i) => (
          <div
            key={l}
            style={{
              position: 'absolute',
              left: xs[i],
              top: (TILE - SIZE * 1.22) / 2,
              fontWeight: 800,
              fontSize: SIZE,
              lineHeight: 1.22,
              transform: `translateY(${(1 - rolls[i]) * TILE}px)`,
              opacity: Math.min(1, rolls[i] * 2.5),
            }}
          >
            {l}
          </div>
        ))}
      </div>

      <Caption y={cy + 50} at={1.16} />
    </Phone>
  );
};
