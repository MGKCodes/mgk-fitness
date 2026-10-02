import React from 'react';
import {AbsoluteFill} from 'remotion';
import {C, Ground, Mark, markOf, useFonts, widthOf} from './kit';

/**
 * Google Play's feature graphic, 1024x500: the launch animation's last frame,
 * `RUN »`, on the app's ground.
 *
 * Play crops it and lays a play button over the middle of it in places, so
 * nothing that matters is within about 80 px of an edge and the lockup sits a
 * little above centre.
 */
export const Feature: React.FC = () => {
  const ready = useFonts();
  if (!ready) return null;
  const W = 1024;
  const H = 500;
  const SIZE = 148;
  const TRACK = SIZE * 0.05;
  const wordW = widthOf('RUN', SIZE, '800', TRACK) - TRACK;
  const m = SIZE * (92 / 60);
  const g = markOf(m);
  const space = SIZE * (13 / 60);
  const lockW = wordW + space + g.width;
  const left = (W - lockW) / 2;
  const cy = H / 2 - 26;
  const lines = [
    {y: -112, x: 96, len: 150, o: 0.18},
    {y: -70, x: 20, len: 210, o: 0.1},
    {y: 78, x: 60, len: 120, o: 0.16},
    {y: 118, x: 150, len: 230, o: 0.09},
    {y: -128, x: 770, len: 120, o: 0.12},
    {y: 96, x: 810, len: 170, o: 0.14},
    {y: 140, x: 700, len: 90, o: 0.1},
  ];
  return (
    <AbsoluteFill style={{background: C.bg, fontFamily: 'Inter', color: C.white}}>
      <Ground at="78% 30%" />
      <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} style={{position: 'absolute', inset: 0}}>
        {lines.map((l, i) => (
          <line
            key={i}
            x1={l.x}
            x2={l.x + l.len}
            y1={cy + l.y}
            y2={cy + l.y}
            stroke={C.white}
            strokeWidth={2.4}
            strokeLinecap="round"
            opacity={l.o}
          />
        ))}
        <Mark cx={left + wordW + space + g.width / 2} cy={cy} m={m} />
      </svg>
      <div
        style={{
          position: 'absolute',
          left,
          top: cy - SIZE * 0.61,
          fontWeight: 800,
          fontSize: SIZE,
          lineHeight: 1.22,
          letterSpacing: TRACK,
          whiteSpace: 'nowrap',
          willChange: 'transform',
        }}
      >
        RUN
      </div>
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top: cy + SIZE * 0.78,
          textAlign: 'center',
          fontWeight: 600,
          fontSize: 22,
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
          top: cy + SIZE * 0.78 + 50,
          textAlign: 'center',
          fontWeight: 500,
          fontSize: 25,
          letterSpacing: 0.2,
          color: C.silver,
          willChange: 'transform',
        }}
      >
        Track runs. Get a real plan.
      </div>
    </AbsoluteFill>
  );
};
