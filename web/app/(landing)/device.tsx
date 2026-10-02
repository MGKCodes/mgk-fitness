import Image from "next/image";
import type { CSSProperties } from "react";

/** One screen the phone shows: the capture, and when it is on (`--in`). */
export type Shown = { src: string; alt: string; style: CSSProperties };

/**
 * The phone the screens are shown on.
 *
 * It is the phone Run's store pictures are drawn on, measure for measure: a
 * 430 by 932 point screen with a 55 point corner, a 5 point bezel and a 3.2
 * point rim, the camera island, four buttons, and the status bar the phone
 * itself draws. So the site and the listing show one device. Everything in
 * `landing.css` under `.phone` is in those points, as `--pt`.
 *
 * **It is drawn, not photographed, and carries no maker's details.** It has an
 * iPhone's proportions and nothing that is Apple's artwork, which is the
 * decision the store pictures made first: neither store lets a listing show
 * another company's product as though it endorsed the app.
 *
 * `bare` is for captures taken with no room left for the status bar, which is
 * Lift's today. They are fitted under it instead of behind it, on `ground`,
 * the colour their own edges are.
 */
export function Phone({
  screens,
  size,
  time,
  bare,
}: {
  screens: Shown[];
  size: [number, number];
  time: string;
  bare?: { ground: string };
}) {
  return (
    <div className="phone">
      <i className="button" style={{ "--top": 178, "--long": 34 } as CSSProperties} />
      <i className="button" style={{ "--top": 240, "--long": 62 } as CSSProperties} />
      <i className="button" style={{ "--top": 318, "--long": 62 } as CSSProperties} />
      <i className="button right" style={{ "--top": 280, "--long": 100 } as CSSProperties} />
      <div className="rim" />
      <div className="bezel" />
      <div
        className={bare ? "screen bare" : "screen"}
        style={bare && { background: bare.ground }}
      >
        {screens.map((screen, i) => (
          <Image
            key={screen.src}
            style={screen.style}
            src={screen.src}
            alt={screen.alt}
            width={size[0]}
            height={size[1]}
            sizes="(max-width: 760px) 70vw, 40svh"
            priority={i === 0}
          />
        ))}
        <span className="clock">{time}</span>
        <svg className="signal" viewBox="0 0 80 14" aria-hidden="true">
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
          <g transform="translate(34.5 12.4)" fill="none" stroke="#fff" strokeWidth={2.1}>
            <path d="M -7.2 -7.2 A 10.2 10.2 0 0 1 7.2 -7.2" />
            <path d="M -4.5 -4.5 A 6.4 6.4 0 0 1 4.5 -4.5" />
            <path d="M -1.9 -1.9 A 2.7 2.7 0 0 1 1.9 -1.9 L 0 0 Z" fill="#fff" stroke="none" />
          </g>
          <rect x={50.5} y={1} width={24} height={12} rx={3.6} fill="none" stroke="#fff" strokeOpacity={0.4} />
          <rect x={52.5} y={3} width={20} height={8} rx={2} fill="#fff" />
          <rect x={75.6} y={5} width={1.6} height={4} rx={0.8} fill="#fff" fillOpacity={0.45} />
        </svg>
        <i className="island" />
        <i className="home" />
      </div>
    </div>
  );
}
