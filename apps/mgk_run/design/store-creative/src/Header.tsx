import React from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame} from 'remotion';
import {C, Ground, Mark, markOf, useFonts, widthOf} from './kit';
import {FILM_SECONDS, FPS, SPEC} from './spec';
import {WORDS} from './words';

const {w: W, h: H, safe} = SPEC.header;

/** 0 before [a], 1 after [b], eased between. */
const seg = (t: number, a: number, b: number, easing: (n: number) => number) =>
  interpolate(t, [a, b], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing});
const lerp = (a: number, b: number, p: number) => a + (b - a) * p;
/** launch-films/src/kit.tsx's curves, the ones the app's launch is timed to. */
const E = {
  out: Easing.bezier(0.16, 1, 0.3, 1),
  inOut: Easing.bezier(0.65, 0, 0.35, 1),
  linear: Easing.linear,
};

/**
 * The lockup at rest, `RUN »`, in Slipstream's proportions (launch-films,
 * chosen 2026-10-01, rebuilt in lib/src/core/launch/launch_curtain.dart): the
 * word at 60, the mark at 92 sitting 13 after it, MGKFITNESS at 10 under. All
 * in points, multiplied by [k] here to fill Apple's safe box.
 */
// Sized for a phone, where the whole header can be shown at a few hundred
// points wide: the lockup and its line fill the safe box. MGKFITNESS sits 38
// points under the name's centre line here, not the launch's 46, so the line
// under it still fits inside the box.
const K = 7.0;
const CAPTION_DROP = 38;
const lockup = () => {
  const SIZE = 60 * K;
  const TRACK = 3 * K;
  const wordW = widthOf(WORDS.name, SIZE, '800', TRACK) - TRACK;
  const small = 92 * K;
  const g = markOf(small);
  const space = 13 * K;
  const lockW = wordW + space + g.width;
  const left = (W - lockW) / 2;
  const caption = 10 * K;
  const line = 68;
  const lineGap = 50;
  // Centre the whole block, the capitals' top to the line's foot, on the safe box.
  const halfCap = (0.727 * SIZE) / 2;
  const blockH = halfCap + CAPTION_DROP * K + caption + lineGap + line;
  const cy = safe.y + (safe.h - blockH) / 2 + halfCap;
  return {SIZE, TRACK, wordW, small, g, space, left, markHome: left + wordW + space + g.width / 2, cy, caption, line, lineGap};
};

/**
 * Air going past: horizontal, as Run's mark travels, above and below the name.
 * `y` is a share of [AIR_BAND], so the lines keep close to the lockup rather
 * than out at the canvas edge.
 */
const AIR_BAND = 900;
const AIR = [
  {y: -0.34, x: 0.1, len: 0.09, o: 0.16},
  {y: -0.27, x: 0.21, len: 0.14, o: 0.1},
  {y: 0.3, x: 0.06, len: 0.11, o: 0.14},
  {y: 0.39, x: 0.17, len: 0.06, o: 0.1},
  {y: -0.38, x: 0.72, len: 0.08, o: 0.12},
  {y: 0.33, x: 0.75, len: 0.13, o: 0.13},
  {y: 0.44, x: 0.74, len: 0.05, o: 0.09},
  {y: -0.3, x: 0.86, len: 0.06, o: 0.1},
];

const Words: React.FC<{cy: number; opacity?: number; reveal?: number}> = ({cy, opacity = 1, reveal}) => {
  const L = lockup();
  return (
    <>
      <div
        style={{
          position: 'absolute',
          left: L.left,
          top: cy - L.SIZE * 0.61,
          width: reveal ?? L.wordW + L.TRACK,
          height: L.SIZE * 1.22,
          overflow: 'hidden',
          opacity,
        }}
      >
        <div
          style={{
            fontWeight: 800,
            fontSize: L.SIZE,
            lineHeight: 1.22,
            letterSpacing: L.TRACK,
            whiteSpace: 'nowrap',
            willChange: 'transform',
          }}
        >
          {WORDS.name}
        </div>
      </div>
    </>
  );
};

const Under: React.FC<{cy: number; caption: number; line: number}> = ({cy, caption, line}) => {
  const L = lockup();
  // Slipstream's Caption sits 46 points under the name's centre line; here 38.
  const top = cy + CAPTION_DROP * K;
  return (
    <>
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top,
          textAlign: 'center',
          fontWeight: 600,
          fontSize: L.caption,
          lineHeight: 1,
          letterSpacing: 4.2 * K,
          paddingLeft: 4.2 * K,
          color: C.dim,
          opacity: caption,
          willChange: 'transform',
        }}
      >
        {WORDS.suite}
      </div>
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top: top + L.caption + L.lineGap,
          textAlign: 'center',
          fontWeight: 500,
          fontSize: L.line,
          lineHeight: 1,
          letterSpacing: 0.4,
          color: C.silver,
          opacity: line,
          willChange: 'transform',
        }}
      >
        {WORDS.line}
      </div>
    </>
  );
};

/**
 * A · The name. Slipstream's last frame, which is also Play's feature graphic:
 * `RUN »` at rest on the app's ground, the air going past above and below it,
 * MGKFITNESS and one line under. What reads is inside Apple's safe box; the
 * air fills the width only a wide screen shows.
 */
export const HeaderName: React.FC = () => {
  const ready = useFonts();
  if (!ready) return null;
  const L = lockup();
  return (
    <AbsoluteFill style={{background: C.bg, fontFamily: 'Inter', color: C.white}}>
      <Ground at="62% 30%" />
      <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} style={{position: 'absolute', inset: 0}}>
        {AIR.map((l, i) => (
          <line
            key={i}
            x1={l.x * W}
            x2={(l.x + l.len) * W}
            y1={L.cy + l.y * AIR_BAND}
            y2={L.cy + l.y * AIR_BAND}
            stroke={C.white}
            strokeWidth={2.4 * (K / 2)}
            strokeLinecap="round"
            opacity={l.o}
          />
        ))}
        <Mark cx={L.markHome} cy={L.cy} m={L.small} />
      </svg>
      <Words cy={L.cy} />
      <Under cy={L.cy} caption={1} line={1} />
    </AbsoluteFill>
  );
};

/**
 * B · Slipstream, looped. The launch Run opens with, on the header: the mark
 * winds back, then goes, uncovering the name, and rests as `RUN »`. Same
 * beats and curves as launch-films/src/Slipstream.tsx (0.2 to 0.56 s back,
 * 0.56 to 1.02 s the dash), started 0.4 s in so the first frame holds.
 *
 * Then it rests, with the air going past now and again, slow enough to
 * follow. Before the fifteen seconds are out the lockup fades and the big mark
 * comes back to the middle, which is the first frame, so the loop has no jump.
 */
export const HeaderSlipstream: React.FC = () => {
  const ready = useFonts();
  const frame = useCurrentFrame();
  if (!ready) return null;
  const L = lockup();
  const t = frame / FPS;
  const s = t - 0.4;
  const cy = L.cy;

  const back = seg(s, 0.2, 0.56, E.inOut);
  const dash = seg(s, 0.56, 1.02, E.out);
  const big = 130 * K;
  const m = lerp(big, L.small, back);
  const crouch = L.left - 6 * K + markOf(L.small).width / 2;
  const cx = lerp(lerp(W / 2, crouch, back), L.markHome, dash);
  const spread = lerp(lerp(1, 0.78, back), 1, seg(s, 0.56, 0.9, E.out));
  const trailingEdge = cx - markOf(m).width / 2 - 6 * K;
  const shown = dash <= 0 ? 0 : Math.max(0, Math.min(L.wordW + L.TRACK, trailingEdge - L.left));

  const speedAt = (x: number) => lerp(crouch, L.markHome, seg(x, 0.56, 1.02, E.out));
  const speed = Math.abs(speedAt(s) - speedAt(s - 0.03)) / K;
  const ghosts = [1, 2, 3].map((n) => ({dx: -speed * K * n * 0.55, o: Math.min(0.28, speed / 60) / n}));

  // The end: everything fades, then the big mark returns to the middle.
  const out = seg(t, FILM_SECONDS - 1.4, FILM_SECONDS - 0.8, E.inOut);
  const back2 = seg(t, FILM_SECONDS - 0.8, FILM_SECONDS - 1 / FPS, E.inOut);
  const ending = t > FILM_SECONDS - 1.4;

  // The air: the launch's six lines once, at the dash; then a few, every so
  // often, crossing the width in about a second and a half.
  const launchLines = [
    {y: -58, len: 54, at: 0.58, o: 0.22},
    {y: -31, len: 96, at: 0.63, o: 0.14},
    {y: 37, len: 72, at: 0.6, o: 0.2},
    {y: 61, len: 120, at: 0.66, o: 0.12},
    {y: 88, len: 40, at: 0.7, o: 0.18},
    {y: -84, len: 30, at: 0.72, o: 0.14},
  ].map((l) => ({...l, y: l.y * K, len: l.len * K, dur: 0.42}));
  const later = [3.2, 5.9, 8.4, 10.8].flatMap((at, j) =>
    // Above the name, or below the line under it: never across a word.
    [-0.36, 0.5, -0.28, 0.56].slice(0, 2 + (j % 2)).map((y, i) => ({
      y: y * AIR_BAND,
      len: (0.05 + 0.03 * ((i + j) % 3)) * W,
      at: at + i * 0.35,
      o: 0.1 + 0.03 * ((i + j) % 2),
      dur: 1.5,
    })),
  );
  const air = [...launchLines, ...later].map((l, i) => {
    const p = seg(s, l.at, l.at + l.dur, E.linear);
    if (p <= 0 || p >= 1) return null;
    const x = lerp(W * 0.92, W * 0.04, l.dur < 1 ? E.out(p) : p);
    const fade = Math.sin(Math.PI * p);
    return (
      <line
        key={i}
        x1={x}
        x2={x + l.len * (0.4 + 0.6 * fade)}
        y1={cy + l.y}
        y2={cy + l.y}
        stroke={C.white}
        strokeWidth={1.25 * K * 0.7}
        strokeLinecap="round"
        opacity={l.o * fade * (1 - out)}
      />
    );
  });

  return (
    <AbsoluteFill style={{background: C.bg, fontFamily: 'Inter', color: C.white}}>
      <Ground at="62% 30%" opacity={lerp(seg(s, 0.4, 1.1, E.out), 0, back2)} />
      <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} style={{position: 'absolute', inset: 0}}>
        {air}
      </svg>
      <Words cy={cy} reveal={shown} opacity={1 - out} />
      <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} style={{position: 'absolute', inset: 0}}>
        {!ending
          ? ghosts.map((gh, i) => (
              <g key={i} opacity={gh.o}>
                <SpreadMark cx={cx + gh.dx} cy={cy} m={m} spread={spread} />
              </g>
            ))
          : null}
        {!ending ? <SpreadMark cx={cx} cy={cy} m={m} spread={spread} /> : null}
        {ending ? (
          <>
            <g opacity={1 - out}>
              <SpreadMark cx={L.markHome} cy={cy} m={L.small} spread={1} />
            </g>
            <g opacity={back2}>
              <SpreadMark cx={W / 2} cy={cy} m={big} spread={1} />
            </g>
          </>
        ) : null}
      </svg>
      <Under
        cy={cy}
        caption={seg(s, 1.0, 1.4, E.out) * (1 - out)}
        line={seg(s, 1.3, 1.8, E.out) * (1 - out)}
      />
    </AbsoluteFill>
  );
};

/** The mark with launch-films' `spread`: the chevrons drawn in on each other as it winds back. */
const SpreadMark: React.FC<{cx: number; cy: number; m: number; spread: number}> = ({cx, cy, m, spread}) => {
  const g = markOf(m);
  const gap = g.gap * spread;
  return (
    <g>
      {[0, 1].map((i) => {
        const x = cx - gap / 2 - g.lean / 2 + i * gap;
        const y = cy + (g.rise * spread) / 2 - i * g.rise * spread;
        return (
          <polyline
            key={i}
            points={`${x},${y - g.half} ${x + g.lean},${y} ${x},${y + g.half}`}
            fill="none"
            stroke={i === 0 ? C.silver : C.white}
            strokeWidth={g.stroke}
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        );
      })}
    </g>
  );
};
