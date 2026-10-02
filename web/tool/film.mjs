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
// The film is kept in two shapes. **Wide** is 16:9, for a screen wider than it
// is tall. **Tall** is 9:16, for an upright one, which a wide still crops
// badly to. A tall still is its wide one's name with a `p`.
//
// The stills come from `design/landing/stills/selected/` (k1.png … k5.png, and
// k1p.png … k5p.png); `design/landing/stills.md` is the brief they are made
// to. A clip is a video whose first frame is one still and whose last is the
// next, which is what `app/(landing)/storyboard.ts` calls a move. An upright
// clip is taken to be for the tall film.
//
// Everything is cropped to its shape from the centre and written at each width
// in `film.json`, which this script also keeps: the page reads it to know
// which stills and how many frames there are, so it never asks for a file that
// is not there.
//
// A still whose subject sits too high or too low for what the page lays over
// it is framed first: `selected/framing.json` gives, by the still's name, the
// share of its height to cut from the `top` or the `bottom`. The cut is made
// here, and the chosen image is left as it was made.
//
// A clip can be edited on its way in, likewise. `design/landing/clips/edits.json`
// gives, by the clip's file name, an ffmpeg filter graph that takes `[0:v]` and
// ends in `[v]`. It is how a move a video model paced unevenly is evened out,
// and how a jump inside one is dissolved. `clips/notes.md` says what each is for.

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const web = join(dirname(fileURLToPath(import.meta.url)), "..");
const selected = join(web, "design/landing/stills/selected");
const editsFile = join(web, "design/landing/clips/edits.json");
const film = join(web, "public/film");
const manifest = join(web, "app/(landing)/film.json");

const KEYS = ["k1", "k2", "k3", "k4", "k5"];
const MOVES = ["s1", "s2", "s3", "s4"];
// `fps` is the frames a second taken from a clip, and `quality` what they are
// saved at. A clip is 24 frames a second and both films take every other one:
// a five-second move is 61 frames, which is still a frame every dozen pixels
// of scrolling, and half the weight. The first and last frames are kept, so a
// move joins its stills as before. The tall film is fetched by phones, often
// over a mobile connection, so it is saved a little lower as well.
const SHAPES = {
  wide: { across: 16, down: 9, suffix: "", fps: 12, quality: 76 },
  tall: { across: 9, down: 16, suffix: "p", fps: 12, quality: 70 },
};

const state = JSON.parse(readFileSync(manifest, "utf8"));
const save = () => writeFileSync(manifest, JSON.stringify(state, null, 2) + "\n");

const framingFile = join(selected, "framing.json");
const framing = existsSync(framingFile) ? JSON.parse(readFileSync(framingFile, "utf8")) : {};

/** The cut a still is given before it is cropped to its shape, if it has one. */
function framed(name) {
  const { top = 0, bottom = 0 } = framing[name] ?? {};
  return top || bottom ? [`crop=iw:ih*${1 - top - bottom}:0:ih*${top}`] : [];
}

function ffmpeg(shape, input, filters, quality, output, first = [], edit) {
  mkdirSync(dirname(output), { recursive: true });
  const { across, down } = SHAPES[shape];
  const crop = `crop='min(iw,ih*${across}/${down})':'min(ih,iw*${down}/${across})'`;
  const chain = [...first, crop, ...filters].join(",");
  // An edit is a graph of its own, which the usual chain is then hung from.
  const graph = edit
    ? ["-filter_complex", `${edit};[v]${chain}[out]`, "-map", "[out]"]
    : ["-vf", chain];
  // A numbered output is a file per frame. Left to guess from ".webp", ffmpeg
  // writes one animated image called "%04d.webp" instead.
  const each = output.includes("%") ? ["-f", "image2"] : [];
  const run = spawnSync(
    "ffmpeg",
    ["-y", "-loglevel", "error", "-i", input, ...graph,
      "-c:v", "libwebp", "-quality", String(quality), ...each, output],
    { stdio: "inherit" },
  );
  if (run.error) throw new Error("Could not run ffmpeg. Is it installed and on the path?");
  if (run.status !== 0) process.exit(run.status ?? 1);
}

/** Which film a clip is for: the tall one if it is upright. */
function shapeOf(clip) {
  const probe = spawnSync(
    "ffprobe",
    ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", clip],
    { encoding: "utf8" },
  );
  if (probe.error) throw new Error("Could not run ffprobe, which comes with ffmpeg. Is it on the path?");
  const [width, height] = probe.stdout.trim().split(",").map(Number);
  if (probe.status !== 0 || !width || !height) throw new Error(`Could not read the size of "${clip}".`);
  return height > width ? "tall" : "wide";
}

function keys() {
  for (const [shape, { suffix }] of Object.entries(SHAPES)) {
    const set = state[shape];
    // Written afresh, so a still taken out of `selected/` leaves the page too.
    rmSync(join(film, shape, "keys"), { recursive: true, force: true });
    set.keys = [];
    for (const key of KEYS) {
      const source = ["png", "jpg", "jpeg", "webp"]
        .map((ext) => join(selected, `${key}${suffix}.${ext}`))
        .find(existsSync);
      if (!source) {
        console.log(`${key}${suffix}`.padEnd(5) + "not chosen yet");
        continue;
      }
      const cut = framed(`${key}${suffix}`);
      for (const width of set.widths) {
        ffmpeg(shape, source, [`scale=${width}:-2:flags=lanczos`], 84, join(film, shape, "keys", `${key}-${width}.webp`), cut);
      }
      set.keys.push(key);
      console.log(`${key}${suffix}`.padEnd(5) + (cut.length ? "on the page, framed" : "on the page"));
    }
  }
  save();
}

function frames(move, clip) {
  if (!MOVES.includes(move)) throw new Error(`No move called "${move}". The moves are ${MOVES.join(", ")}.`);
  if (!clip || !existsSync(clip)) throw new Error(`No clip at "${clip}".`);
  const shape = shapeOf(clip);
  const set = state[shape];
  const { fps, quality } = SHAPES[shape];
  const edits = existsSync(editsFile) ? JSON.parse(readFileSync(editsFile, "utf8")) : {};
  const edit = edits[basename(clip)];
  clear(move, shape);
  for (const width of set.widths) {
    ffmpeg(shape, clip, [`fps=${fps}`, `scale=${width}:-2:flags=lanczos`], quality, join(film, shape, move, String(width), "%04d.webp"), [], edit);
  }
  set.frames[move] = readdirSync(join(film, shape, move, String(set.widths[0]))).length;
  save();
  console.log(`${move}  ${set.frames[move]} frames, ${shape}${edit ? ", edited" : ""}`);
}

/** Takes a move's frames off the page: from one film, or from both. */
function clear(move, only) {
  if (!MOVES.includes(move)) throw new Error(`No move called "${move}". The moves are ${MOVES.join(", ")}.`);
  for (const shape of only ? [only] : Object.keys(SHAPES)) {
    rmSync(join(film, shape, move), { recursive: true, force: true });
    delete state[shape].frames[move];
  }
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
