import React from 'react';
import {AbsoluteFill} from 'remotion';
import {Device, Kind, Screen, frameOf} from './Device';
import {C, Ground, Mark, widthOf} from './kit';
import {Shot} from './shots';

type Props = {shot: Shot; kind: Kind; width: number; height: number; time: string};

const src = (kind: Kind, shot: Shot) => `screens/${kind}/${shot.screen}.png`;

/** The largest size, up to [base], at which both lines fit in [room]. */
const fit = (lines: string[], base: number, room: number): number => {
  const widest = Math.max(...lines.map((l) => widthOf(l, base, '800', -0.022 * base)));
  return widest <= room ? base : Math.floor((base * room) / widest);
};

const Tag: React.FC<{text: string; size: number; align: 'center' | 'left'}> = ({
  text,
  size,
  align,
}) => (
  <div
    style={{
      fontWeight: 700,
      fontSize: size,
      lineHeight: 1,
      // An empty tag keeps its line, so the headline under it does not move.
      minHeight: size,
      letterSpacing: size * 0.22,
      // Tracking is added after each letter; this takes the last one's back
      // off so a centred line is centred on its ink.
      paddingLeft: align === 'center' ? size * 0.22 : 0,
      textTransform: 'uppercase',
      textAlign: align,
      color: C.dim,
      willChange: 'transform',
    }}
  >
    {text}
  </div>
);

const Headline: React.FC<{lines: [string, string]; size: number; align: 'center' | 'left'}> = ({
  lines,
  size,
  align,
}) => (
  <div
    style={{
      fontWeight: 800,
      fontSize: size,
      lineHeight: 1.06,
      letterSpacing: -0.022 * size,
      textAlign: align,
      whiteSpace: 'nowrap',
      // A layer of its own, so Windows sets it with grey edges and not the
      // coloured sub-pixel fringe it gives text on an opaque ground.
      willChange: 'transform',
    }}
  >
    <div style={{color: C.white}}>{lines[0]}</div>
    <div style={{color: C.silver}}>{lines[1]}</div>
  </div>
);

/**
 * A · Still.
 *
 * The words centred, the whole phone under them, nothing else. The one that
 * looks like the app: quiet, and all of the screen is in the picture.
 */
export const Still: React.FC<Props> = ({shot, kind, width, height, time}) => {
  const tag = Math.round(width * 0.0235);
  const size = fit(shot.lines, Math.round(width * 0.094), width * 0.86);
  const top = Math.round(height * 0.052);
  const wordsEnd = top + tag + Math.round(width * 0.036) + size * 1.06 * 2;
  const phoneTop = wordsEnd + Math.round(width * 0.062);
  const foot = Math.round(height * 0.03);
  // The frame is a fixed share taller than its screen is wide; solve for the
  // widest screen whose frame fits what is left.
  const unit = frameOf(kind, 1000);
  const screenWidth = Math.min(
    width * 0.8,
    ((height - phoneTop - foot) / unit.height) * 1000,
  );
  const f = frameOf(kind, screenWidth);
  return (
    <AbsoluteFill style={{background: C.bg, fontFamily: 'Inter'}}>
      <Ground at="50% 0%" />
      <div style={{position: 'absolute', left: 0, right: 0, top}}>
        <Tag text={shot.tag} size={tag} align="center" />
        <div style={{height: Math.round(width * 0.036)}} />
        <Headline lines={shot.lines} size={size} align="center" />
      </div>
      <div style={{position: 'absolute', left: (width - f.width) / 2, top: phoneTop}}>
        <Device kind={kind} src={src(kind, shot)} screenWidth={screenWidth} time={time} />
      </div>
    </AbsoluteFill>
  );
};

/**
 * B · Slipstream.
 *
 * The launch animation's picture, held still: the mark behind, the air going
 * past beside the tag, the words set hard left and large. The phone is bigger and runs off
 * the bottom, so the screen reads from further away and its last row is lost.
 */
export const Slipstream: React.FC<Props & {index: number}> = ({
  shot,
  kind,
  width,
  height,
  time,
  index,
}) => {
  const margin = Math.round(width * 0.074);
  const tag = Math.round(width * 0.0235);
  const size = fit(shot.lines, Math.round(width * 0.104), width - margin * 2);
  const top = Math.round(height * 0.05);
  const wordsEnd = top + tag + Math.round(width * 0.036) + size * 1.06 * 2;
  const phoneTop = wordsEnd + Math.round(width * 0.07);
  const screenWidth = width * 0.84;
  const f = frameOf(kind, screenWidth);
  const left = (width - f.width) / 2;
  // The air going past, up beside the tag: three streaks, set a little
  // differently on each picture so six in a row do not repeat.
  const streaks = [
    {x: 0.6, len: 0.2, dy: -0.013, o: 0.22},
    {x: 0.73, len: 0.2, dy: 0.005, o: 0.13},
    {x: 0.5, len: 0.13, dy: 0.023, o: 0.17},
  ].map((s, i) => {
    const shift = (((index * 31 + i * 17) % 11) - 5) / 100;
    return {
      x: width * (s.x + shift),
      len: width * s.len,
      y: top + tag / 2 + width * s.dy,
      o: s.o,
    };
  });
  return (
    <AbsoluteFill style={{background: C.bg, fontFamily: 'Inter'}}>
      <Ground at="82% 12%" />
      <svg
        width={width}
        height={height}
        viewBox={`0 0 ${width} ${height}`}
        style={{position: 'absolute', inset: 0}}
      >
        <Mark
          cx={width * 0.74}
          cy={top + tag + size * 1.1}
          m={width * 0.92}
          trailing={C.lift}
          leading={C.lift}
          opacity={0.42}
        />
        {streaks.map((l, i) => (
          <line
            key={i}
            x1={l.x}
            x2={Math.min(l.x + l.len, width - margin)}
            y1={l.y}
            y2={l.y}
            stroke={C.white}
            strokeWidth={width * 0.0028}
            strokeLinecap="round"
            opacity={l.o}
          />
        ))}
      </svg>
      <div style={{position: 'absolute', left: margin, top}}>
        <Tag text={shot.tag} size={tag} align="left" />
        <div style={{height: Math.round(width * 0.036)}} />
        <Headline lines={shot.lines} size={size} align="left" />
      </div>
      <div style={{position: 'absolute', left, top: phoneTop}}>
        <Device kind={kind} src={src(kind, shot)} screenWidth={screenWidth} time={time} />
      </div>
    </AbsoluteFill>
  );
};

/**
 * C · Plain.
 *
 * The screen and nothing else: what a screenshot taken on the phone looks
 * like. No words, so nothing says which half is free.
 */
export const Plain: React.FC<Props> = ({shot, kind, width, time}) => (
  <AbsoluteFill style={{background: C.bg, fontFamily: 'Inter'}}>
    <Screen kind={kind} src={src(kind, shot)} width={width} time={time} island={false} radius={0} />
  </AbsoluteFill>
);
