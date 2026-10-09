import React from 'react';
import {C} from './kit';

/**
 * The air the mark climbs through, as the feature graphic draws it: short
 * upright strokes, faint, falling past either side of the name and never
 * across it. Here there is far more width to fill, so the strokes are laid out
 * by a fixed seed rather than by hand: the same picture on every render.
 */
export const Air: React.FC<{
  width: number;
  height: number;
  /** Half the width of the column kept clear round the centre. */
  clear: number;
  /** The band the strokes stay in, top and bottom. */
  top: number;
  bottom: number;
  count?: number;
  /** Stroke width, in canvas pixels. */
  stroke?: number;
  seed?: number;
}> = ({width, height, clear, top, bottom, count = 34, stroke = 5, seed = 7}) => {
  let s = seed;
  const rand = () => {
    s = (s * 16807) % 2147483647;
    return (s - 1) / 2147483646;
  };
  const cx = width / 2;
  const reach = cx - clear;
  const lines = Array.from({length: count}, (_, i) => {
    const side = i % 2 === 0 ? -1 : 1;
    // Nearer the name, longer and brighter; out at the edge, barely there.
    const d = Math.pow(rand(), 0.8);
    const x = cx + side * (clear + d * reach * 0.94);
    const len = (0.16 + 0.22 * rand()) * (bottom - top) * (1 - 0.55 * d);
    const y = top + rand() * (bottom - top - len);
    const o = (0.08 + 0.16 * rand()) * (1 - 0.7 * d);
    return {x, y, len, o};
  });
  return (
    <svg
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      style={{position: 'absolute', inset: 0}}
    >
      {lines.map((l, i) => (
        <line
          key={i}
          x1={l.x}
          x2={l.x}
          y1={l.y}
          y2={l.y + l.len}
          stroke={C.white}
          strokeWidth={stroke}
          strokeLinecap="round"
          opacity={l.o}
        />
      ))}
    </svg>
  );
};
