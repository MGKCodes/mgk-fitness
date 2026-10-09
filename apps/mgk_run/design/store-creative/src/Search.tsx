import React from 'react';
import {AbsoluteFill} from 'remotion';
import {Device, frameOf} from './Device';
import {C, Ground, useFonts, widthOf} from './kit';
import {SPEC} from './spec';
import {SCREENS, TIME, WORDS} from './words';

const {w: W, h: H, safe} = SPEC.search;

/**
 * The search results asset: what the app is, at a glance, before anyone opens
 * the listing. Apple's advice for this one is "state the obvious" and show the
 * app in use, so it is three of the app's own screens under one headline: a
 * run being recorded in the middle, the finished run and the year either
 * side, as Lift's is, so the two read as one suite. The phones run off the
 * foot. The recording screen's figures are at its foot, so in the tightest
 * crop that phone is its map and route; the full 3:2 shows the figures too.
 */
export const Search: React.FC = () => {
  const ready = useFonts();
  if (!ready) return null;
  // Read on a phone at a few hundred points wide, so set large.
  const HEAD = 230;
  const SUB = 128;
  const [head, sub] = WORDS.search;
  const subW = widthOf(sub, SUB, '600');
  // Fitted with a margin inside the box, so a crop on its edge misses the letters.
  const room = safe.w - 120;
  const sub2 = subW > room ? Math.floor((SUB * room) / subW) : SUB;
  const textTop = safe.y + 12;
  const phonesTop = textTop + HEAD * 1.06 + 30 + sub2 * 1.2 + 110;

  const hero = 760;
  const side = 650;
  const fHero = frameOf('iphone', hero);
  const fSide = frameOf('iphone', side);
  const gap = 60;
  const rowW = fHero.width + 2 * fSide.width + 2 * gap;
  const x0 = (W - rowW) / 2;
  const phones = [
    {src: SCREENS.finished, sw: side, x: x0, y: phonesTop + 90},
    {src: SCREENS.hero, sw: hero, x: x0 + fSide.width + gap, y: phonesTop},
    {src: SCREENS.year, sw: side, x: x0 + fSide.width + gap + fHero.width + gap, y: phonesTop + 90},
  ];
  return (
    <AbsoluteFill style={{background: C.bg, fontFamily: 'Inter', color: C.white}}>
      <Ground at="50% 10%" />
      {phones.map((p) => (
        <div key={p.src} style={{position: 'absolute', left: p.x, top: p.y}}>
          <Device kind="iphone" src={`screens/iphone/${p.src}.png`} screenWidth={p.sw} time={TIME} />
        </div>
      ))}
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top: textTop,
          textAlign: 'center',
          whiteSpace: 'nowrap',
          willChange: 'transform',
        }}
      >
        <div style={{fontWeight: 800, fontSize: HEAD, lineHeight: 1.06, letterSpacing: -0.022 * HEAD}}>
          {head}
        </div>
        <div
          style={{
            marginTop: 30,
            fontWeight: 600,
            fontSize: sub2,
            lineHeight: 1.2,
            letterSpacing: -0.01 * sub2,
            color: C.silver,
          }}
        >
          {sub}
        </div>
      </div>
    </AbsoluteFill>
  );
};
