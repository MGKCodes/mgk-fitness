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
 * The launch, looped: what Lift plays when it opens, on the header, as Run's
 * header plays Slipstream. Ported beat for beat from
 * lib/src/core/launch/launch_curtain.dart (LaunchTimeline, LaunchMarkPainter):
 * the mark stands, dips and draws in on itself (0.2 to 0.56 s), drives up
 * (to 1.02 s), and LIFT rises from under its own baseline a beat behind it
 * while the air falls past either side; MGKFITNESS comes in from 1.0 s. All
 * of it is in the painter's points, multiplied by [K].
 *
 * Started 0.4 s in, so the first frame holds. Then it rests, with the air
 * falling now and again, and before the fifteen seconds are out the lockup
 * fades and the big mark comes back to the middle, which is the first frame,
 * so the loop has no jump. The curtain lift is left out: there is no app
 * underneath to uncover.
 */
export const HeaderLaunch: React.FC = () => {
  const ready = useFonts();
  const frame = useCurrentFrame();
  if (!ready) return null;
  const t = frame / FPS;
  const s = t - 0.4;
  // Sized for a phone, where the whole header can be shown at a few hundred
  // points wide: as large as the stack goes with every part of it, mark to
  // line, still inside the safe box. The gaps under the word are tighter than
  // the launch's, which has a whole phone screen to sit in.
  const K = 3.9;
  const cx = W / 2;
  const out = Easing.bezier(0.16, 1, 0.3, 1);
  const inOut = Easing.bezier(0.65, 0, 0.35, 1);
  const seg = (x: number, a: number, b: number, curve: (n: number) => number = inOut) =>
    interpolate(x, [a, b], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: curve});
  const lerp = (a: number, b: number, p: number) => a + (b - a) * p;
  const inkHeight = (m: number) => {
    const g = markOf(m);
    return g.gap + g.lean + g.stroke;
  };

  // The lockup, as the painter lays it out: mark, a space, the word under it.
  const SIZE = 60 * K;
  const TRACK = 3 * K;
  const cap = 0.727 * SIZE;
  const small = 112 * K;
  const big = 150 * K;
  const markH = inkHeight(small);
  const space = 20 * K;
  const caption = 10 * K;
  const captionGap = 14 * K;
  const line = 66;
  const lineGap = 36;
  // Centred so the whole block, mark to the line under it, sits in the safe box.
  const lockH = markH + space + cap;
  const blockH = lockH + captionGap + caption + lineGap + line;
  const top = safe.y + (safe.h - blockH) / 2;
  const cy = top + lockH / 2;
  const home = top + markH / 2;
  const baselineY = top + lockH;

  // The three beats.
  const dip = seg(s, 0.2, 0.56);
  const drive = seg(s, 0.56, 1.02, out);
  const m = lerp(big, small, dip);
  const low = cy + 30 * K;
  const up = (amount: number) => lerp(low, home, amount);
  const markY = drive > 0 ? up(drive) : lerp(cy, low, dip);
  const spread = lerp(lerp(1, 0.72, dip), 1, seg(s, 0.56, 0.9, out));
  const before = up(seg(s, 0.59, 1.05, out));
  const speed = Math.abs(up(drive) - before);

  // The word, rising a beat behind the mark. Nothing before the drive.
  const risen = seg(s, 0.62, 1.1, out);
  const named = seg(s, 1.0, 1.4, out);
  const lined = seg(s, 1.3, 1.8, out);

  // The end: the lockup fades, then the big mark returns to the middle.
  const gone = seg(t, FILM_SECONDS - 1.4, FILM_SECONDS - 0.8);
  const back = seg(t, FILM_SECONDS - 0.8, FILM_SECONDS - 1 / FPS);
  const ending = t > FILM_SECONDS - 1.4;

  // The air: the launch's six lines once, then a few every so often, falling
  // slowly enough to follow. Lanes either side of the name, never across it.
  const launchAir = [
    {x: -96, len: 54, at: 0.58, o: 0.22},
    {x: 104, len: 96, at: 0.63, o: 0.14},
    {x: -128, len: 72, at: 0.6, o: 0.2},
    {x: 136, len: 120, at: 0.66, o: 0.12},
    {x: 160, len: 40, at: 0.7, o: 0.18},
    {x: -156, len: 30, at: 0.72, o: 0.14},
  ].map((l) => ({...l, dur: 0.42, curve: out}));
  const lanes = [-112, 148, -236, 288, -300, 210];
  const laterAir = [3.2, 5.9, 8.4, 10.8].flatMap((at, j) =>
    lanes.slice(j % 3, (j % 3) + 2 + (j % 2)).map((x, i) => ({
      x,
      len: 50 + 30 * ((i + j) % 3),
      at: at + i * 0.35,
      o: 0.1 + 0.03 * ((i + j) % 2),
      dur: 1.5,
      curve: Easing.linear,
    })),
  );
  const air = [...launchAir, ...laterAir].map((l, i) => {
    const p = seg(s, l.at, l.at + l.dur, Easing.linear);
    if (p <= 0 || p >= 1) return null;
    const y = lerp(cy - 200 * K, cy + 170 * K, l.curve(p));
    const fade = Math.sin(Math.PI * p);
    const x = cx + l.x * K;
    return (
      <line
        key={i}
        x1={x}
        x2={x}
        y1={y}
        y2={y - l.len * K * (0.4 + 0.6 * fade)}
        stroke={C.white}
        strokeWidth={1.25 * K}
        strokeLinecap="round"
        opacity={l.o * fade * (1 - gone)}
      />
    );
  });

  // The two chevrons, their ink centred on (x, y), drawn in by [sp].
  const LaunchMark: React.FC<{y: number; size: number; sp: number; opacity: number}> = ({y, size, sp, opacity}) => {
    const g = markOf(size);
    const gap = g.gap * sp;
    const base = y + g.lean / 2;
    return (
      <g opacity={opacity}>
        {[0, 1].map((i) => {
          const yy = base + gap / 2 - i * gap;
          return (
            <polyline
              key={i}
              points={`${cx - g.half},${yy} ${cx},${yy - g.lean} ${cx + g.half},${yy}`}
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

  // Inter's alphabetic baseline sits 0.974 of the size below the top of a 1.22 line.
  const baseline = 0.974 * SIZE;
  const wordTop = baselineY - baseline;
  const glow = lerp(seg(s, 0.4, 1.1, out), 0, back);

  return (
    <AbsoluteFill style={{background: C.bg, fontFamily: 'Inter', color: C.white}}>
      <div
        style={{
          position: 'absolute',
          inset: 0,
          opacity: glow,
          background: 'radial-gradient(115% 62% at 50% 16%, rgba(58,58,58,0.55) 0%, rgba(58,58,58,0) 62%)',
        }}
      />
      <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} style={{position: 'absolute', inset: 0}}>
        {air}
      </svg>
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top: wordTop,
          // The floor it comes up through: just under the baseline.
          height: baseline + 1.5 * K,
          overflow: 'hidden',
          opacity: 1 - gone,
        }}
      >
        <div
          style={{
            transform: `translateY(${(1 - risen) * (cap + 6 * K)}px)`,
            textAlign: 'center',
            fontWeight: 800,
            fontSize: SIZE,
            lineHeight: 1.22,
            letterSpacing: TRACK,
            paddingLeft: TRACK,
            whiteSpace: 'nowrap',
            visibility: risen > 0 ? 'visible' : 'hidden',
            willChange: 'transform',
          }}
        >
          {WORDS.name}
        </div>
      </div>
      <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} style={{position: 'absolute', inset: 0}}>
        {!ending
          ? [3, 2, 1].map((ghost) => {
              const o = Math.min(0.28, speed / (36 * K)) / ghost;
              return o < 0.004 ? null : (
                <LaunchMark key={ghost} y={markY + speed * ghost * 0.9} size={m} sp={spread} opacity={o} />
              );
            })
          : null}
        {!ending ? <LaunchMark y={markY} size={m} sp={spread} opacity={1} /> : null}
        {ending ? (
          <>
            <LaunchMark y={home} size={small} sp={1} opacity={1 - gone} />
            <LaunchMark y={cy} size={big} sp={1} opacity={back} />
          </>
        ) : null}
      </svg>
      <Centred
        top={baselineY + captionGap + lerp(6 * K, 0, named)}
        size={caption}
        weight={600}
        track={4.2 * K}
        color={APP.textSecondary}
      >
        <span style={{opacity: 0.88 * named * (1 - gone)}}>{WORDS.suite}</span>
      </Centred>
      <Centred top={baselineY + captionGap + caption + lineGap} size={line} weight={500} track={0.4} color={C.silver}>
        <span style={{opacity: lined * (1 - gone)}}>{WORDS.line}</span>
      </Centred>
    </AbsoluteFill>
  );
};

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
