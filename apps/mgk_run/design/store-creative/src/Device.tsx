import React from 'react';
import {Img, staticFile} from 'remotion';

export type Kind = 'iphone' | 'android';

/**
 * The two phones the screens were drawn as, in points. These match
 * `kStorePhones` in test/plates/store.dart: the top band each leaves empty is
 * where the status bar is drawn here.
 */
export const PHONES = {
  iphone: {w: 430, h: 932, radius: 55, bezel: 5, rim: 3.2},
  android: {w: 432, h: 864, radius: 36, bezel: 5, rim: 2.6},
} as const;

/** What a frame adds to each side of its screen, in canvas pixels. */
export const frameOf = (kind: Kind, screenWidth: number) => {
  const p = PHONES[kind];
  const k = screenWidth / p.w;
  const pad = (p.bezel + p.rim) * k;
  return {
    k,
    pad,
    width: screenWidth + 2 * pad,
    height: p.h * k + 2 * pad,
    screenHeight: p.h * k,
  };
};

const IphoneBar: React.FC<{time: string}> = ({time}) => (
  <>
    <div
      style={{
        position: 'absolute',
        left: 28,
        top: 19,
        width: 100,
        textAlign: 'center',
        fontWeight: 600,
        fontSize: 17,
        lineHeight: '21px',
        letterSpacing: -0.2,
        color: '#fff',
      }}
    >
      {time}
    </div>
    <svg
      width={80}
      height={14}
      viewBox="0 0 80 14"
      style={{position: 'absolute', left: 314, top: 23}}
    >
      {/* Signal. */}
      {[0, 1, 2, 3].map((i) => (
        <rect
          key={i}
          x={i * 5}
          y={12.5 - (4 + i * 2.6)}
          width={3.2}
          height={4 + i * 2.6}
          rx={1}
          fill="#fff"
        />
      ))}
      {/* Wi-Fi: a dot and two bands, a quarter turn wide. */}
      <g transform="translate(34.5 12.4)" fill="none" stroke="#fff" strokeWidth={2.1}>
        <path d="M -7.2 -7.2 A 10.2 10.2 0 0 1 7.2 -7.2" />
        <path d="M -4.5 -4.5 A 6.4 6.4 0 0 1 4.5 -4.5" />
        <path d="M -1.9 -1.9 A 2.7 2.7 0 0 1 1.9 -1.9 L 0 0 Z" fill="#fff" stroke="none" />
      </g>
      {/* Battery. */}
      <rect x={50.5} y={1} width={24} height={12} rx={3.6} fill="none" stroke="#fff" strokeOpacity={0.4} />
      <rect x={52.5} y={3} width={20} height={8} rx={2} fill="#fff" />
      <rect x={75.6} y={5} width={1.6} height={4} rx={0.8} fill="#fff" fillOpacity={0.45} />
    </svg>
    {/* The home indicator. */}
    <div
      style={{
        position: 'absolute',
        left: (430 - 144) / 2,
        bottom: 8,
        width: 144,
        height: 5,
        borderRadius: 3,
        background: '#fff',
      }}
    />
  </>
);

const AndroidBar: React.FC<{time: string}> = ({time}) => (
  <>
    <div
      style={{
        position: 'absolute',
        left: 26,
        top: 10,
        fontWeight: 500,
        fontSize: 14.5,
        lineHeight: '20px',
        color: '#fff',
      }}
    >
      {time}
    </div>
    <svg
      width={58}
      height={16}
      viewBox="0 0 58 16"
      style={{position: 'absolute', right: 24, top: 12}}
    >
      {/* Wi-Fi: a full fan. */}
      <path d="M 9 14.5 L 0.6 4.6 A 13 13 0 0 1 17.4 4.6 Z" fill="#fff" />
      {/* Signal: a full wedge. */}
      <path d="M 23.5 14.5 L 37 14.5 L 37 1.5 Z" fill="#fff" />
      {/* Battery, upright. */}
      <rect x={46} y={2.4} width={9} height={12.1} rx={1.6} fill="#fff" />
      <rect x={48.5} y={0.8} width={4} height={2.4} rx={0.8} fill="#fff" />
    </svg>
    {/* The gesture pill. */}
    <div
      style={{
        position: 'absolute',
        left: (432 - 108) / 2,
        bottom: 8,
        width: 108,
        height: 4,
        borderRadius: 2,
        background: '#fff',
        opacity: 0.92,
      }}
    />
  </>
);

/**
 * A screen with what the phone itself draws over it: the clock, the signal,
 * the battery and the bar at the bottom. [island] adds the camera, which a
 * screenshot taken on the phone does not show and a picture of the phone does.
 */
export const Screen: React.FC<{
  kind: Kind;
  src: string;
  width: number;
  time: string;
  island?: boolean;
  radius?: number;
}> = ({kind, src, width, time, island = true, radius}) => {
  const p = PHONES[kind];
  const k = width / p.w;
  return (
    <div
      style={{
        position: 'relative',
        width,
        height: p.h * k,
        borderRadius: radius ?? p.radius * k,
        overflow: 'hidden',
        background: '#1A1A1A',
      }}
    >
      <Img src={staticFile(src)} style={{position: 'absolute', inset: 0, width, height: p.h * k}} />
      <div
        style={{
          position: 'absolute',
          left: 0,
          top: 0,
          width: p.w,
          height: p.h,
          transform: `scale(${k})`,
          transformOrigin: '0 0',
          fontFamily: 'Inter',
          willChange: 'transform',
        }}
      >
        {kind === 'iphone' ? <IphoneBar time={time} /> : <AndroidBar time={time} />}
        {island && kind === 'iphone' ? (
          <div
            style={{
              position: 'absolute',
              left: (430 - 124) / 2,
              top: 11,
              width: 124,
              height: 36,
              borderRadius: 18,
              background: '#000',
            }}
          />
        ) : null}
        {island && kind === 'android' ? (
          <div
            style={{
              position: 'absolute',
              left: 432 / 2 - 7,
              top: 13,
              width: 14,
              height: 14,
              borderRadius: 7,
              background: '#000',
              boxShadow: 'inset 0 0 0 1.5px #161616',
            }}
          />
        ) : null}
      </div>
    </div>
  );
};

/**
 * The phone: a plain dark frame, no maker's details. Neither store lets a
 * listing show another company's product as though it endorsed the app, and a
 * frame that is nobody's in particular cannot go out of date.
 */
export const Device: React.FC<{
  kind: Kind;
  src: string;
  screenWidth: number;
  time: string;
}> = ({kind, src, screenWidth, time}) => {
  const p = PHONES[kind];
  const f = frameOf(kind, screenWidth);
  const outer = (p.radius + p.bezel + p.rim) * f.k;
  const button = (top: number, height: number, side: 'left' | 'right') => (
    <div
      style={{
        position: 'absolute',
        [side]: -1.6 * f.k,
        top: top * f.k,
        width: 3 * f.k,
        height: height * f.k,
        borderRadius: 1.5 * f.k,
        background: 'linear-gradient(90deg, #2c2c2e, #4a4a4d 50%, #2c2c2e)',
      }}
    />
  );
  return (
    <div style={{position: 'relative', width: f.width, height: f.height}}>
      {kind === 'iphone' ? (
        <>
          {button(178, 34, 'left')}
          {button(240, 62, 'left')}
          {button(318, 62, 'left')}
          {button(280, 100, 'right')}
        </>
      ) : (
        <>
          {button(210, 46, 'right')}
          {button(290, 96, 'right')}
        </>
      )}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          borderRadius: outer,
          background:
            'linear-gradient(140deg, #6b6b6e 0%, #38383a 14%, #232325 38%, #1d1d1f 62%, #343436 86%, #58585b 100%)',
          boxShadow: `0 ${50 * f.k}px ${90 * f.k}px rgba(0,0,0,0.55), 0 ${8 * f.k}px ${20 * f.k}px rgba(0,0,0,0.35)`,
        }}
      />
      <div
        style={{
          position: 'absolute',
          inset: p.rim * f.k,
          borderRadius: (p.radius + p.bezel) * f.k,
          background: '#050505',
        }}
      />
      <div style={{position: 'absolute', left: f.pad, top: f.pad}}>
        <Screen kind={kind} src={src} width={screenWidth} time={time} />
      </div>
    </div>
  );
};
