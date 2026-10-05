// The screens on Lift's store pictures, drawn the way the pictures need them:
// at each phone's size in points and its pixel ratio, with the bands the phone
// keeps for itself left empty for the status bar the pictures draw on top.
//
//   flutter build web -t lib/preview/main.dart --release
//   PLAYWRIGHT_DIR=<folder containing node_modules> node tool/capture_store_screens.mjs
//
// Writes screenshots/store/screens/<phone>/<screen>.png, which
// design/store-shots/render.sh reads. Generated, and not committed.
//
// **Which screens** is read from design/store-shots/src/shots.ts, so the list
// of pictures and the list of screens cannot disagree. STORE_SCREENS=a,b,c
// draws others instead, for choosing.
//
// **The phones are Run's** (kStorePhones in apps/mgk_run/test/plates/store.dart):
// the same points, pixel ratios and safe areas, so the two apps' listings are
// the same pictures of the same phone. The safe area reaches the app through
// the harness's `?safe=` parameter, since a browser has none of its own.

import { createServer } from 'node:http';
import { readFile, mkdir, readdir, unlink } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join, extname, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const here = dirname(fileURLToPath(import.meta.url));

// Resolved from outside the repo, as capture_screens_web.mjs explains.
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
      'the folder containing node_modules.',
  );
}

const PHONES = [
  { name: 'iphone', width: 430, height: 932, dpr: 3, safe: [59, 34] },
  { name: 'android', width: 432, height: 864, dpr: 2.5, safe: [40, 20] },
];

// How long after the first frame each screen is photographed, where 1.5 s is
// wrong. The summary's new best is said as the screen arrives and then closes
// (session_summary_screen.dart), and is gone by about 2.3 s, so a picture
// taken at the usual moment caught it on one phone and missed it on the other.
const MOMENTS = { 'session-summary-pb': 800 };

const webRoot = join(here, '../build/web');
const out = join(here, '../screenshots/store/screens');
const port = Number(process.env.PREVIEW_PORT ?? 8912);

if (!existsSync(webRoot)) {
  throw new Error(
    `No build at ${webRoot}. Run: flutter build web -t lib/preview/main.dart --release`,
  );
}

const shotsSource = await readFile(
  join(here, '../design/store-shots/src/shots.ts'),
  'utf8',
);
const screens = process.env.STORE_SCREENS
  ? process.env.STORE_SCREENS.split(',').map((s) => s.trim()).filter(Boolean)
  : [...shotsSource.matchAll(/screen:\s*'([a-z0-9-]+)'/g)].map((m) => m[1]);
if (screens.length === 0) {
  throw new Error('No screens named in design/store-shots/src/shots.ts');
}

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
    res.writeHead(200, {
      'Content-Type': types[extname(file)] ?? 'application/octet-stream',
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
    });
    res.end(await readFile(file));
  } catch {
    res.writeHead(404).end('not found');
  }
});
await new Promise((resolve) => server.listen(port, '127.0.0.1', resolve));

const browser = await chromium.launch();
const failures = [];

for (const phone of PHONES) {
  const dir = join(out, phone.name);
  await mkdir(dir, { recursive: true });
  // Emptied first, so a screen dropped from the list leaves no picture behind.
  for (const f of await readdir(dir)) {
    if (f.endsWith('.png')) await unlink(join(dir, f));
  }
  const context = await browser.newContext({
    viewport: { width: phone.width, height: phone.height },
    deviceScaleFactor: phone.dpr,
  });
  const page = await context.newPage();
  console.log(`${phone.name}: ${phone.width}x${phone.height} @ ${phone.dpr}`);
  for (const screen of screens) {
    const errors = [];
    const onError = (e) => errors.push(e.message);
    page.on('pageerror', onError);
    try {
      const url =
        `http://127.0.0.1:${port}/?screen=${screen}` +
        `&safe=${phone.safe[0]},${phone.safe[1]}`;
      await page.goto(url, { waitUntil: 'load', timeout: 30_000 });
      await page.waitForSelector('flt-glass-pane, flutter-view', {
        timeout: 30_000,
      });
      // The route push and the screen's entrance, as in the review capture.
      await page.waitForTimeout(MOMENTS[screen] ?? 1500);
      await page.screenshot({ path: join(dir, `${screen}.png`) });
      if (errors.length) throw new Error(errors[0]);
      console.log(`  ${screen}`);
    } catch (e) {
      failures.push(`${phone.name}/${screen}: ${e.message}`);
      console.log(`  ${screen}  FAILED: ${e.message}`);
    } finally {
      page.off('pageerror', onError);
    }
  }
  await context.close();
}

await browser.close();
server.close();
console.log(`\ndone: ${out}`);
if (failures.length) {
  for (const f of failures) console.log(`  ${f}`);
  process.exitCode = 1;
}
