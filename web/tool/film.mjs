// Puts the landing film's source on the page.
//
//   node tool/film.mjs keys                 the chosen stills, as the film's five keyframes
//   node tool/film.mjs frames s1 clip.mp4   one move's clip, cut into frames
//   node tool/film.mjs clear s1             take a move's frames off the page again
//
// Run from `web/`. Needs ffmpeg on the path and nothing else: the site has no
// build step that could do this, and Vercel does not run it, so what it writes
// into `public/film/` is committed, like the legal pages.
//
// The stills come from `design/landing/stills/selected/` (k1.png … k5.png);
// `design/landing/stills.md` is the brief they are made to. A clip is a video
// whose first frame is one still and whose last is the next, which is what
// `app/(landing)/storyboard.ts` calls a move.
//
// Everything is cropped to 16:9 from the centre and written at each width in
// `film.json`, which this script also keeps: the page reads it to know which
// stills and how many frames there are, so it never asks for a file that is
// not there.

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const web = join(dirname(fileURLToPath(import.meta.url)), "..");
const selected = join(web, "design/landing/stills/selected");
const film = join(web, "public/film");
const manifest = join(web, "app/(landing)/film.json");

const KEYS = ["k1", "k2", "k3", "k4", "k5"];
const MOVES = ["s1", "s2", "s3", "s4"];
// Frames a second taken from a clip. A five-second move is 120 frames, which
// is as smooth as a scroll can show and about as much as a phone should fetch.
const FPS = 24;

const state = JSON.parse(readFileSync(manifest, "utf8"));
const save = () => writeFileSync(manifest, JSON.stringify(state, null, 2) + "\n");

function ffmpeg(input, filters, quality, output) {
  mkdirSync(dirname(output), { recursive: true });
  const crop = "crop='min(iw,ih*16/9)':'min(ih,iw*9/16)'";
  // A numbered output is a file per frame. Left to guess from ".webp", ffmpeg
  // writes one animated image called "%04d.webp" instead.
  const each = output.includes("%") ? ["-f", "image2"] : [];
  const run = spawnSync(
    "ffmpeg",
    ["-y", "-loglevel", "error", "-i", input, "-vf", [crop, ...filters].join(","),
      "-c:v", "libwebp", "-quality", String(quality), ...each, output],
    { stdio: "inherit" },
  );
  if (run.error) throw new Error("Could not run ffmpeg. Is it installed and on the path?");
  if (run.status !== 0) process.exit(run.status ?? 1);
}

function keys() {
  state.keys = [];
  for (const key of KEYS) {
    const source = ["png", "jpg", "jpeg", "webp"]
      .map((ext) => join(selected, `${key}.${ext}`))
      .find(existsSync);
    if (!source) {
      console.log(`${key}  not chosen yet`);
      continue;
    }
    for (const width of state.widths) {
      ffmpeg(source, [`scale=${width}:-2:flags=lanczos`], 84, join(film, "keys", `${key}-${width}.webp`));
    }
    state.keys.push(key);
    console.log(`${key}  on the page`);
  }
  save();
}

function frames(move, clip) {
  if (!MOVES.includes(move)) throw new Error(`No move called "${move}". The moves are ${MOVES.join(", ")}.`);
  if (!clip || !existsSync(clip)) throw new Error(`No clip at "${clip}".`);
  clear(move);
  for (const width of state.widths) {
    ffmpeg(clip, [`fps=${FPS}`, `scale=${width}:-2:flags=lanczos`], 78, join(film, move, String(width), "%04d.webp"));
  }
  state.frames[move] = readdirSync(join(film, move, String(state.widths[0]))).length;
  save();
  console.log(`${move}  ${state.frames[move]} frames`);
}

function clear(move) {
  rmSync(join(film, move), { recursive: true, force: true });
  delete state.frames[move];
  save();
}

const [command, ...rest] = process.argv.slice(2);
try {
  if (command === "keys") keys();
  else if (command === "frames") frames(...rest);
  else if (command === "clear") clear(rest[0]);
  else throw new Error("Usage: node tool/film.mjs keys | frames <move> <clip> | clear <move>");
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
