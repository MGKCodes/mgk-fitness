import React, {useEffect, useState} from 'react';
import {
  AbsoluteFill,
  Easing,
  Img,
  continueRender,
  delayRender,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {loadFont} from '@remotion/fonts';
import {measureText} from '@remotion/layout-utils';

/** The phone every plate is drawn at, in points. The film is drawn at 2x. */
export const W = 393;
export const H = 852;
export const SCALE = 2;
export const FPS = 60;
export const SECONDS = 2.6;

/** AppColors, and the two greys the icon is drawn in. */
export const C = {
  bg: '#1A1A1A',
  lift: '#3A3A3A',
  silver: '#C0C0C0',
  white: '#FFFFFF',
  dim: '#8A8F98',
};

const faces: Array<[string, string]> = [
  ['Black', '900'],
  ['ExtraBold', '800'],
  ['Bold', '700'],
  ['SemiBold', '600'],
  ['Medium', '500'],
  ['Regular', '400'],
];

const fonts = Promise.all(
  faces.map(([name, weight]) =>
    loadFont({family: 'Inter', url: staticFile(`Inter-${name}.ttf`), weight}),
  ),
);

/** True once Inter is in, so nothing is measured or drawn in a fallback. */
export const useFonts = (): boolean => {
  const [ready, setReady] = useState(false);
  const [handle] = useState(() => delayRender('Inter'));
  useEffect(() => {
    fonts.then(() => {
      setReady(true);
      continueRender(handle);
    });
  }, [handle]);
  return ready;
};

/** Seconds since the first frame. */
export const useSeconds = (): number => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return frame / fps;
};

export const E = {
  /** Arrives fast and settles: content landing. */
  out: Easing.bezier(0.16, 1, 0.3, 1),
  /** Leaves slowly, then goes: content departing. */
  in: Easing.bezier(0.7, 0, 0.84, 0),
  /** Both ends soft: a move between two rests. */
  inOut: Easing.bezier(0.65, 0, 0.35, 1),
  /** Lands a little past and comes back. */
  back: Easing.bezier(0.34, 1.4, 0.64, 1),
  linear: Easing.linear,
};

/** 0 before [a], 1 after [b], eased between. */
export const seg = (
  t: number,
  a: number,
  b: number,
  easing: (n: number) => number = E.inOut,
): number =>
  interpolate(t, [a, b], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing,
  });

export const lerp = (a: number, b: number, p: number): number => a + (b - a) * p;

/** The width of [text] as Inter will set it. Call only once fonts are ready. */
export const widthOf = (
  text: string,
  fontSize: number,
  fontWeight: string,
  letterSpacing = 0,
): number =>
  measureText({
    text,
    fontFamily: 'Inter',
    fontSize,
    fontWeight,
    letterSpacing: `${letterSpacing}px`,
  }).width;

/** When the curtain starts to lift, and how long it takes. */
export const LIFT_AT = 1.62;
export const LIFT_FOR = 0.32;

/**
 * The phone: the app underneath, and the launch curtain over it, which lifts
 * at [LIFT_AT]. Children are drawn in points, on the curtain.
 */
export const Phone: React.FC<{children: React.ReactNode; ground?: React.ReactNode}> = ({
  children,
  ground,
}) => {
  const t = useSeconds();
  const lift = seg(t, LIFT_AT, LIFT_AT + LIFT_FOR, Easing.bezier(0.5, 0, 0.75, 0));
  return (
    <AbsoluteFill style={{background: C.bg}}>
      <div
        style={{
          width: W,
          height: H,
          transform: `scale(${SCALE})`,
          transformOrigin: '0 0',
          position: 'relative',
          overflow: 'hidden',
          fontFamily: 'Inter',
          color: C.white,
        }}
      >
        <Img
          src={staticFile('home.png')}
          style={{
            position: 'absolute',
            inset: 0,
            width: W,
            height: H,
            // The app settles as the curtain goes: it arrives, it is not cut to.
            transform: `scale(${lerp(1.035, 1, seg(t, LIFT_AT, LIFT_AT + LIFT_FOR + 0.25, E.out))})`,
          }}
        />
        <div
          style={{
            position: 'absolute',
            inset: 0,
            background: C.bg,
            opacity: 1 - lift,
          }}
        >
          {ground}
          <div
            style={{
              position: 'absolute',
              inset: 0,
              transform: `scale(${lerp(1, 1.06, lift)})`,
            }}
          >
            {children}
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

/** The icon's ground: one soft light from the mark's heading. */
export const Ground: React.FC<{opacity?: number}> = ({opacity = 1}) => (
  <div
    style={{
      position: 'absolute',
      inset: 0,
      opacity,
      background: `radial-gradient(120% 70% at 78% 30%, rgba(58,58,58,0.55) 0%, rgba(26,26,26,0) 62%)`,
    }}
  />
);

/** The mark's proportions at a canvas of [m], as tool/build_app_icons.py has them. */
export const markOf = (m: number) => {
  const w = 0.61 * m;
  return {
    stroke: 0.09 * m,
    half: 0.215 * w,
    lean: 0.2 * w,
    gap: 0.36 * w,
    rise: 0.215 * w,
    /** Ink bounds, for laying it out beside type. */
    width: 0.36 * w + 0.2 * w + 0.09 * m,
    height: 2 * 0.215 * w + 0.215 * w + 0.09 * m,
  };
};

/** One chevron: tip at (x + lean, y). */
export const Chevron: React.FC<{
  x: number;
  y: number;
  half: number;
  lean: number;
  stroke: number;
  color: string;
  opacity?: number;
}> = ({x, y, half, lean, stroke, color, opacity = 1}) => (
  <polyline
    points={`${x},${y - half} ${x + lean},${y} ${x},${y + half}`}
    fill="none"
    stroke={color}
    strokeWidth={stroke}
    strokeLinecap="round"
    strokeLinejoin="round"
    opacity={opacity}
  />
);

/** The whole mark, centred on (cx, cy), at a canvas of [m]. */
export const Mark: React.FC<{
  cx: number;
  cy: number;
  m: number;
  opacity?: number;
  /** How far apart the two chevrons sit, as a share of the icon's gap. */
  spread?: number;
  trailing?: string;
}> = ({cx, cy, m, opacity = 1, spread = 1, trailing = C.silver}) => {
  const g = markOf(m);
  const gap = g.gap * spread;
  return (
    <g opacity={opacity}>
      {[0, 1].map((i) => (
        <Chevron
          key={i}
          x={cx - gap / 2 - g.lean / 2 + i * gap}
          y={cy + (g.rise * spread) / 2 - i * g.rise * spread}
          half={g.half}
          lean={g.lean}
          stroke={g.stroke}
          color={i === 0 ? trailing : C.white}
        />
      ))}
    </g>
  );
};

/** A full-canvas drawing layer, in points. */
export const Layer: React.FC<{children: React.ReactNode; style?: React.CSSProperties}> = ({
  children,
  style,
}) => (
  <svg
    width={W}
    height={H}
    viewBox={`0 0 ${W} ${H}`}
    style={{position: 'absolute', inset: 0, overflow: 'visible', ...style}}
  >
    {children}
  </svg>
);

/** "MGKFITNESS", the quiet line under every lockup. */
export const Caption: React.FC<{y: number; at: number}> = ({y, at}) => {
  const t = useSeconds();
  const p = seg(t, at, at + 0.4, E.out);
  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        top: y + lerp(6, 0, p),
        textAlign: 'center',
        fontWeight: 600,
        fontSize: 10,
        letterSpacing: 4.2,
        // Tracking is added after each letter; this takes the last one's back
        // off so the line is centred on its ink.
        paddingLeft: 4.2,
        color: C.dim,
        opacity: p,
      }}
    >
      MGKFITNESS
    </div>
  );
};
