import React from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame} from 'remotion';
import {Air} from './Air';
import {C, Ground, Mark, markOf, useFonts, widthOf} from './kit';
import {APP, FILM_SECONDS, FPS, SPEC} from './spec';
import {WORDS} from './words';

const {w: W, h: H, safe} = SPEC.header;

/**
 * A · The name. The launch's last frame, which is also Play's feature graphic:
 * the mark at rest above LIFT, the suite under it, and one line, on the app's
 * ground with the air falling past either side. Everything that reads sits in
 * Apple's safe box; the air fills the width that only a wide screen shows.
 *
 * Proportions are the feature graphic's (store-shots/src/Feature.tsx), scaled:
 * the mark is sized against the word as the launch sizes it.
 */
export const HeaderName: React.FC = () => {
  const ready = useFonts();
  if (!ready) return null;
  const SIZE = 190;
  const k = SIZE / 96;
  const TRACK = SIZE * 0.05;
  const m = SIZE * (112 / 60);
  const g = markOf(m);
  const space = SIZE * (20 / 60);
  const cap = 0.727 * SIZE;
  const suiteGap = 34 * k;
  const suite = 22 * k;
  const lineGap = 26 * k;
  const line = 25 * k;
  const block = g.upHeight + space + cap + suiteGap + suite + lineGap + line;
  const top = safe.y + (safe.h - block) / 2;
  const markCy = top + g.stroke / 2 + g.lean + g.gap / 2;
  const capTop = top + g.upHeight + space;
  const capMid = capTop + cap / 2;
  const suiteTop = capTop + cap + suiteGap;
  const lineTop = suiteTop + suite + lineGap;
  const cx = W / 2;
  const nameW = widthOf(WORDS.name, SIZE, '800', TRACK);
  return (
    <AbsoluteFill style={{background: C.bg, fontFamily: 'Inter', color: C.white}}>
      <Ground at="50% 18%" />
      <Air
        width={W}
        height={H}
        clear={Math.max(nameW, widthOf(WORDS.line, line, '500')) / 2 + 150}
        top={safe.y - 120}
        bottom={safe.y + safe.h + 120}
        stroke={2.4 * k}
      />
      <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} style={{position: 'absolute', inset: 0}}>
        <Mark cx={cx} cy={markCy} m={m} up />
      </svg>
      <Centred top={capMid - SIZE * 0.61} size={SIZE} weight={800} track={TRACK} lineHeight={1.22}>
        {WORDS.name}
      </Centred>
      <Centred top={suiteTop} size={suite} weight={600} track={9.2 * k} color={C.dim}>
        {WORDS.suite}
      </Centred>
      <Centred top={lineTop} size={line} weight={500} track={0.2 * k} color={C.silver}>
        {WORDS.line}
      </Centred>
    </AbsoluteFill>
  );
};

const Centred: React.FC<{
  top: number;
  size: number;
  weight: number;
  track: number;
  color?: string;
  lineHeight?: number;
  children: React.ReactNode;
}> = ({top, size, weight, track, color = C.white, lineHeight = 1, children}) => (
  <div
    style={{
      position: 'absolute',
      left: 0,
      right: 0,
      top,
      textAlign: 'center',
      fontWeight: weight,
      fontSize: size,
      lineHeight,
      letterSpacing: track,
      // Tracking is added after every letter, the last one too; this puts the
      // line's ink, not its box, on the centre.
      paddingLeft: track,
      color,
      whiteSpace: 'nowrap',
      // Its own layer, so Windows gives it grey edges rather than colour fringes.
      willChange: 'transform',
    }}
  >
    {children}
  </div>
);

/**
 * B · Between sets. The rest dock at the foot of a session, at poster size,
 * running in real time: RESTING with the last ten seconds going, the ring
 * emptying, then REST OVER in the app's green and the clock counting on past
 * zero, which is what the app does (active_session_screen.dart, `_RestRow`:
 * "Past zero it counts up: how long the lifter has actually rested").
 *
 * Nothing is sped up. The rest is 1:30, as on the session screen in the store
 * pictures, so the ring is nearly empty when the film joins it. Fifteen
 * seconds, then a half-second fade back to the start, so the loop has no jump.
 */
export const HeaderBetweenSets: React.FC = () => {
  const ready = useFonts();
  const frame = useCurrentFrame();
  if (!ready) return null;
  const t = frame / FPS;
  const REST = 90;
  // Joined with ten seconds and a bit to go, so 0:10 is on screen a whole
  // second, the way RestTimer.format floors it.
  const LEFT_AT_START = 10.99;
  const remaining = LEFT_AT_START - t;
  const done = remaining <= 0;
  const fmt = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
  const clock = done ? `+${fmt(-remaining)}` : fmt(remaining);
  const left = Math.max(0, remaining / REST);

  // Back to the first frame: the end goes, then the start comes, one after
  // the other. A crossfade laid 0:10 over +0:03 for a third of a second.
  const fade = (a: number, b: number) =>
    interpolate(t, [a, b], [0, 1], {
      extrapolateLeft: 'clamp',
      extrapolateRight: 'clamp',
      easing: Easing.inOut(Easing.ease),
    });
  const loopOut = 1 - fade(FILM_SECONDS - 0.75, FILM_SECONDS - 0.4);
  const loopIn = fade(FILM_SECONDS - 0.4, FILM_SECONDS - 1 / FPS);

  const DIGITS = 330;
  const LABEL = 62;
  const RING = 360;
  const STROKE = RING * (3 / 36);
  const gap = 90;
  // Laid out for the widest the clock gets, so nothing shifts when the plus arrives.
  const widest = widthOf('+0:00', DIGITS, '700');
  const rowW = RING + gap + widest;
  const lineSize = 54;
  const lineGap = 70;
  const rowH = RING;
  const blockH = rowH + lineGap + lineSize;
  const top = safe.y + (safe.h - blockH) / 2;
  const left0 = (W - rowW) / 2;
  const r = (RING - STROKE) / 2;
  const ringCx = left0 + RING / 2;
  const ringCy = top + RING / 2;
  // CircularProgressIndicator draws from twelve o'clock, clockwise.
  const arc = (frac: number) => {
    if (frac <= 0) return '';
    const a = -Math.PI / 2 + 2 * Math.PI * Math.min(frac, 0.9999);
    const x = ringCx + r * Math.cos(a);
    const y = ringCy + r * Math.sin(a);
    return `M ${ringCx} ${ringCy - r} A ${r} ${r} 0 ${frac > 0.5 ? 1 : 0} 1 ${x} ${y}`;
  };
  const labelColor = done ? APP.success : APP.textSecondary;
  const textX = left0 + RING + gap;
  // The label sits over the clock, as in the dock: a SectionLabel, uppercase, bold.
  const digitsCap = 0.727 * DIGITS;
  const columnH = LABEL + 34 + digitsCap;
  const columnTop = ringCy - columnH / 2;

  // Draws one state of the dock; the loop fades the end into the start.
  const Dock: React.FC<{opacity: number; state: 'live' | 'start'}> = ({opacity, state}) => {
    const isStart = state === 'start';
    const c = isStart ? fmt(LEFT_AT_START) : clock;
    const l = isStart ? LEFT_AT_START / REST : left;
    const lab = isStart ? 'Resting' : done ? 'Rest over' : 'Resting';
    const col = isStart ? APP.textSecondary : labelColor;
    return (
      <div style={{position: 'absolute', inset: 0, opacity}}>
        <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} style={{position: 'absolute', inset: 0}}>
          <circle cx={ringCx} cy={ringCy} r={r} fill="none" stroke={C.white} strokeOpacity={0.1} strokeWidth={STROKE} />
          {/* Past zero the ring is empty, as the app's is: only the label turns green. */}
          <path d={arc(l)} fill="none" stroke={C.white} strokeWidth={STROKE} strokeLinecap="butt" />
        </svg>
        <div
          style={{
            position: 'absolute',
            left: textX,
            top: columnTop,
            fontWeight: 700,
            fontSize: LABEL,
            lineHeight: 1,
            letterSpacing: LABEL * 0.12,
            textTransform: 'uppercase',
            color: col,
            whiteSpace: 'nowrap',
            willChange: 'transform',
          }}
        >
          {lab}
        </div>
        <div
          style={{
            position: 'absolute',
            left: textX - DIGITS * 0.04,
            // Inter's figures are centred 0.61 of the size below the top of a 1.22 line.
            top: columnTop + LABEL + 34 + digitsCap / 2 - DIGITS * 0.61,
            fontWeight: 700,
            fontSize: DIGITS,
            lineHeight: 1.22,
            letterSpacing: -0.01 * DIGITS,
            fontVariantNumeric: 'tabular-nums',
            color: C.white,
            whiteSpace: 'nowrap',
            willChange: 'transform',
          }}
        >
          {c}
        </div>
      </div>
    );
  };

  return (
    <AbsoluteFill style={{background: C.bg, fontFamily: 'Inter', color: C.white}}>
      <Ground at="50% 30%" />
      <Dock opacity={loopOut} state="live" />
      <Dock opacity={loopIn} state="start" />
      <Centred top={top + rowH + lineGap} size={lineSize} weight={500} track={0.4} color={C.silver}>
        {WORDS.line}
      </Centred>
    </AbsoluteFill>
  );
};
