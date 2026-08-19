// Screenshots every preview screen from a browser, via Playwright.
//
//   flutter build web -t lib/preview/main.dart --release
//   node tool/capture_screens_web.mjs
//
// The sibling capture_screens.ps1 does the same job against an Android
// emulator. Keep both: the emulator is the only one that shows real platform
// chrome (status bar, system back, the actual font fallback), and this one is
// the only one that can run without a device attached. Neither replaces the
// other.
//
// **Addressed by name, not by tap position.** The emulator script computes an
// (x, y) for each row of the harness index and taps it, which is why it carries
// a mirrored cellHeight/columns and a heuristic to notice when a tap missed.
// None of that applies here: `?screen=<key>` is read by _HarnessState in
// lib/preview/main.dart and pushes the named route directly, so a screen either
// renders or the page fails to load. There is no silent wrong-screen mode.

import { createServer } from 'node:http';
import { readFile, writeFile, mkdir, readdir, unlink } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join, extname, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const here = dirname(fileURLToPath(import.meta.url));

// Playwright is resolved from outside the repo on purpose.
//
// This is a Flutter workspace with no package.json anywhere and no node_modules
// in .gitignore, so installing a browser driver here would put an npm tree into
// a pure Dart repo and then commit it. Instead, install it wherever you like
// and point PLAYWRIGHT_DIR at the folder *containing* node_modules:
//
//   npm install playwright && npx playwright install chromium
//   PLAYWRIGHT_DIR=<that folder> node tool/capture_screens_web.mjs
//
// createRequire rather than a bare import because ESM resolution walks up from
// this file's own directory and ignores NODE_PATH entirely — so an env var can
// only redirect it through the CJS resolver.
const pwDir = process.env.PLAYWRIGHT_DIR;
const require = createRequire(
  pwDir ? join(pwDir, 'resolve-from-here.cjs') : import.meta.url,
);
let chromium;
try {
  ({ chromium } = require('playwright'));
} catch {
  throw new Error(
    "Could not resolve 'playwright'. Install it, then set PLAYWRIGHT_DIR to " +
      'the folder containing node_modules (see the note above).',
  );
}
const webRoot = join(here, '../build/web');
const previewSource = join(here, '../lib/preview/main.dart');

// 8901 is taken by a parallel worktree's harness. Overridable so a third one
// does not have to edit this file.
const port = Number(process.env.PREVIEW_PORT ?? 8911);

const date =
  process.env.CAPTURE_DATE ?? new Date().toISOString().slice(0, 10);
const out = join(here, `../screenshots/${date}-lift-review`);

// A phone, because that is the only place this app runs. 390x844 is the
// iPhone 14 / Pixel 7 class of viewport; DPR 3 so text is judged at the
// density it actually ships at rather than a blurry upscale.
const viewport = { width: 390, height: 844 };
const deviceScaleFactor = 3;

/// Problems that do not throw, and so cannot be detected from here.
///
/// A screen that renders perfectly well but shows the wrong thing looks
/// identical to a healthy one from Playwright's side. Keyed by screen name
/// rather than file, so adding a screen ahead of one in the list does not
/// silently move a note onto its neighbour.
const KNOWN = {
  // Not defects — limits of reviewing in a browser, worth saying on the page so
  // grey tiles are not mistaken for a broken grid.
  photos: 'layout only — imagery needs the emulator, a browser has no files',
  'photo-series':
    'layout only — imagery needs the emulator, a browser has no files',
};


if (!existsSync(webRoot)) {
  throw new Error(
    `No build at ${webRoot} — run: flutter build web -t lib/preview/main.dart --release`,
  );
}

// The screen names, read from the source rather than duplicated here — same
// reasoning as capture_screens.ps1, which drifted out of order when the list
// was maintained by hand and captioned screens with the wrong names.
const source = await readFile(previewSource, 'utf8');
const screens = [...source.matchAll(/^\s+'([a-z0-9-]+)':\s+\(_\)/gm)].map(
  (m) => m[1],
);
if (screens.length < 2) {
  throw new Error(
    `Could not read screen names from ${previewSource} — has the map format changed?`,
  );
}
console.log(`${screens.length} screens: ${screens.join(', ')}`);

const types = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.css': 'text/css',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff2': 'font/woff2',
  '.bin': 'application/octet-stream',
};

const server = createServer(async (req, res) => {
  try {
    const path = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    const file = join(webRoot, path === '/' ? '/index.html' : path);
    // Serving canvaskit.wasm with the wrong content-type makes the engine fall
    // back to a slower path or refuse to start, and the page then just sits
    // blank — which looks exactly like a screen that failed to render.
    res.writeHead(200, {
      'Content-Type': types[extname(file)] ?? 'application/octet-stream',
      // CanvasKit wants these to use SharedArrayBuffer for its threaded build.
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
    });
    res.end(await readFile(file));
  } catch {
    res.writeHead(404).end('not found');
  }
});

await new Promise((resolve) => server.listen(port, '127.0.0.1', resolve));
console.log(`serving ${webRoot} on http://127.0.0.1:${port}`);

await mkdir(out, { recursive: true });
// Emptied first, for the same reason the emulator script does it: a run that
// adds or reorders screens must leave one coherent set, not new numbering laid
// over old files that nothing writes any more.
for (const f of await readdir(out)) {
  if (f.endsWith('.png')) await unlink(join(out, f));
}

const browser = await chromium.launch();
const context = await browser.newContext({ viewport, deviceScaleFactor });
const page = await context.newPage();

const failures = [];

// Flutter web paints to a canvas, so there is no DOM node per screen to wait
// on. What there IS: the engine removes its loading state and stamps
// <flt-glass-pane> / <flt-scene-host> once it has drawn a frame. Waiting on a
// fixed timeout instead was what produced half-painted captures.
async function waitForFlutter() {
  await page.waitForSelector('flt-glass-pane, flutter-view', {
    timeout: 30_000,
  });
  // One more frame after the pane exists, for the route push and any entrance
  // animation on the screen underneath it.
  await page.waitForTimeout(1200);
}

async function capture(name, url) {
  const errors = [];
  const onError = (e) => errors.push(e.message);
  page.on('pageerror', onError);
  try {
    await page.goto(url, { waitUntil: 'load', timeout: 30_000 });
    await waitForFlutter();
    await page.screenshot({ path: join(out, name) });
    if (errors.length) {
      failures.push(`${name}: ${errors[0]}`);
      console.log(`  ${name}  (page error: ${errors[0]})`);
      return `page error on load: ${errors[0]}`;
    }
    console.log(`  ${name}`);
    return null;
  } catch (e) {
    failures.push(`${name}: ${e.message}`);
    console.log(`  ${name}  FAILED: ${e.message}`);
    return `capture failed: ${e.message}`;
  } finally {
    page.off('pageerror', onError);
  }
}

const base = `http://127.0.0.1:${port}/`;
const sheet = [];

sheet.push({ file: '00-index.png', name: 'index', why: await capture('00-index.png', base) });

for (const [i, screen] of screens.entries()) {
  const file = `${String(i + 1).padStart(2, '0')}-${screen}.png`;
  sheet.push({
    file,
    name: screen,
    why: await capture(file, `${base}?screen=${screen}`),
  });
}

await browser.close();
server.close();

await writeContactSheet(sheet);

console.log(`\ndone: ${out}`);
if (failures.length) {
  console.log(`\n${failures.length} screen(s) had problems:`);
  for (const f of failures) console.log(`  ${f}`);
  process.exitCode = 1;
}

/// Writes the contact sheet next to the images it references.
///
/// **Generated, not hand-maintained.** The first version of this page carried
/// its own copy of the screen list, which went stale the moment a screen was
/// added — the same drift that made capture_screens.ps1 caption screens with
/// their neighbours' names, and the reason the list is parsed from source in
/// the first place. Anything that names a screen is built from `sheet`.
async function writeContactSheet(entries) {
  const rows = entries.map((e) => ({
    ...e,
    why: e.why ?? KNOWN[e.name] ?? '',
  }));
  const flagged = rows.filter((r) => r.why).length;
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lift screen review — ${date}</title>
<style>
  :root { --bg:#0e0e0e; --panel:#1a1a1a; --line:#2c2c2c; --text:#f2f2f2;
          --muted:#9a9a9a; --flag:#d97706; --flag-bg:#d976060f; }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--bg); color:var(--text); padding:32px 28px 80px;
         font:15px/1.5 ui-sans-serif,-apple-system,"Segoe UI",system-ui,sans-serif; }
  header { max-width:1400px; margin:0 auto 28px; }
  h1 { font-size:22px; margin:0 0 6px; font-weight:650; letter-spacing:-0.01em; }
  .sub { color:var(--muted); font-size:14px; margin:0; }
  .controls { display:flex; gap:18px; align-items:center; flex-wrap:wrap;
              margin-top:18px; padding-top:18px; border-top:1px solid var(--line); }
  label { color:var(--muted); font-size:13px; display:flex; gap:7px; align-items:center; cursor:pointer; }
  input[type=range] { width:190px; accent-color:#888; }
  .grid { max-width:1400px; margin:0 auto; display:grid; gap:22px;
          grid-template-columns:repeat(auto-fill,minmax(var(--w,230px),1fr)); }
  figure { margin:0; }
  .shot { display:block; width:100%; height:auto; border-radius:10px;
          border:1px solid var(--line); background:var(--panel); cursor:zoom-in; }
  figcaption { margin-top:8px; font-size:12.5px; color:var(--muted);
               display:flex; align-items:baseline; gap:7px; }
  .n { color:#5f5f5f; font-variant-numeric:tabular-nums; }
  .name { color:var(--text); }
  figure.flagged .shot { border-color:var(--flag); background:var(--flag-bg); }
  figure.flagged .name { color:var(--flag); }
  .why { display:block; color:var(--flag); font-size:11.5px; margin-top:3px; }
  body.hide-ok figure:not(.flagged) { display:none; }
  dialog { border:0; padding:0; background:transparent; max-width:100vw; max-height:100vh; }
  dialog::backdrop { background:#000000e8; }
  dialog img { max-height:94vh; max-width:94vw; border-radius:8px; display:block; }
  dialog .cap { color:#ddd; text-align:center; font-size:13px; padding:10px 0 0; }
</style>
</head>
<body>
<header>
  <h1>Liftio — preview screen review</h1>
  <p class="sub">${rows.length} captures · ${date} · ${viewport.width}×${viewport.height} @ DPR ${deviceScaleFactor} · from <code>lib/preview/main.dart</code></p>
  <div class="controls">
    <label><input type="checkbox" id="only"> Show only flagged (${flagged})</label>
    <label>Size <input type="range" id="size" min="150" max="460" value="230"></label>
    <span class="sub" style="margin-left:auto">Click any shot to enlarge · ← → to step · Esc to close</span>
  </div>
</header>
<div class="grid" id="grid"></div>
<dialog id="lb"><img id="lbimg" alt=""><div class="cap" id="lbcap"></div></dialog>
<script>
const shots = ${JSON.stringify(rows.map((r) => [r.file, r.name, r.why]))};
const grid = document.getElementById('grid');
const esc = s => s.replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
grid.innerHTML = shots.map(([file, name, why], i) => \`
  <figure class="\${why ? 'flagged' : ''}" data-i="\${i}">
    <img class="shot" src="\${esc(file)}" alt="\${esc(name)}" loading="lazy">
    <figcaption>
      <span class="n">\${String(i).padStart(2,'0')}</span>
      <span><span class="name">\${esc(name)}</span>\${why ? \`<span class="why">\${esc(why)}</span>\` : ''}</span>
    </figcaption>
  </figure>\`).join('');

const lb = document.getElementById('lb');
const lbimg = document.getElementById('lbimg');
const lbcap = document.getElementById('lbcap');
let cur = 0;
function show(i) {
  cur = (i + shots.length) % shots.length;
  const [file, name, why] = shots[cur];
  lbimg.src = file;
  lbcap.textContent = String(cur).padStart(2,'0') + ' · ' + name + (why ? '  —  ' + why : '');
  if (!lb.open) lb.showModal();
}
grid.addEventListener('click', e => {
  const fig = e.target.closest('figure');
  if (fig) show(Number(fig.dataset.i));
});
lb.addEventListener('click', () => lb.close());
document.addEventListener('keydown', e => {
  if (!lb.open) return;
  if (e.key === 'ArrowRight') { e.preventDefault(); show(cur + 1); }
  if (e.key === 'ArrowLeft') { e.preventDefault(); show(cur - 1); }
});
document.getElementById('only').addEventListener('change', e =>
  document.body.classList.toggle('hide-ok', e.target.checked));
document.getElementById('size').addEventListener('input', e =>
  grid.style.setProperty('--w', e.target.value + 'px'));
</script>
</body>
</html>
`;
  await writeFile(join(out, 'contact-sheet.html'), html, 'utf8');
  console.log(`contact sheet: ${join(out, 'contact-sheet.html')} (${flagged} flagged)`);
}
