"use client";

import { useEffect } from "react";
import "./studio.css";

/**
 * mgkcodes.com runs this page live inside its home page, and builds it there
 * in the studio's stages before it goes live. This lets that page ask for
 * three looks: the empty drawing board ("blank"), this page drawn in
 * hairlines ("sketch", studio.css), and the page itself ("page"). It also
 * sends the page's markup, which the studio's page types out as the build.
 *
 * Both come from the page as it is, so the studio's picture of it can never
 * go out of date. Only mgkcodes.com is answered, and a page that is not in a
 * frame does nothing at all.
 */
const STUDIO = new Set(["https://mgkcodes.com", "https://www.mgkcodes.com"]);

const LOOKS = new Set(["blank", "sketch", "page"]);
const SKIP = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "svg", "CANVAS", "VIDEO", "IMG", "PICTURE"]);
const TEXT = new Set(["H1", "H2", "H3", "H4", "P", "A", "BUTTON", "LI", "LABEL", "SMALL", "SPAN", "STRONG", "EM"]);
const LANDMARK = new Set(["HEADER", "NAV", "MAIN", "SECTION", "ARTICLE", "FOOTER", "FORM"]);
// A class that names something ("pill", "lede"), not a utility ("flex", "mt-4").
const UTILITY =
  /^(hidden|block|inline|flex|grid|absolute|relative|fixed|sticky|static|contents|container|group|peer|truncate|uppercase|lowercase|italic|underline|sr-only)$|^-?(m|p|[mp][xytblr]|w|h|min|max|gap|space|text|font|leading|tracking|bg|border|rounded|shadow|opacity|z|top|left|right|bottom|inset|col|row|items|justify|self|place|order|overflow|object|transition|duration|ease|delay|animate|translate|scale|rotate|origin|cursor|select|pointer|fill|stroke|ring|outline|decoration|whitespace|break|aspect|size|basis|grow|shrink|line|backdrop|blur)-|[:[\]/.0-9]/;

const onScreen = (el: Element) => {
  const r = el.getBoundingClientRect();
  return r.width > 2 && r.height > 2 && r.bottom > 0 && r.top < innerHeight && r.right > 0 && r.left < innerWidth;
};

const opaque = (colour: string) => {
  const alpha = colour.match(/rgba?\([^)]*[,/]\s*([\d.]+)\s*\)/);
  return colour !== "transparent" && (!alpha || parseFloat(alpha[1]) > 0.1);
};

/**
 * Marks what the sketch draws, in reading order, so it can draw it piece by
 * piece: each piece of text, and each box with a fill or a border. A fill
 * the size of the screen is the page's ground, not a box.
 */
function mark() {
  const pieces: HTMLElement[] = [];
  for (const el of document.body.querySelectorAll<HTMLElement>("*")) {
    if (SKIP.has(el.tagName) || !onScreen(el)) continue;
    const style = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    const ground = r.width >= innerWidth * 0.9 && r.height >= innerHeight * 0.9;
    const boxed =
      !ground &&
      (opaque(style.backgroundColor) ||
        style.backgroundImage !== "none" ||
        parseFloat(style.borderTopWidth) + parseFloat(style.borderBottomWidth) > 0);
    const worded = [...el.childNodes].some((n) => n.nodeType === Node.TEXT_NODE && n.textContent?.trim());
    if (boxed) el.dataset.studioBox = "";
    if (boxed || worded) pieces.push(el);
  }
  pieces.forEach((el, i) => el.style.setProperty("--studio-at", `${Math.round((i / pieces.length) * 900)}ms`));
}

/**
 * The page's first screen as markup: landmarks, and the words in them. A
 * list of links shows its first three, so the headline below still fits.
 */
function outline() {
  const lines: string[] = [];
  const walk = (parent: Element, depth: number, list = false) => {
    let items = 0;
    for (const el of parent.children) {
      if (lines.length >= 12) return;
      if (SKIP.has(el.tagName) || !onScreen(el)) continue;
      if (list && items === 3) {
        lines.push(`${"  ".repeat(depth)}…`);
        return;
      }
      const tag = el.tagName.toLowerCase();
      const name = [...el.classList].find((c) => /^[a-z][a-z-]{1,15}$/.test(c) && !UTILITY.test(c));
      const open = name ? `${tag} class="${name}"` : tag;
      const pad = "  ".repeat(depth);
      const words = (el as HTMLElement).innerText?.replace(/\s+/g, " ").trim();
      if (TEXT.has(el.tagName) && words && !el.querySelector(":scope > :is(div, section, header, nav, ul, ol)")) {
        lines.push(`${pad}<${open}>${words.length > 30 ? `${words.slice(0, 29)}…` : words}</${tag}>`);
        items++;
      } else if (LANDMARK.has(el.tagName)) {
        const at = lines.length;
        lines.push(`${pad}<${open}>`);
        walk(el, depth + 1, el.tagName === "NAV");
        if (lines.length === at + 1) lines.pop();
        else lines.push(`${pad}</${tag}>`);
      } else {
        walk(el, depth, list);
      }
    }
  };
  walk(document.body, 0);
  return lines;
}

export function Studio() {
  useEffect(() => {
    if (window.parent === window) return;
    const root = document.documentElement;
    let marked = false;
    let markup: string[] | undefined;
    let settling: number | undefined;

    const show = (look: string) => {
      if (!marked) {
        mark();
        marked = true;
      }
      clearTimeout(settling);
      if (look === "page") {
        if (!root.dataset.studio) return;
        // Held for the colours to come back, then let go.
        root.dataset.studio = "page";
        settling = window.setTimeout(() => delete root.dataset.studio, 1000);
        return;
      }
      if (look === "sketch" && root.dataset.studio !== "blank") {
        // Clear the board first, so the sketch draws on rather than snapping.
        root.dataset.studio = "blank";
        void root.offsetWidth;
      }
      root.dataset.studio = look;
    };

    const onMessage = (event: MessageEvent) => {
      if (!STUDIO.has(event.origin) || event.source !== window.parent) return;
      const data = event.data as { studio?: unknown; stage?: unknown };
      if (data?.studio !== 1) return;
      if (typeof data.stage === "string" && LOOKS.has(data.stage)) show(data.stage);
      markup ??= outline();
      window.parent.postMessage({ studio: 1, ready: true, outline: markup }, event.origin);
    };
    window.addEventListener("message", onMessage);
    // Says it is listening, in case the studio's page spoke before it was.
    window.parent.postMessage({ studio: 1, hello: true }, "*");
    return () => {
      window.removeEventListener("message", onMessage);
      clearTimeout(settling);
    };
  }, []);
  return null;
}
