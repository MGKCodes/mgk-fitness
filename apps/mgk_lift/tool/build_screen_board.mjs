// Builds the screen board from a capture directory and screen_board.json.
//
//   node tool/capture_screens_web.mjs            # the images
//   node tool/build_screen_board.mjs             # this page
//
// **Generated, and it fails rather than drifts.** The contact sheet the capture
// script writes is a grid with names under it; this is the same images arranged
// as the app's own navigation, with the documentation attached. Neither one
// keeps its own copy of the screen list: that one parses the harness, and this
// one cross-checks the harness against screen_board.json and exits non-zero if
// either has a screen the other does not. A board that quietly omits a new
// screen is worse than no board, because it reads as coverage.
//
// **Laid out as a document, not a canvas.** The first version was eight lanes
// on a pan-and-zoom board, and sixty-two screenshots arriving at once is not
// something anybody can concentrate on. This is the shape mgk_run's contact
// sheet arrived at and the reason is the same: acts you read down, each opening
// with what the act is for, broken into racks of three to five plates so the
// eye has somewhere to stop.
//
// Codes are pinned in the data, not derived from position here. Adding a screen
// means giving it the next free number in its act; nothing already on the board
// moves, and a code said out loud stays the plate it was.

import { readFile, writeFile, readdir } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));

// Where the board was rendered from, asked of git rather than written down.
//
// The masthead named `lift/release-2.0.0` as a literal, and went on naming it
// after that branch was merged and deleted. A board that says where it came
// from has to be told by the thing that knows.
const git = (...args) =>
  execFileSync('git', args, { cwd: here, encoding: 'utf8' }).trim();
const branch = git('rev-parse', '--abbrev-ref', 'HEAD');
const commit = git('rev-parse', '--short', 'HEAD');

// Same resolution trick, and the same reason, as capture_screens_web.mjs: this
// is a Flutter workspace with no package.json, so the image encoder is resolved
// from wherever it happens to be installed rather than vendored into a Dart
// repo.
const nodeDir = process.env.SHARP_DIR ?? process.env.PLAYWRIGHT_DIR;
const require = createRequire(
  nodeDir ? join(nodeDir, 'resolve-from-here.cjs') : import.meta.url,
);
let sharp;
try {
  sharp = require('sharp');
} catch {
  throw new Error(
    "Could not resolve 'sharp'. Install it, then set SHARP_DIR (or " +
      'PLAYWRIGHT_DIR) to the folder containing node_modules.',
  );
}

const date = process.env.CAPTURE_DATE ?? new Date().toISOString().slice(0, 10);
const shotsDir = join(here, `../screenshots/${date}-lift-review`);
const outFile =
  process.env.BOARD_OUT ?? join(here, `../screenshots/screen-board.html`);

const board = JSON.parse(
  await readFile(join(here, 'screen_board.json'), 'utf8'),
);

const esc = (s) =>
  String(s).replace(
    /[&<>"]/g,
    (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c],
  );

/* ---- the images, and the check that they match the words ------------------ */

const files = (await readdir(shotsDir)).filter((f) => f.endsWith('.png'));
// `00-index.png` is the harness's own menu, not a screen of the app.
const captured = new Map();
for (const f of files) {
  const m = /^(\d+)-(.+)\.png$/.exec(f);
  if (!m || m[2] === 'index') continue;
  captured.set(m[2], f);
}

const laid = board.acts.flatMap((a) => a.racks.flatMap((r) => r.screens));
const seen = new Set();
const codes = new Map();
const problems = [];

for (const act of board.acts) {
  for (const rack of act.racks) {
    for (const key of rack.screens) {
      if (seen.has(key)) problems.push(`${key} is in two racks`);
      seen.add(key);
      if (!captured.has(key)) {
        problems.push(`${key} is on the board, not captured`);
        continue;
      }
      const s = board.screens[key];
      if (!s) {
        problems.push(`${key} is in a rack, undocumented`);
        continue;
      }
      if (!s.code) problems.push(`${key} has no code`);
      else if (!s.code.startsWith(act.letter)) {
        problems.push(`${key} is coded ${s.code}, but act is ${act.letter}`);
      } else if (codes.has(s.code)) {
        problems.push(`${s.code} is on both ${codes.get(s.code)} and ${key}`);
      } else codes.set(s.code, key);
    }
  }
}
for (const key of captured.keys()) {
  if (!seen.has(key)) problems.push(`${key} was captured, not on the board`);
}
for (const key of Object.keys(board.screens)) {
  if (!seen.has(key)) problems.push(`${key} is documented, not in a rack`);
}
for (const e of board.edges) {
  if (!seen.has(e.from)) problems.push(`edge from unknown screen ${e.from}`);
  if (!seen.has(e.to)) problems.push(`edge to unknown screen ${e.to}`);
}
if (problems.length) {
  console.error(`screen_board.json does not match ${shotsDir}:`);
  for (const p of problems) console.error(`  ${p}`);
  process.exit(1);
}

console.log(`${laid.length} plates across ${board.acts.length} acts`);

const code = (key) => board.screens[key].code;

// Prose refers to other plates as `{{key}}` and never as "P4".
//
// Written out, a code is a second copy of the data: recode a plate and every
// sentence naming it is quietly wrong, with nothing to catch it.
const NUMBERED = ['doc', 'note', 'flag', 'in', 'out', 'next', 'next_note'];
const resolve = (text, where) =>
  text.replace(/\{\{([a-z0-9-]+)\}\}/g, (_, ref) => {
    if (!board.screens[ref]) {
      console.error(`${where} refers to unknown screen "${ref}"`);
      process.exit(1);
    }
    return board.screens[ref].code;
  });
for (const [key, s] of Object.entries(board.screens)) {
  for (const field of NUMBERED) {
    if (typeof s[field] === 'string') {
      s[field] = resolve(s[field], `${key}.${field}`);
    }
  }
}
for (const act of board.acts) {
  act.lede = resolve(act.lede, `act ${act.letter}.lede`);
}

/* ---- what is behind a plate ------------------------------------------------
 *
 * Three kinds of fact, and only one of them is written by hand.
 *
 *   Pulled     the class's own `///` comment, and its constructor's parameters.
 *              These are read out of the source at build time, so they are
 *              whatever the code says today and cannot be stale.
 *   Verified   the ADR numbers and the symbols the call path names. Declared
 *              here, checked against the tree, and the build fails if one has
 *              been renamed or removed.
 *   Written    the call path itself, and the note on each step. A parser cannot
 *              say why a write is not awaited.
 *
 * The split is the point. A screen board that describes architecture in prose
 * is a second copy of the code, and a second copy is a copy that rots — so the
 * parts that CAN be derived are derived, and the parts that cannot are pinned
 * to symbols that fail loudly when they move.
 */

const libRoot = join(here, '../lib');
// The shared packages count as "the tree" too: a call path may legitimately
// name PhotoThumb or Mass, which live in mgk_ui and mgk_units rather than here.
const sharedRoots = [
  join(here, '../../../packages/mgk_ui/lib'),
  join(here, '../../../packages/mgk_units/lib'),
];
const adrRoot = join(here, '../../mgk_run/docs/decisions');
const sourceCache = new Map();

async function source(rel) {
  if (!sourceCache.has(rel)) {
    sourceCache.set(rel, await readFile(join(here, '..', rel), 'utf8'));
  }
  return sourceCache.get(rel);
}

/// Every .dart file under lib, concatenated once, for symbol checks.
async function allSource(dir = libRoot) {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) out.push(await allSource(p));
    else if (entry.name.endsWith('.dart')) out.push(await readFile(p, 'utf8'));
  }
  return out.join('\n');
}
const tree = (
  await Promise.all([libRoot, ...sharedRoots].map((r) => allSource(r)))
).join('\n');

/// The `///` block immediately above a declaration, as paragraphs.
///
/// Markdown-ish already — `[Foo]` links and **bold** are how the codebase
/// writes these — so the little that renders is converted rather than stripped.
function docComment(src, name) {
  const at = new RegExp(
    `^(?:abstract interface |abstract |)class ${name}\\b|^[A-Za-z<>?, ]+ ${name}\\(`,
    'm',
  ).exec(src);
  if (!at) return null;
  const before = src.slice(0, at.index).split('\n');
  // The slice ends exactly at the declaration's line start, so the last element
  // is the empty string before it. Left in, the walk-back stops on that empty
  // line and every doc comment reads as absent.
  if (before.length && before[before.length - 1].trim() === '') before.pop();
  const lines = [];
  for (let i = before.length - 1; i >= 0; i--) {
    const line = before[i].trim();
    if (line.startsWith('///')) lines.unshift(line.replace(/^\/\/\/ ?/, ''));
    else if (line.startsWith('@')) continue;
    else break;
  }
  if (!lines.length) return null;
  const paras = lines
    .join('\n')
    .split(/\n\s*\n/)
    .map((p) => p.replace(/\n/g, ' ').trim())
    .filter(Boolean);
  return paras.map((p) =>
    esc(p)
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\[([A-Za-z0-9_.]+)\]/g, '<code>$1</code>')
      .replace(/`([^`]+)`/g, '<code>$1</code>'),
  );
}

/// The constructor's named parameters, with the type each field declares.
function dependencies(src, name) {
  const ctor = new RegExp(`const ${name}\\(\\{([\\s\\S]*?)\\}\\);`).exec(src);
  if (!ctor) return [];
  const deps = [];
  for (const m of ctor[1].matchAll(/(required )?this\.([A-Za-z0-9_]+)/g)) {
    if (m[2] === 'key') continue;
    const field = new RegExp(`final ([^;]+?) ${m[2]};`).exec(src);
    deps.push({
      name: m[2],
      type: field ? field[1].trim() : '',
      required: Boolean(m[1]),
    });
  }
  return deps;
}

const adrTitles = new Map();
async function adr(n) {
  if (adrTitles.has(n)) return adrTitles.get(n);
  const file = (await readdir(adrRoot)).find((f) => f.startsWith(`${n}-`));
  if (!file) return null;
  const head = (await readFile(join(adrRoot, file), 'utf8')).split('\n')[0];
  const title = head.replace(/^#\s*\d+\s*[—-]\s*/, '').trim();
  adrTitles.set(n, { n, title, file });
  return adrTitles.get(n);
}

/// Does this symbol still exist? `Type` or `Type.member`.
function symbolExists(symbol) {
  const [type, member] = symbol.split('.');
  const declared = new RegExp(
    `\\b(?:abstract interface class|abstract class|class|enum|mixin) ${type}\\b`,
  ).test(tree);
  if (!declared) return false;
  if (!member) return true;
  return new RegExp(`\\b${member}\\b`).test(tree);
}

const archProblems = [];
for (const [key, s] of Object.entries(board.screens)) {
  const a = s.arch;
  if (!a) continue;
  let src;
  try {
    src = await source(a.file);
  } catch {
    archProblems.push(`${key}: no such file ${a.file}`);
    continue;
  }
  a.doc = docComment(src, a.class);
  if (!a.doc) archProblems.push(`${key}: no doc comment on ${a.class}`);
  a.deps = dependencies(src, a.class);
  if (!a.deps.length) archProblems.push(`${key}: no constructor on ${a.class}`);
  a.decisions = [];
  for (const n of a.adrs ?? []) {
    const found = await adr(n);
    if (found) a.decisions.push(found);
    else archProblems.push(`${key}: ADR ${n} does not exist`);
  }
  for (const step of a.path ?? []) {
    if (step.symbol && !symbolExists(step.symbol)) {
      archProblems.push(`${key}: call path names ${step.symbol}, which is gone`);
    }
  }
}
if (archProblems.length) {
  console.error('the architecture notes no longer match the code:');
  for (const p of archProblems) console.error(`  ${p}`);
  process.exit(1);
}
const withArch = Object.values(board.screens).filter((s) => s.arch).length;
console.log(`${withArch} plate(s) carry architecture notes`);

// 620px wide is about twice the plate's display width, so the enlarged view is
// still sharp and the page still sits well under the size ceiling.
const img = new Map();
let bytes = 0;
for (const key of laid) {
  const buf = await sharp(join(shotsDir, captured.get(key)))
    .resize({ width: 620 })
    .webp({ quality: 80 })
    .toBuffer();
  bytes += buf.length;
  img.set(key, `data:image/webp;base64,${buf.toString('base64')}`);
}
console.log(`${(bytes / 1024 / 1024).toFixed(1)} MB of imagery`);

/* ---- the page ------------------------------------------------------------- */

// Routes read as taps: "Settings › Back up your training".
const chevrons = (s) => esc(s).replace(/›/g, '<span class="arrow">›</span>');

const HOSTS = {
  shell: ['tab root', 'Nav bar and coach mark are both on this screen.'],
  pushed: ['pushed', 'A full screen over the shell, with a back affordance.'],
  sheet: ['sheet', 'A modal bottom sheet. Drag or scrim dismisses it.'],
  dialog: ['dialog', 'An alert. Its own buttons are the only way out.'],
};

const has = (key, tag) => (board.screens[key].tags ?? []).includes(tag);
// `new` and `first` are different claims and were briefly one number, which
// made the masthead say eleven screens had never been photographed when six had.
// New = built recently. First = the harness could not reach it until today.
const counts = {
  all: laid.length,
  new: laid.filter((k) => has(k, 'new')).length,
  first: laid.filter((k) => has(k, 'first')).length,
  paid: laid.filter((k) => has(k, 'paid')).length,
  flag: laid.filter((k) => has(k, 'flag')).length,
};

function plate(key) {
  const s = board.screens[key];
  const [hostLabel] = HOSTS[s.host];
  return `<figure class="plate${has(key, 'flag') ? ' flagged' : ''}" id="${s.code}"
  data-key="${esc(key)}" data-code="${s.code}"
  data-new="${has(key, 'new') ? 1 : 0}" data-paid="${has(key, 'paid') ? 1 : 0}"
  data-flag="${has(key, 'flag') ? 1 : 0}">
  <button class="mount" type="button" aria-label="Open ${esc(s.title)} (${s.code})">
    <span class="code">${s.code}</span>
    <img data-src="${esc(key)}" alt="${esc(s.title)}" width="390" height="844">
  </button>
  <figcaption>
    <p class="cap-name">${esc(s.title)}<span class="how h-${s.host}">${esc(hostLabel)}</span>${
      has(key, 'first')
        ? `<span class="how first" title="Not on the previous board (${esc(board.previous ?? 'none')}).">new</span>`
        : ''
    }</p>
    <p class="cap-file"><code>${esc(key)}</code></p>
    <p class="cap-route">${chevrons(s.in)}</p>
    <p class="cap-note">${esc(s.note)}</p>
    ${s.flag ? `<p class="cap-flag">${esc(s.flag)}</p>` : ''}
  </figcaption>
</figure>`;
}

const acts = board.acts
  .map(
    (a) => `<section class="act" id="act-${a.letter}">
  <div class="act-head">
    <span class="act-n">${a.letter}</span>
    <div>
      <h2>${esc(a.title)}</h2>
      <p class="act-sub">${esc(a.sub)}</p>
    </div>
    <span class="act-count">${a.racks.reduce((n, r) => n + r.screens.length, 0)} plates</span>
  </div>
  <p class="act-lede">${a.lede}</p>
  ${a.racks
    .map(
      (r) => `<div class="rack">
    <h3 class="rack-t">${esc(r.title)}<span class="rack-codes">${code(r.screens[0])}–${code(r.screens[r.screens.length - 1])}</span></h3>
    <div class="sheet">${r.screens.map(plate).join('')}</div>
  </div>`,
    )
    .join('')}
</section>`,
  )
  .join('');

const index = board.acts
  .map(
    (a) => `<div class="idx-col">
  <h3>${a.letter} &middot; ${esc(a.title)}</h3>
  <ul>${a.racks
    .flatMap((r) => r.screens)
    .map(
      (k) =>
        `<li><a href="#${code(k)}"><span class="k">${code(k)}</span>${esc(board.screens[k].title)}</a></li>`,
    )
    .join('')}</ul>
</div>`,
  )
  .join('');

// The exit audit, as a table. Every plate's way in, way out and next action —
// the same three facts docs/navigation.md is built on, against the picture.
const table = board.acts
  .map(
    (a) => `<tbody>
  <tr class="grp"><th colspan="5">${a.letter} &middot; ${esc(a.title)}</th></tr>
  ${a.racks
    .flatMap((r) => r.screens)
    .map((k) => {
      const s = board.screens[k];
      return `<tr>
    <td class="c"><a href="#${s.code}">${s.code}</a></td>
    <td class="n">${esc(s.title)}</td>
    <td>${chevrons(s.in)}</td>
    <td>${esc(s.out)}</td>
    <td>${esc(s.next)}${s.next_note ? ` <em>— ${esc(s.next_note)}</em>` : ''}</td>
  </tr>`;
    })
    .join('')}
</tbody>`,
  )
  .join('');

const DETAIL = Object.fromEntries(
  laid.map((key) => {
    const s = board.screens[key];
    const [hostLabel, hostWhy] = HOSTS[s.host];
    return [
      key,
      {
        code: s.code,
        title: s.title,
        host: s.host,
        hostLabel,
        hostWhy,
        doc: s.doc,
        in: s.in,
        out: s.out,
        next: s.next + (s.next_note ? ` — ${s.next_note}` : ''),
        flag: s.flag ?? '',
        arch: s.arch
          ? {
              class: s.arch.class,
              file: s.arch.file,
              doc: s.arch.doc,
              deps: s.arch.deps,
              decisions: s.arch.decisions,
              action: s.arch.action,
              path: s.arch.path,
            }
          : null,
        routes: board.edges
          .filter((e) => e.from === key || e.to === key)
          .map((e) => {
            const out = e.from === key;
            const other = out ? e.to : e.from;
            return {
              out,
              other,
              code: board.screens[other].code,
              title: board.screens[other].title,
              label: e.label,
            };
          }),
      },
    ];
  }),
);

const html = `<title>Lift Screen Board</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<style>
/* The same palette and type as mgk_run's contact sheet, deliberately: these are
   two halves of one product and a reviewer moving between them should not have
   to change reading habits. Light ground, warm accent, plates mounted on white
   — the dark screenshots need something to sit ON rather than dissolve into. */
:root{
  --ground:#E8EAED; --mount:#FFFFFF; --ink:#14171A; --muted:#5A6169;
  --faint:#8A9199; --rule:#D3D7DC; --accent:#8A5D0B; --accent-bg:#F3E7CD;
  --flag:#A8410E; --flag-bg:#F7E3D8; --gate:#6B4B12;
  --shadow:0 1px 2px rgba(16,20,24,.08),0 8px 24px rgba(16,20,24,.08);
}
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){
    --ground:#101214; --mount:#191C1F; --ink:#E6E9EC; --muted:#9AA1A9;
    --faint:#6C747C; --rule:#282D32; --accent:#D9A63E; --accent-bg:#2C2517;
    --flag:#E08A55; --flag-bg:#2E1D13; --gate:#D9A63E;
    --shadow:0 1px 2px rgba(0,0,0,.5),0 10px 30px rgba(0,0,0,.45);
  }
}
:root[data-theme="dark"]{
  --ground:#101214; --mount:#191C1F; --ink:#E6E9EC; --muted:#9AA1A9;
  --faint:#6C747C; --rule:#282D32; --accent:#D9A63E; --accent-bg:#2C2517;
  --flag:#E08A55; --flag-bg:#2E1D13; --gate:#D9A63E;
  --shadow:0 1px 2px rgba(0,0,0,.5),0 10px 30px rgba(0,0,0,.45);
}
*{box-sizing:border-box}
body{
  margin:0; background:var(--ground); color:var(--ink);
  font-family:"IBM Plex Sans","Segoe UI",system-ui,sans-serif;
  font-size:16px; line-height:1.6; -webkit-font-smoothing:antialiased;
}
.wrap{max-width:1240px; margin:0 auto; padding:56px 24px 96px}
code{font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:.88em}
.eyebrow{
  font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:11px;
  letter-spacing:.14em; text-transform:uppercase; color:var(--faint); margin:0 0 10px;
}
a{color:inherit}
:focus-visible{outline:2px solid var(--accent); outline-offset:3px}

/* ---------- masthead ---------- */
header.top{border-bottom:1px solid var(--rule); padding-bottom:32px}
h1{font-size:clamp(30px,4.6vw,46px); line-height:1.08; margin:0 0 14px;
   font-weight:600; letter-spacing:-.022em; text-wrap:balance}
.lede{font-size:17px; color:var(--muted); max-width:64ch; margin:0 0 24px}
.lede strong{color:var(--ink); font-weight:600}
.meta{display:flex; flex-wrap:wrap; gap:10px 28px; align-items:baseline}
.meta div{display:flex; gap:8px; align-items:baseline}
.meta .k{font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:11px;
  letter-spacing:.12em; text-transform:uppercase; color:var(--faint)}
.meta .v{font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:13px; color:var(--ink)}
.cmd{margin:24px 0 0; padding:12px 14px; border:1px solid var(--rule); border-radius:7px;
  background:var(--mount); font-family:"IBM Plex Mono",ui-monospace,monospace;
  font-size:13px; overflow-x:auto; white-space:nowrap}
.cmd .p{color:var(--faint)}
.cmd + .cmd{margin-top:8px}
.caveat{margin:24px 0 0; padding:14px 16px; border-left:3px solid var(--accent);
  background:var(--accent-bg); color:var(--ink); font-size:14.5px; line-height:1.6;
  max-width:76ch; border-radius:0 7px 7px 0}

/* ---------- index ---------- */
.index{margin-top:40px; border:1px solid var(--rule); border-radius:10px;
  background:var(--mount); padding:24px 26px}
.index h2{font-size:21px; margin:0 0 6px}
.index .sub{color:var(--muted); font-size:14.5px; margin:0 0 20px; max-width:70ch}
.index .sub code{background:var(--accent-bg); color:var(--accent); padding:1px 5px;
  border-radius:4px; font-weight:500}
.idx{display:grid; gap:22px; grid-template-columns:repeat(auto-fit,minmax(210px,1fr))}
.idx-col h3{font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:10.5px;
  letter-spacing:.13em; text-transform:uppercase; color:var(--faint); font-weight:400;
  margin:0 0 9px; padding-bottom:7px; border-bottom:1px solid var(--rule)}
.idx-col ul{list-style:none; margin:0; padding:0; display:flex; flex-direction:column; gap:5px}
.idx-col a{display:flex; gap:9px; align-items:baseline; text-decoration:none;
  color:var(--muted); font-size:13.5px}
.idx-col a:hover,.idx-col a:focus-visible{color:var(--ink)}
.idx-col .k{font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:11.5px;
  color:var(--accent); min-width:28px; font-weight:500}

/* ---------- acts ---------- */
section.act{margin-top:72px}
.act-head{display:flex; gap:18px; align-items:baseline; border-top:1px solid var(--rule);
  padding-top:22px; margin-bottom:8px}
.act-n{font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:20px;
  font-weight:500; color:var(--accent); letter-spacing:.06em; min-width:24px}
.act-head > div{flex:1 1 auto; min-width:0}
h2{font-size:27px; line-height:1.2; margin:0; font-weight:600; letter-spacing:-.016em}
.act-sub{color:var(--faint); font-size:15px; margin:0}
.act-count{font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:11px;
  color:var(--faint); white-space:nowrap}
.act-lede{color:var(--muted); font-size:15px; margin:12px 0 30px; max-width:74ch}
.act-lede code{background:var(--accent-bg); color:var(--accent); padding:1px 5px; border-radius:4px}
.act-lede strong{color:var(--ink); font-weight:600}
.act-lede em{font-style:italic}

.rack{margin-bottom:40px}
h3.rack-t{font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:11px;
  letter-spacing:.13em; text-transform:uppercase; color:var(--faint); font-weight:400;
  margin:0 0 16px; padding-bottom:8px; border-bottom:1px solid var(--rule);
  display:flex; justify-content:space-between; gap:16px}
.rack-codes{color:var(--accent)}
.sheet{display:grid; gap:26px; grid-template-columns:repeat(auto-fill,minmax(212px,1fr))}

figure.plate{margin:0; display:flex; flex-direction:column; scroll-margin-top:24px}
figure.plate:target .mount{outline:2px solid var(--accent); outline-offset:3px}
.mount{position:relative; display:block; width:100%; padding:8px; background:var(--mount);
  border:1px solid var(--rule); border-radius:10px; box-shadow:var(--shadow);
  line-height:0; cursor:zoom-in; transition:transform .16s ease}
.mount:hover{transform:translateY(-2px)}
.plate.flagged .mount{border-color:var(--flag)}
.mount img{width:100%; height:auto; display:block; border-radius:4px; background:#0b0b0b}
.code{position:absolute; top:14px; left:14px; z-index:2;
  font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:11px; font-weight:500;
  letter-spacing:.06em; line-height:1; padding:5px 7px; border-radius:5px;
  background:var(--accent); color:var(--mount)}
.plate.flagged .code{background:var(--flag)}
figcaption{padding:11px 2px 0}
.cap-name{font-size:14.5px; font-weight:600; margin:0 0 3px; letter-spacing:-.005em;
  display:flex; gap:8px; align-items:baseline; flex-wrap:wrap}
.how{font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:9.5px; font-weight:400;
  letter-spacing:.08em; text-transform:uppercase; color:var(--faint);
  border:1px solid var(--rule); border-radius:4px; padding:1px 5px; line-height:1.5}
.how.h-shell{color:var(--accent); border-color:var(--accent)}
.how.first{color:var(--mount); background:var(--gate); border-color:var(--gate)}
.cap-file{font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:10.5px;
  color:var(--faint); margin:0 0 6px}
.cap-file code{font-size:inherit}
.cap-route{font-size:12px; color:var(--faint); margin:0 0 6px; line-height:1.45}
.arrow{color:var(--accent); padding:0 2px}
.cap-note{font-size:13px; color:var(--muted); margin:0; line-height:1.5}
.cap-flag{font-size:12px; color:var(--flag); margin:6px 0 0; line-height:1.45}

/* ---------- panels ---------- */
.panel{margin-top:72px; border:1px solid var(--rule); border-radius:10px;
  background:var(--mount); padding:26px}
.panel h2{margin-bottom:6px; font-size:23px}
.panel .sub{color:var(--muted); font-size:15px; margin:0 0 20px; max-width:70ch}
.panel .sub code{background:var(--accent-bg); color:var(--accent); padding:1px 5px; border-radius:4px}
.tablewrap{overflow-x:auto}
table{width:100%; border-collapse:collapse; font-size:13.5px; min-width:760px}
th{text-align:left; font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:10.5px;
  letter-spacing:.12em; text-transform:uppercase; color:var(--faint); font-weight:400;
  padding:0 12px 9px 0; border-bottom:1px solid var(--rule)}
td{padding:11px 12px 11px 0; border-bottom:1px solid var(--rule); vertical-align:top;
  color:var(--muted)}
tr.grp th{padding-top:22px; color:var(--accent); font-size:11px; letter-spacing:.13em}
td.c{font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:12px; width:44px}
td.c a{color:var(--accent); text-decoration:none; font-weight:500}
td.n{color:var(--ink); font-weight:500; width:210px}
td em{font-style:normal; color:var(--faint)}

.findings{list-style:none; margin:0; padding:0; display:flex; flex-direction:column; gap:16px}
.findings li{display:flex; gap:14px; align-items:flex-start}
.findings .fn{font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:11px;
  color:var(--accent); padding-top:4px; min-width:22px}
.findings p{margin:0; font-size:14.5px; color:var(--muted); max-width:74ch}
.findings b{color:var(--ink); font-weight:600}
.findings code{background:var(--accent-bg); color:var(--accent); padding:1px 5px; border-radius:4px}

/* ---------- the enlarged plate ---------- */
dialog{border:1px solid var(--rule); padding:0; background:var(--mount); color:var(--ink);
  border-radius:12px; max-width:min(1000px,94vw); max-height:92vh; overflow:hidden}
dialog::backdrop{background:rgba(12,14,16,.72)}
.d-wrap{display:flex; max-height:92vh}
.d-shot{flex:0 0 auto; padding:20px; display:flex; align-items:center; background:var(--ground)}
.d-shot img{max-height:min(76vh,740px); width:auto; display:block; border-radius:6px;
  border:1px solid var(--rule); background:#0b0b0b}
.d-body{padding:24px 26px; overflow:auto; min-width:0; max-width:500px}
.d-code{font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:12px; color:var(--accent);
  letter-spacing:.06em; margin:0 0 6px}
.d-body h3{margin:0 0 8px; font-size:21px; font-weight:600; letter-spacing:-.014em}
.d-key{font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:11.5px; color:var(--faint);
  margin:0 0 16px; display:flex; gap:9px; align-items:center; flex-wrap:wrap}
.d-flag{margin:0 0 14px; padding:10px 12px; border-left:3px solid var(--flag);
  background:var(--flag-bg); color:var(--flag); font-size:13.5px; line-height:1.55; border-radius:0 6px 6px 0}
.d-doc{margin:0 0 18px; color:var(--muted); font-size:14.5px; line-height:1.65}
.d-body h4{margin:18px 0 8px; font-family:"IBM Plex Mono",ui-monospace,monospace;
  font-size:10.5px; letter-spacing:.13em; text-transform:uppercase; color:var(--faint);
  font-weight:400; padding-bottom:7px; border-bottom:1px solid var(--rule)}
.d-body dl{margin:0; display:flex; flex-direction:column; gap:7px}
.d-body dl div{display:flex; gap:12px; font-size:13.5px; line-height:1.5}
.d-body dt{flex:0 0 38px; color:var(--faint);
  font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:10px;
  letter-spacing:.1em; text-transform:uppercase; padding-top:3px}
.d-body dd{margin:0; color:var(--muted)}
.d-routes{list-style:none; margin:0; padding:0; display:flex; flex-direction:column; gap:7px}
.d-routes li{display:flex; gap:9px; align-items:baseline; font-size:13.5px}
.d-routes .dir{font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:12px;
  color:var(--faint); flex:0 0 auto}
.d-routes button{background:none; border:0; padding:0; font:inherit; cursor:pointer;
  color:var(--accent); text-align:left; text-decoration:underline; text-underline-offset:2px}
.d-routes .lbl{color:var(--faint)}
/* ---------- behind it ---------- */
.d-class{margin:0 0 12px; display:flex; flex-direction:column; gap:2px}
#dclass{font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:14px;
  font-weight:500; color:var(--ink)}
.d-file{font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:11px; color:var(--faint)}
.d-src{border-left:2px solid var(--rule); padding:2px 0 2px 14px; margin:0 0 8px}
.d-src p{margin:0 0 9px; font-size:13.5px; line-height:1.6; color:var(--muted)}
.d-src p:last-child{margin-bottom:0}
.d-src code{background:var(--accent-bg); color:var(--accent); padding:1px 4px; border-radius:3px}
.d-src strong{color:var(--ink); font-weight:600}
.d-from{margin:0; font-size:11.5px; color:var(--faint); line-height:1.5}

.d-deps{list-style:none; margin:0; padding:0; display:flex; flex-direction:column; gap:5px}
.d-deps li{display:flex; gap:9px; align-items:baseline; font-size:12.5px;
  font-family:"IBM Plex Mono",ui-monospace,monospace}
.dep-n{color:var(--ink); min-width:96px}
.dep-t{color:var(--muted)}
.dep-r{color:var(--accent); font-size:10px; letter-spacing:.06em}

.d-path{list-style:none; margin:0; padding:0; display:flex; flex-direction:column; gap:12px;
  counter-reset:step}
.d-path li{border-left:2px solid var(--accent-bg); padding-left:12px; margin-left:0}
.d-path code{display:block; font-family:"IBM Plex Mono",ui-monospace,monospace;
  font-size:12.5px; color:var(--ink); line-height:1.5; word-break:break-word}
.d-path p{margin:5px 0 0; font-size:12.5px; line-height:1.55; color:var(--muted)}

.d-adrs{list-style:none; margin:0; padding:0; display:flex; flex-direction:column; gap:6px}
.d-adrs li{display:flex; gap:10px; align-items:baseline; font-size:13px; color:var(--muted)}
.adr-n{font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:11.5px;
  color:var(--accent); flex:0 0 auto}

.d-close{position:absolute; top:14px; right:16px; z-index:3; background:var(--mount);
  border:1px solid var(--rule); border-radius:6px; width:28px; height:28px;
  color:var(--muted); font-size:16px; line-height:1; cursor:pointer}
.d-nav{display:flex; gap:8px; margin-top:22px; padding-top:16px; border-top:1px solid var(--rule)}
.d-nav button{flex:1; background:var(--ground); border:1px solid var(--rule); border-radius:7px;
  padding:8px 10px; font:inherit; font-size:13px; color:var(--muted); cursor:pointer}
.d-nav button:hover{color:var(--ink)}
@media (max-width:820px){
  .d-wrap{flex-direction:column; overflow:auto}
  .d-shot{justify-content:center}
  .d-shot img{max-height:46vh}
  .d-body{max-width:none}
}
@media (prefers-reduced-motion:reduce){*{transition:none !important}}
</style>

<div class="wrap">

<header class="top">
  <p class="eyebrow">apps/mgk_lift &middot; ${esc(branch)} @ ${esc(commit)}</p>
  <h1>Every screen in Lift, in the order you reach it</h1>
  <p class="lede">All ${counts.all} of them, rendered from the preview harness rather than a device, with the
    chrome they really have. <strong>${counts.first} are new since the last board</strong>
    (${esc(board.previous ?? 'none')})${board.since ? `: ${esc(board.since)}` : ''}. Each plate carries a code you
    can say out loud and the taps that reach it, so a note about a design can name exactly the screen it is
    about.</p>
  <div class="meta">
    <div><span class="k">Rendered</span><span class="v">${date}</span></div>
    <div><span class="k">From</span><span class="v">${esc(branch)} @ ${esc(commit)}</span></div>
    <div><span class="k">Plates</span><span class="v">${counts.all}</span></div>
    <div><span class="k">New since last board</span><span class="v">${counts.first}</span></div>
    <div><span class="k">Behind the gate</span><span class="v">${counts.paid}</span></div>
    <div><span class="k">Surface</span><span class="v">390×844 @ DPR 3</span></div>
  </div>
  <p class="cmd"><span class="p">$</span> flutter build web -t lib/preview/main.dart --release</p>
  <p class="cmd"><span class="p">$</span> node tool/capture_screens_web.mjs   <span class="p"># the images</span></p>
  <p class="cmd"><span class="p">$</span> node tool/build_screen_board.mjs   <span class="p"># this page</span></p>
  <p class="caveat"><strong>The preview harness, not a production build.</strong> Fake coach, fake auth, seeded data
    and one fixed clock — so the paid half renders here whether or not it works on a phone, and progress photos show
    layout only, because a browser has no camera roll. ${counts.flag} plates in act&nbsp;Q are <strong>a design the
    app does not render</strong>; read them with the flag on each one, not as coverage.</p>
</header>

<section class="index">
  <p class="eyebrow">Reference</p>
  <h2>Every plate has a code</h2>
  <p class="sub">Say <code>W7</code> or <code>P4</code> and I will know exactly which screen you mean. The letter is
    the act, the number is its place in that act's flow. Codes are pinned to the plate rather than to its position,
    so adding a screen never renumbers the rest.</p>
  <div class="idx">${index}</div>
</section>

${acts}

<section class="panel">
  <p class="eyebrow">The exit audit</p>
  <h2>In, out, and what to do next</h2>
  <p class="sub">Every screen needs an obvious way in, an obvious way back, and an obvious next step. Where back would
    interrupt something, it is either safe and therefore unguarded, or blocked while the thing is in flight — there is
    no third option. This is the same table as <code>docs/navigation.md</code>, against the picture.</p>
  <div class="tablewrap">
    <table>
      <thead><tr><th>Code</th><th>Screen</th><th>In</th><th>Out</th><th>Next</th></tr></thead>
      ${table}
    </table>
  </div>
</section>

<section class="panel">
  <p class="eyebrow">Found by photographing every screen</p>
  <h2>What building this turned up</h2>
  <p class="sub">A narrower question than the last review asked, and put to the harness rather than the app:
    <em>is what this photographs the screen the app renders?</em> Six times it was not.</p>
  <ol class="findings">
    <li><span class="fn">01</span><p><b>Ten screens were photographed without their chrome.</b> They mounted a surface
      bare on a <code>Scaffold</code> instead of going through <code>LiftShell</code>, so the board showed no nav bar
      and no coach mark on screens that have both — and one entry in fifty-seven rendered the mark at all.</p></li>
    <li><span class="fn">02</span><p><b>The shell took no clock</b>, which is <em>why</em> they were mounted bare: through
      the shell, a screenshot's content changed with the day it was taken. All three surfaces already accepted a date;
      the shell was the one link that did not pass it on.</p></li>
    <li><span class="fn">03</span><p><b>Six screens the harness could not address at all</b> until that
      board. Between them: the primary control on a running session, the only thing progress
      photos are for, and two of the three sheets the exit sweep caught shipping with no dismiss affordance.</p></li>
    <li><span class="fn">04</span><p><b>Two plates were one screen, twice.</b> <code>coach-mark</code> was
      character-for-character <code>track-coach</code>; <code>plan-active</code> turned out to be {{plan-standing}} on a
      different weekday. A board that shows one screen twice claims coverage it does not have.</p></li>
    <li><span class="fn">05</span><p><b>Two screens still read the wall clock</b> — the backup card and coach memory —
      so a sync three minutes old read as "20d ago", and got a day worse every day. Both take a clock now, as every
      other surface already did.</p></li>
    <li><span class="fn">06</span><p><b>The plan intake had a designed flow and no UI for it.</b> Act&nbsp;Q, and the
      one finding that was a decision rather than a fix: build the questionnaire, or take <code>intake_flow.dart</code>
      and its ten previews out. <b>Settled by asking where the answers go.</b> Four of the seven questions land in
      <code>PlanIntake</code>, which persists — those are built, and the four plates now photograph
      <code>PlanIntakeScreen</code> itself instead of a fake transcript in a coach sheet. The other three are body facts
      that <code>docs/coach-profile.md</code> puts in <code>core</code>, and <code>core</code> has nowhere to put them:
      no <code>body_metrics</code>, no <code>height_cm</code>, no <code>year_of_birth</code> in any migration. They were
      three plates of a conversation the backend could not record, so they are cut rather than rendered and discarded.
      The wheel that asks them is built and shipping in the coach; what is missing is a table, not a control.</p></li>
  </ol>
</section>

</div>

<dialog id="detail">
  <button class="d-close" id="dclose" aria-label="Close">&times;</button>
  <div class="d-wrap">
    <div class="d-shot"><img id="dimg" alt=""></div>
    <div class="d-body">
      <p class="d-code" id="dcode"></p>
      <h3 id="dtitle"></h3>
      <p class="d-key"><code id="dkey"></code><span class="how" id="dhost"></span></p>
      <p class="d-flag" id="dflag" hidden></p>
      <p class="d-doc" id="ddoc"></p>
      <h4>Navigation</h4>
      <dl>
        <div><dt>In</dt><dd id="din"></dd></div>
        <div><dt>Out</dt><dd id="dout"></dd></div>
        <div><dt>Next</dt><dd id="dnext"></dd></div>
      </dl>
      <h4 id="drouteh">Routes</h4>
      <ul class="d-routes" id="droutes"></ul>

      <section id="darch" hidden>
        <h4>Behind it</h4>
        <p class="d-class"><span id="dclass"></span><span class="d-file" id="dfile"></span></p>
        <div class="d-src" id="ddocsrc"></div>
        <p class="d-from">From the class's own doc comment, read at build time — so it is whatever the source says today.</p>

        <h4 id="ddeph">Dependencies</h4>
        <ul class="d-deps" id="ddeps"></ul>

        <h4 id="dpathh">What a tap does</h4>
        <ol class="d-path" id="dpath"></ol>

        <h4 id="dadrh">Decisions</h4>
        <ul class="d-adrs" id="dadrs"></ul>
      </section>
      <div class="d-nav">
        <button type="button" id="dprev">&larr; Previous plate</button>
        <button type="button" id="dnext-btn">Next plate &rarr;</button>
      </div>
    </div>
  </div>
</dialog>

<script>
// One copy of each image, keyed by screen. Written out at every <img> instead,
// the page would carry each screenshot twice — plate and dialog — for nothing.
const IMG = ${JSON.stringify(Object.fromEntries(img))};
const DETAIL = ${JSON.stringify(DETAIL)};
const ORDER = ${JSON.stringify(laid)};

for (const el of document.querySelectorAll('img[data-src]')) {
  el.src = IMG[el.dataset.src] || '';
  el.loading = 'lazy';
}

const dlg = document.getElementById('detail');
let cur = null;

function open(key) {
  const d = DETAIL[key];
  if (!d) return;
  cur = key;
  const im = document.getElementById('dimg');
  im.src = IMG[key];
  im.alt = d.title;
  document.getElementById('dcode').textContent = d.code;
  document.getElementById('dtitle').textContent = d.title;
  document.getElementById('dkey').textContent = key;
  const host = document.getElementById('dhost');
  host.textContent = d.hostLabel;
  host.title = d.hostWhy;
  host.className = 'how h-' + d.host;
  const flag = document.getElementById('dflag');
  flag.hidden = !d.flag;
  flag.textContent = d.flag;
  document.getElementById('ddoc').textContent = d.doc;
  document.getElementById('din').textContent = d.in;
  document.getElementById('dout').textContent = d.out;
  document.getElementById('dnext').textContent = d.next;

  const list = document.getElementById('droutes');
  list.replaceChildren();
  for (const r of d.routes) {
    const li = document.createElement('li');
    const dir = document.createElement('span');
    dir.className = 'dir';
    dir.textContent = r.out ? 'to' : 'from';
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.textContent = r.code + '  ' + r.title;
    btn.addEventListener('click', () => open(r.other));
    li.append(dir, btn);
    if (r.label) {
      const lbl = document.createElement('span');
      lbl.className = 'lbl';
      lbl.textContent = '\\u00b7 ' + r.label;
      li.append(lbl);
    }
    list.append(li);
  }
  document.getElementById('drouteh').hidden = d.routes.length === 0;

  const arch = document.getElementById('darch');
  arch.hidden = !d.arch;
  if (d.arch) {
    const a = d.arch;
    document.getElementById('dclass').textContent = a.class;
    document.getElementById('dfile').textContent = a.file.replace(/^lib\\/src\\//, '');

    const src = document.getElementById('ddocsrc');
    src.replaceChildren();
    for (const para of a.doc ?? []) {
      const p = document.createElement('p');
      p.innerHTML = para;
      src.append(p);
    }

    const deps = document.getElementById('ddeps');
    deps.replaceChildren();
    for (const dep of a.deps ?? []) {
      const li = document.createElement('li');
      const n = document.createElement('span');
      n.className = 'dep-n';
      n.textContent = dep.name;
      const t = document.createElement('span');
      t.className = 'dep-t';
      t.textContent = dep.type;
      li.append(n, t);
      if (dep.required) {
        const r = document.createElement('span');
        r.className = 'dep-r';
        r.textContent = 'required';
        li.append(r);
      }
      deps.append(li);
    }
    document.getElementById('ddeph').hidden = !(a.deps ?? []).length;

    const path = document.getElementById('dpath');
    path.replaceChildren();
    for (const step of a.path ?? []) {
      const li = document.createElement('li');
      li.style.paddingLeft = 14 * (step.depth ?? 0) + 'px';
      const c = document.createElement('code');
      c.textContent = step.call;
      li.append(c);
      if (step.note) {
        const n = document.createElement('p');
        n.textContent = step.note;
        li.append(n);
      }
      path.append(li);
    }
    const ph = document.getElementById('dpathh');
    ph.hidden = !(a.path ?? []).length;
    if (a.action) ph.textContent = a.action;

    const adrs = document.getElementById('dadrs');
    adrs.replaceChildren();
    for (const dec of a.decisions ?? []) {
      const li = document.createElement('li');
      const n = document.createElement('span');
      n.className = 'adr-n';
      n.textContent = dec.n;
      const t = document.createElement('span');
      t.textContent = dec.title;
      li.append(n, t);
      adrs.append(li);
    }
    document.getElementById('dadrh').hidden = !(a.decisions ?? []).length;
  }

  if (!dlg.open) dlg.showModal();
  dlg.querySelector('.d-body').scrollTop = 0;
}

const step = (n) => {
  const i = ORDER.indexOf(cur);
  if (i >= 0) open(ORDER[(i + n + ORDER.length) % ORDER.length]);
};

document.addEventListener('click', (e) => {
  const mount = e.target.closest('.mount');
  if (mount) open(mount.closest('.plate').dataset.key);
});
document.getElementById('dclose').addEventListener('click', () => dlg.close());
document.getElementById('dprev').addEventListener('click', () => step(-1));
document.getElementById('dnext-btn').addEventListener('click', () => step(1));
dlg.addEventListener('click', (e) => { if (e.target === dlg) dlg.close(); });
document.addEventListener('keydown', (e) => {
  if (!dlg.open) return;
  if (e.key === 'ArrowRight') { e.preventDefault(); step(1); }
  if (e.key === 'ArrowLeft') { e.preventDefault(); step(-1); }
});
</script>
`;

await writeFile(outFile, resolve(html, 'page'), 'utf8');
console.log(
  `board: ${outFile} (${(Buffer.byteLength(html) / 1024 / 1024).toFixed(1)} MB)`,
);
