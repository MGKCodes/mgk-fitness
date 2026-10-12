"use client";

import { usePathname } from "next/navigation";
import { useEffect, useRef, type MouseEvent } from "react";
import { social } from "./links";
import { Mark } from "./mark";
import { Social } from "./social";
import { StoreGlyph, Stores } from "./stores";

// How long the page takes to travel one screen of film going down, in
// milliseconds. The film is played by scrolling, so this is its playing speed
// when the page does the scrolling for somebody.
const PACE = 1050;

let halt: (() => void) | undefined;

/**
 * Scrolls the page to `to` over a time that suits the distance, so that going
 * to an app plays the film on the way and is not a jump past it. Anything the
 * visitor does stops it: it is their page.
 */
function glide(to: number) {
  halt?.();
  const from = window.scrollY;
  const distance = to - from;
  if (
    Math.abs(distance) < 2 ||
    window.matchMedia("(prefers-reduced-motion: reduce)").matches
  ) {
    return window.scrollTo(0, to);
  }

  const screens = Math.abs(distance) / window.innerHeight;
  // Down is the film playing, so it takes the film's time. Back up is quick.
  const duration =
    distance > 0
      ? Math.min(7500, Math.max(1200, screens * PACE))
      : Math.min(1600, Math.max(600, screens * 250));
  const began = performance.now();
  const reasons = ["wheel", "touchstart", "keydown", "mousedown"];
  let frame = 0;

  const stop = () => {
    cancelAnimationFrame(frame);
    for (const reason of reasons) window.removeEventListener(reason, stop);
    halt = undefined;
  };
  const step = (now: number) => {
    const t = Math.min(1, (now - began) / duration);
    // Soft at both ends, even in between.
    window.scrollTo(0, from + distance * (0.5 - Math.cos(Math.PI * t) / 2));
    if (t < 1) frame = requestAnimationFrame(step);
    else stop();
  };

  for (const reason of reasons) window.addEventListener(reason, stop, { passive: true });
  halt = stop;
  frame = requestAnimationFrame(step);
}

/**
 * Where to get the apps, from anywhere on the page: the two stores' marks,
 * which open each app's badges. A <details>, so it opens with no JavaScript;
 * the script only closes it on a click elsewhere or Escape.
 */
function Get() {
  const menu = useRef<HTMLDetailsElement>(null);
  useEffect(() => {
    const close = (event: Event) => {
      const open = menu.current;
      if (!open?.open) return;
      if (event instanceof KeyboardEvent ? event.key === "Escape" : !open.contains(event.target as Node)) {
        open.open = false;
      }
    };
    document.addEventListener("pointerdown", close);
    document.addEventListener("keydown", close);
    return () => {
      document.removeEventListener("pointerdown", close);
      document.removeEventListener("keydown", close);
    };
  }, []);

  return (
    <details className="getmenu" ref={menu}>
      <summary className="pill" aria-label="Get the apps">
        <StoreGlyph store="App Store" />
        <StoreGlyph store="Google Play" />
        <span className="wide">Get the apps</span>
      </summary>
      <div className="panel">
        <p>Run</p>
        <Stores app="run" />
        <p>Lift</p>
        <Stores app="lift" />
      </div>
    </details>
  );
}

/**
 * The bar: the suite's name, its pages, its accounts elsewhere and where to
 * get the apps.
 *
 * The film is the home page, and the suite's name takes it back to its top:
 * gliding there on the home page, and a link home from every other page. Run,
 * Lift and the source are pages of their own.
 */
export function Bar() {
  const home = usePathname() === "/";

  function top(event: MouseEvent<HTMLAnchorElement>) {
    if (!home) return;
    event.preventDefault();
    history.replaceState(null, "", "/");
    glide(0);
  }

  return (
    <header className="bar">
      {/* Named for the widths at which only the mark is shown. */}
      <a className="wordmark" href="/" onClick={top} aria-label="MGKFitness">
        <Mark of="suite" />
        <span>MGKFITNESS</span>
      </a>
      <nav aria-label="Pages">
        <a href="/run">Run</a>
        <a href="/lift">Lift</a>
        <a className="source" href="/open-source">
          Open source
        </a>
      </nav>
      <div className="socials">
        {social.map((account) => (
          <Social key={account.name} {...account} />
        ))}
      </div>
      <Get />
    </header>
  );
}
