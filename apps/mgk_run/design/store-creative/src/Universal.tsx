import React from 'react';
import {AbsoluteFill} from 'remotion';
import {Device, frameOf} from './Device';
import {C, Ground, Mark, markOf, useFonts, widthOf} from './kit';
import {SPEC} from './spec';
import {SCREENS, TIME, WORDS} from './words';

const {w: W, h: H, safe} = SPEC.universal;

/**
 * C · One picture. A single 16:9 image that App Store Connect crops for both
 * placements, so the header and the search result are the same picture.
 *
 * The store pictures' Slipstream treatment, turned on its side: the mark huge
 * and dark behind, heading right, two lines hard left and a run being recorded
 * beside them. Apple's universal safe box is small (1402 x 962 of 5244 x 2950),
 * so the words and the phone both live inside it. The recording screen's
 * figures are at its foot, so the phone sits high and keeps its foot in the
 * box; its top, the map, is what a tight crop loses.
 */
export const Universal: React.FC = () => {
  const ready = useFonts();
  if (!ready) return null;
  const screenWidth = 600;
  const f = frameOf('iphone', screenWidth);
  const phoneX = safe.x + safe.w - f.width;
  const phoneY = safe.y + safe.h - f.height + 40;
  const inset = 60;
  const room = phoneX - safe.x - inset - 70;
  const [l1, l2] = WORDS.universal;
  const base = 170;
  const widest = Math.max(widthOf(l1, base, '800', -0.022 * base), widthOf(l2, base, '800', -0.022 * base));
  const size = widest <= room ? base : Math.floor((base * room) / widest);
  // The mark, sized so its ink runs most of the height.
  const m = (H * 0.86) / (2 * 0.215 * 0.61 + 0.215 * 0.61 + 0.09);
  const g = markOf(m);
  return (
    <AbsoluteFill style={{background: C.bg, fontFamily: 'Inter', color: C.white}}>
      <Ground at="70% 30%" />
      <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} style={{position: 'absolute', inset: 0}}>
        <Mark cx={W / 2 + g.width * 0.08} cy={H / 2} m={m} trailing={C.lift} leading={C.lift} opacity={0.42} />
      </svg>
      <div style={{position: 'absolute', left: phoneX, top: phoneY}}>
        <Device kind="iphone" src={`screens/iphone/${SCREENS.hero}.png`} screenWidth={screenWidth} time={TIME} />
      </div>
      <div
        style={{
          position: 'absolute',
          left: safe.x + inset,
          top: safe.y + safe.h / 2 - size * 1.06,
          fontWeight: 800,
          fontSize: size,
          lineHeight: 1.06,
          letterSpacing: -0.022 * size,
          whiteSpace: 'nowrap',
          willChange: 'transform',
        }}
      >
        <div style={{color: C.white}}>{l1}</div>
        <div style={{color: C.silver}}>{l2}</div>
      </div>
    </AbsoluteFill>
  );
};
