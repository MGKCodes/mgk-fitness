"use client";

import { useEffect, useRef, type CSSProperties, type ReactNode } from "react";
import assets from "./film.json";
import { screens, shots, type Key, type Shot } from "./storyboard";

// What `tool/film.mjs` has put in `public/film/`, in the two shapes it keeps
// the film in: wide for a screen wider than it is tall, and tall for an
// upright one. `across` is a shape's width over its height. Empty until there
// are stills.
type Shape = "wide" | "tall";
type Reel = {
  keys: string[];
  frames: Record<string, number>;
  widths: number[];
  across: number;
};
const reels: Record<Shape, Reel> = {
  wide: { ...assets.wide, across: 16 / 9 },
  tall: { ...assets.tall, across: 9 / 16 },
};
const everyKey = [...new Set([...reels.wide.keys, ...reels.tall.keys])] as Key[];

const keyUrl = (shape: Shape, key: Key, width: number) =>
  `/film/${shape}/keys/${key}-${width}.webp`;
const frameUrl = (shape: Shape, shot: string, width: number, index: number) =>
  `/film/${shape}/${shot}/${width}/${String(index + 1).padStart(4, "0")}.webp`;

const clamp = (n: number) => Math.min(1, Math.max(0, n));
const ease = (t: number) => t * t * (3 - 2 * t);

// Where each shot begins and ends, as a share of the whole film.
const spans = (() => {
  let at = 0;
  return shots.map((shot) => {
    const start = at / screens;
    at += shot.screens;
    return { shot, start, end: at / screens };
  });
})();
const spanOf = (id: string) => spans.find((span) => span.shot.id === id);

/**
 * The film: one canvas pinned to the viewport, played by scrolling.
 *
 * Its children are the beats, the words and screens laid over it. Each names
 * the shots it is on screen for with `data-from` and `data-to`, and is given
 * `--t`, its own progress from 0 to 1, to move by.
 *
 * A move with frames plays them. A move without crossfades between its two
 * stills, so the storyboard can be walked before any video exists. With no
 * stills either it draws a slate naming the shot.
 *
 * An upright screen is shown the tall film once that film has a still: its
 * frames and no others, and its stills, with the wide still standing in for
 * any it has not got yet.
 *
 * `places` names points in the film that a link can go to: an id, and the hold
 * it stands for. Each is put a third of the way into its hold, where whatever
 * arrives during that hold has arrived.
 */
export function Film({
  places = {},
  children,
}: {
  places?: Record<string, string>;
  children: ReactNode;
}) {
  const film = useRef<HTMLElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const root = film.current!;
    const view = canvas.current!;
    const ctx = view.getContext("2d")!;
    const beats = [...root.querySelectorAll<HTMLElement>("[data-beat]")];
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");

    const images = new Map<string, HTMLImageElement>();
    // Which film is showing, and the width of each that suits this screen.
    let shape: Shape = "wide";
    let width = { wide: 0, tall: 0 };
    let shown = -1;
    let dirty = true;
    let raf = 0;
    let stopped = false;

    const image = (src: string) => {
      let img = images.get(src);
      if (!img) {
        img = new Image();
        img.decoding = "async";
        img.addEventListener("load", () => (dirty = true));
        img.src = src;
        images.set(src, img);
      }
      return img;
    };
    const ready = (src: string) => {
      const img = image(src);
      return img.complete && img.naturalWidth > 0 ? img : null;
    };

    // A key's still in the film that is showing, or its wide one.
    const stillUrl = (key: Key) => {
      const from = reels[shape].keys.includes(key) ? shape : "wide";
      return reels[from].keys.includes(key) ? keyUrl(from, key, width[from]) : null;
    };
    const count = (shot: string) => reels[shape].frames[shot] ?? 0;

    // The stills, then every eighth frame, then the gaps, so a move can be
    // scrubbed roughly as soon as it is reached and sharpens as the rest lands.
    const preload = () => {
      const queue = everyKey.map(stillUrl).filter((src) => src !== null);
      const seen = new Set<string>();
      for (const stride of [8, 4, 2, 1]) {
        for (const { shot } of spans) {
          for (let i = 0; i < count(shot.id); i += stride) {
            const src = frameUrl(shape, shot.id, width[shape], i);
            if (!seen.has(src)) queue.push(src);
            seen.add(src);
          }
        }
      }
      let next = 0;
      const pull = () => {
        while (!stopped && next < queue.length) {
          const img = image(queue[next++]);
          if (img.complete) continue;
          img.addEventListener("load", pull, { once: true });
          img.addEventListener("error", pull, { once: true });
          return;
        }
      };
      for (let lane = 0; lane < 6; lane++) pull();
    };

    // The smallest width a film has that fills the canvas without being
    // stretched far, or failing that its largest.
    const fit = ({ widths, across }: Reel) => {
      const drawn = Math.max(view.width, view.height * across);
      return (
        [...widths].sort((a, b) => a - b).find((each) => each >= drawn * 0.87) ??
        Math.max(...widths)
      );
    };

    const resize = () => {
      const ratio = Math.min(window.devicePixelRatio, 2);
      view.width = Math.round(view.clientWidth * ratio);
      view.height = Math.round(view.clientHeight * ratio);
      const next: Shape =
        view.height > view.width && reels.tall.keys.length ? "tall" : "wide";
      const fits = { wide: fit(reels.wide), tall: fit(reels.tall) };
      if (next !== shape || fits.wide !== width.wide || fits.tall !== width.tall) {
        shape = next;
        width = fits;
        preload();
      }
      dirty = true;
    };

    const cover = (img: HTMLImageElement, alpha = 1) => {
      const scale = Math.max(
        view.width / img.naturalWidth,
        view.height / img.naturalHeight,
      );
      const w = img.naturalWidth * scale;
      const h = img.naturalHeight * scale;
      ctx.globalAlpha = alpha;
      ctx.drawImage(img, (view.width - w) / 2, (view.height - h) / 2, w, h);
      ctx.globalAlpha = 1;
    };

    const slate = (shot: Shot, t: number) => {
      const px = view.width / view.clientWidth;
      const path =
        shot.kind === "hold" ? shot.at : `${shot.from} → ${shot.to}`;
      // Out of the beats' way: along the bottom, or under the bar on a phone,
      // where the bottom belongs to the words.
      const y = view.clientWidth < 760 ? 84 * px : view.height - 44 * px;
      const rule = 160 * px;
      ctx.fillStyle = "#8a8f98";
      ctx.font = `600 ${11 * px}px ${getComputedStyle(view).fontFamily}`;
      ctx.textAlign = "center";
      ctx.fillText(
        `${shot.id} · ${path} · no stills yet`.toUpperCase(),
        view.width / 2,
        y,
      );
      ctx.fillStyle = "#3a3a3a";
      ctx.fillRect((view.width - rule) / 2, y + 12 * px, rule, 2 * px);
      ctx.fillStyle = "#c0c0c0";
      ctx.fillRect((view.width - rule) / 2, y + 12 * px, rule * t, 2 * px);
    };

    const still = (key: Key) => {
      const src = stillUrl(key);
      return src ? ready(src) : null;
    };

    // The nearest frame that has arrived, looking outwards from the one asked for.
    const frame = (shot: string, index: number) => {
      const total = count(shot);
      for (let reach = 0; reach < total; reach++) {
        for (const i of [index - reach, index + reach]) {
          if (i < 0 || i >= total) continue;
          const img = images.get(frameUrl(shape, shot, width[shape], i));
          if (img?.complete && img.naturalWidth > 0) return img;
        }
      }
      return null;
    };

    const draw = (p: number) => {
      const span = spans.find((s) => p < s.end) ?? spans[spans.length - 1];
      const { shot } = span;
      const t = clamp((p - span.start) / (span.end - span.start));

      ctx.fillStyle = "#1a1a1a";
      ctx.fillRect(0, 0, view.width, view.height);

      if (shot.kind === "hold") {
        // Rest on the frame the camera arrived on, so a hold and the move
        // before it never disagree about where the camera stopped.
        const before = spans[spans.indexOf(span) - 1]?.shot;
        const after = spans[spans.indexOf(span) + 1]?.shot;
        const img =
          (before && frame(before.id, count(before.id) - 1)) ||
          (after && frame(after.id, 0)) ||
          still(shot.at);
        if (img) cover(img);
        else slate(shot, t);
        return;
      }

      const total = count(shot.id);
      // Reduced motion gets a cut where the move would have been.
      const cut = reduced.matches;
      const played = cut ? null : frame(shot.id, Math.round(t * (total - 1)));
      if (played) return cover(played);

      const from =
        still(shot.from) ?? (cut ? frame(shot.id, 0) : null);
      const to =
        still(shot.to) ?? (cut ? frame(shot.id, total - 1) : null);
      if (!from && !to) return slate(shot, t);
      const mix = cut ? (t < 0.5 ? 0 : 1) : ease(t);
      if (from) cover(from);
      if (to) cover(to, from ? mix : 1);
    };

    const place = (p: number) => {
      const fade = 0.3 / screens;
      for (const beat of beats) {
        const start = spanOf(beat.dataset.from!)?.start ?? 0;
        const end = spanOf(beat.dataset.to!)?.end ?? 1;
        const rise = start <= 0 ? 1 : clamp((p - start) / fade);
        const fall = end >= 1 ? 1 : clamp((end - p) / fade);
        const opacity = Math.min(rise, fall);
        beat.style.opacity = String(opacity);
        beat.style.visibility = opacity > 0 ? "visible" : "hidden";
        beat.style.setProperty("--t", String(clamp((p - start) / (end - start))));
      }
    };

    const tick = () => {
      raf = requestAnimationFrame(tick);
      const box = root.getBoundingClientRect();
      const target = clamp(-box.top / (box.height - view.clientHeight));
      // Ease towards the scroll position: a wheel moves in steps, and a film
      // that steps with it reads as a slideshow.
      const next =
        shown < 0 || reduced.matches || Math.abs(target - shown) < 0.0004
          ? target
          : shown + (target - shown) * 0.2;
      if (next === shown && !dirty) return;
      shown = next;
      dirty = false;
      draw(shown);
      place(shown);
    };

    resize();
    window.addEventListener("resize", resize);
    raf = requestAnimationFrame(tick);

    return () => {
      stopped = true;
      cancelAnimationFrame(raf);
      window.removeEventListener("resize", resize);
    };
  }, []);

  return (
    <section
      ref={film}
      className="film"
      style={{ "--screens": screens } as CSSProperties}
    >
      {Object.entries(places).map(([id, shot]) => {
        const span = spanOf(shot)!;
        const at = (span.start + (span.end - span.start) * 0.3) * screens;
        return <i key={id} id={id} className="place" style={{ top: `${at * 100}svh` }} />;
      })}
      <div className="stage">
        <canvas ref={canvas} aria-hidden="true" />
        {children}
      </div>
    </section>
  );
}
