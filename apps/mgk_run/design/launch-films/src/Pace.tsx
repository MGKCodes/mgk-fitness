import React from 'react';
import {
  C,
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
} from './kit';

/**
 * 03 · Pace.
 *
 * The word is the picture. The mark steps up to be its eyebrow, the letters
 * come up through the line one after another, and under them distance goes by
 * on a rule and slows to a stop, with a clock that has been running since the
 * app was opened.
 */
export const Pace: React.FC = () => {
  const ready = useFonts();
  const t = useSeconds();
  if (!ready) return null;

  const SIZE = 118;
  const cy = H / 2 - 6;

  // The mark: centre, then up and small.
  const up = seg(t, 0.2, 0.62, E.inOut);
  const m = lerp(150, 58, up);
  const my = lerp(cy, cy - 92, up);

  // The letters, each through its own slot.
  const letters = ['R', 'U', 'N'];
  const rise = (i: number) => seg(t, 0.4 + i * 0.075, 0.92 + i * 0.075, E.out);

  // The rule: fast, then it stops.
  const run = seg(t, 0.25, 1.5, E.out);
  const offset = run * 640;
  const ruleIn = seg(t, 0.25, 0.6, E.out);
  const STEP = 7;
  const ruleY = cy + 84;
  const first = Math.floor(offset / STEP) - 2;
  const ticks = Array.from({length: Math.ceil(W / STEP) + 6}, (_, k) => first + k);

  // The clock stops with the rule.
  const clock = Math.min(t, 1.5);
  const stamp = `0:0${Math.floor(clock)}.${String(Math.floor((clock % 1) * 100)).padStart(2, '0')}`;

  return (
    <Phone ground={<Ground opacity={seg(t, 0.3, 1.1, E.out)} />}>
      <Layer>
        <Mark cx={W / 2} cy={my} m={m} />
      </Layer>

      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top: cy - SIZE * 0.52,
          height: SIZE * 1.0,
          display: 'flex',
          justifyContent: 'center',
          overflow: 'hidden',
        }}
      >
        {letters.map((l, i) => (
          <div
            key={l}
            style={{
              fontWeight: 900,
              fontSize: SIZE,
              lineHeight: 1,
              letterSpacing: -1.5,
              transform: `translateY(${(1 - rise(i)) * SIZE * 1.05}px)`,
            }}
          >
            {l}
          </div>
        ))}
      </div>

      <Layer style={{opacity: ruleIn}}>
        <line x1={0} x2={W} y1={ruleY} y2={ruleY} stroke={C.white} strokeWidth={1} opacity={0.14} />
        {ticks.map((n) => {
          const x = n * STEP - offset + 24;
          const major = n % 10 === 0;
          const mid = n % 5 === 0;
          // Fades toward both edges, so the rule has no ends.
          const edge = Math.min(1, Math.min(x, W - x) / 70);
          if (edge <= 0) return null;
          return (
            <g key={n} opacity={edge}>
              <line
                x1={x}
                x2={x}
                y1={ruleY}
                y2={ruleY + (major ? 13 : mid ? 9 : 5)}
                stroke={C.white}
                strokeWidth={1}
                opacity={major ? 0.5 : 0.22}
              />
              {major && n >= 0 ? (
                <text
                  x={x}
                  y={ruleY + 27}
                  fill={C.white}
                  opacity={0.34}
                  fontSize={8.5}
                  fontWeight={600}
                  textAnchor="middle"
                  fontFamily="Inter"
                  letterSpacing={0.6}
                >
                  {(n / 10) * 100}
                </text>
              ) : null}
            </g>
          );
        })}
        {/* Where you are on it. */}
        <line x1={W / 2} x2={W / 2} y1={ruleY - 7} y2={ruleY + 15} stroke={C.white} strokeWidth={1.5} />
      </Layer>

      <div
        style={{
          position: 'absolute',
          left: 28,
          right: 28,
          top: ruleY + 42,
          display: 'flex',
          justifyContent: 'space-between',
          fontSize: 10,
          fontWeight: 600,
          letterSpacing: 3.6,
          color: C.dim,
          opacity: seg(t, 0.55, 0.95, E.out),
        }}
      >
        <span>MGKFITNESS</span>
        <span style={{fontVariantNumeric: 'tabular-nums', letterSpacing: 1.6, color: C.silver}}>
          {stamp}
        </span>
      </div>
    </Phone>
  );
};
