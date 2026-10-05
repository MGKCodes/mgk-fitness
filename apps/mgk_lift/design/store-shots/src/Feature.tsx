import React from 'react';
import {AbsoluteFill} from 'remotion';
import {C, Ground, Mark, markOf, useFonts} from './kit';

/**
 * Google Play's feature graphic, 1024x500: the launch animation's last frame,
 * the mark at rest above `LIFT`, on the app's ground.
 *
 * **Stacked, where Run's is in a line**, as the launch is
 * (lib/src/core/launch/launch_curtain.dart): Run's mark rests after its name
 * because that is the way it travels, and this one travels up. The air falls
 * past either side of the name, never across it.
 *
 * Play crops it and lays a play button over the middle of it in places, so
 * nothing that matters is within about 80 px of an edge.
 */
export const Feature: React.FC = () => {
  const ready = useFonts();
  if (!ready) return null;
  const W = 1024;
  const H = 500;
  // The word, and the mark sized against it as the launch sizes it.
  const SIZE = 96;
  const TRACK = SIZE * 0.05;
  const m = SIZE * (112 / 60);
  const g = markOf(m);
  const space = SIZE * (20 / 60);
  const cap = 0.727 * SIZE;
  const studioGap = 34;
  const studio = 22;
  const subGap = 22;
  const sub = 25;
  const block = g.upHeight + space + cap + studioGap + studio + subGap + sub;
  const top = (H - block) / 2 - 6;
  // Placed so the ink's top is [top]: the climbing mark's ink runs from a
  // half-gap and a lean above cy to a half-gap below it, plus the round ends.
  const markCy = top + g.stroke / 2 + g.lean + g.gap / 2;
  const capTop = top + g.upHeight + space;
  const capMid = capTop + cap / 2;
  const studioTop = capTop + cap + studioGap;
  const subTop = studioTop + studio + subGap;
  const cx = W / 2;
  const air = [
    {x: -168, y: -40, len: 110, o: 0.2},
    {x: 196, y: -70, len: 150, o: 0.12},
    {x: -232, y: -96, len: 80, o: 0.16},
    {x: 262, y: 10, len: 96, o: 0.1},
    {x: 300, y: -120, len: 60, o: 0.15},
    {x: -296, y: 20, len: 50, o: 0.11},
  ];
  return (
    <AbsoluteFill style={{background: C.bg, fontFamily: 'Inter', color: C.white}}>
      <Ground at="50% 4%" />
      <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} style={{position: 'absolute', inset: 0}}>
        {air.map((l, i) => (
          <line
            key={i}
            x1={cx + l.x}
            x2={cx + l.x}
            y1={H / 2 + l.y}
            y2={H / 2 + l.y + l.len}
            stroke={C.white}
            strokeWidth={2.4}
            strokeLinecap="round"
            opacity={l.o}
          />
        ))}
        <Mark cx={cx} cy={markCy} m={m} up />
      </svg>
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          // Inter's capitals are centred 0.61 of the size below the top of a
          // 1.22 line, so this puts their middle on capMid.
          top: capMid - SIZE * 0.61,
          textAlign: 'center',
          fontWeight: 800,
          fontSize: SIZE,
          lineHeight: 1.22,
          letterSpacing: TRACK,
          paddingLeft: TRACK,
          whiteSpace: 'nowrap',
          willChange: 'transform',
        }}
      >
        LIFT
      </div>
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top: studioTop,
          textAlign: 'center',
          fontWeight: 600,
          fontSize: studio,
          lineHeight: 1,
          letterSpacing: 9.2,
          paddingLeft: 9.2,
          color: C.dim,
          willChange: 'transform',
        }}
      >
        MGKFITNESS
      </div>
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top: subTop,
          textAlign: 'center',
          fontWeight: 500,
          fontSize: sub,
          lineHeight: 1,
          letterSpacing: 0.2,
          color: C.silver,
          willChange: 'transform',
        }}
      >
        Log every set. Get a real plan.
      </div>
    </AbsoluteFill>
  );
};
