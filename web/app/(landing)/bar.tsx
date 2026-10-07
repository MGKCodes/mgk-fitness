"use client";

import type { MouseEvent } from "react";
import { social } from "./links";
import { Mark } from "./mark";
import { Social } from "./social";

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
 * The bar: the suite's name, its two apps, its accounts elsewhere and where
 * to get the apps.
 *
 * Run and Lift are places in the film, not pages, so their links scroll the
 * film to where each app arrives. They are ordinary links to `#run` and
 * `#lift` underneath, which is what they do with no JavaScript and what a
 * shared address opens on.
 */
export function Bar() {
  function go(event: MouseEvent<HTMLAnchorElement>) {
    const place = document.getElementById(event.currentTarget.hash.slice(1));
    if (!place) return;
    event.preventDefault();
    history.replaceState(null, "", event.currentTarget.hash);
    glide(place.getBoundingClientRect().top + window.scrollY);
  }

  return (
    <header className="bar">
      {/* Named for the widths at which only the mark is shown. */}
      <a className="wordmark" href="#top" onClick={go} aria-label="MGKFitness">
        <Mark of="suite" />
        <span>MGKFITNESS</span>
      </a>
      <nav aria-label="On this page">
        <a href="#run" onClick={go}>
          Run
        </a>
        <a href="#lift" onClick={go}>
          Lift
        </a>
      </nav>
      <div className="socials">
        {social.map((account) => (
          <Social key={account.name} {...account} />
        ))}
      </div>
      {/* Said in one word where the bar has no room for two. */}
      <a className="pill" href="#get" aria-label="Get the apps">
        <span className="wide">Get the apps</span>
        <span className="narrow">Get</span>
      </a>
    </header>
  );
}
