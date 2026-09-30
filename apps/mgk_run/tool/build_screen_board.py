#!/usr/bin/env python3
"""Build the Run screen board: one self-contained HTML page of every screen.

    python tool/build_screen_board.py --out board.html   # from apps/mgk_run
    python tool/build_screen_board.py --stale            # what to re-read

Three inputs, and this file owns none of their content:

- ``plates/*.png`` -- the pictures, written by ``flutter test test/plates/<file>.dart``
  (gitignored; regenerate them first).
- ``test/plates/board.captions.json`` -- what each screen is FOR and what good
  looks like, grouped into acts and bands. **The writing is the deliverable**;
  it lives apart from this generator so a diff shows which descriptions changed
  rather than which pixels did.
- ``test/plates/board.state.json`` -- the commit each plate was captured at,
  per plate rather than per run.

**--stale** is the half that keeps the board honest. Pictures regenerate in
minutes; the prose was written against code that has since moved, and nothing
else will ever say so. It diffs each plate's recorded commit against HEAD and
lists the plates whose *descriptions* to re-read: direct hits first (the plate's
own source, or a file its caption names as drawing it), then every other changed
app or design-system file named once at the bottom, because one edit to a shared
widget would otherwise flag every plate and bury the line that mattered.

Images are converted to WebP and held under ~70 KB each, so the page stays well
inside what an artifact republishes on every save. Needs Pillow.
"""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import html
import io
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.normpath(os.path.join(HERE, '..'))
PLATES = os.path.join(APP, 'plates')
CAPTIONS = os.path.join(APP, 'test', 'plates', 'board.captions.json')
STATE = os.path.join(APP, 'test', 'plates', 'board.state.json')

MAX_BYTES = 70 * 1024


def load(path: str) -> dict:
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def git(*args: str) -> str:
    return subprocess.run(
        ['git', *args], cwd=APP, check=True, capture_output=True, text=True
    ).stdout.strip()


# --- Images ------------------------------------------------------------------


def webp(path: str) -> tuple[bytes, int, int]:
    """The plate as WebP, as sharp as fits under MAX_BYTES."""
    from PIL import Image

    src = Image.open(path).convert('RGB')
    # 2x the widest a plate is drawn in the lightbox (420 CSS px) for a phone
    # screen; component crops keep their own proportion.
    for width in (840, 720, 620, 540, 460):
        scale = min(1.0, width / src.width)
        im = src.resize((round(src.width * scale), round(src.height * scale)), Image.LANCZOS)
        for quality in (82, 74, 66, 58, 50):
            buf = io.BytesIO()
            im.save(buf, 'WEBP', quality=quality, method=6)
            if buf.tell() <= MAX_BYTES:
                return buf.getvalue(), im.width, im.height
    return buf.getvalue(), im.width, im.height


# --- Staleness ---------------------------------------------------------------


def stale(captions: dict, state: dict) -> int:
    head = git('rev-parse', 'HEAD')
    prefix = git('rev-parse', '--show-prefix')  # e.g. apps/mgk_run/
    watched = (prefix + 'lib/', 'packages/mgk_ui/lib/', prefix + 'test/plates/')
    records = state.get('plates', {})

    changed_since: dict[str, set[str]] = {}
    direct: list[tuple[str, str, list[str]]] = []
    shared: set[str] = set()
    missing: list[str] = []

    for code, plate in captions['plates'].items():
        rec = records.get(plate['file'])
        if rec is None:
            missing.append(code)
            continue
        sha = rec['sha']
        if sha not in changed_since:
            names = git('diff', '--name-only', f'{sha}..{head}').splitlines()
            changed_since[sha] = {n for n in names if n.startswith(watched)}
        changed = changed_since[sha]
        own = {prefix + rec['source']} | {prefix + f for f in plate.get('files', [])}
        hits = sorted(changed & own)
        if hits:
            direct.append((code, plate['name'], hits))
        shared |= {
            n for n in changed - own
            if not n.startswith(prefix + 'test/plates/')
        }

    print(f'Screen board staleness against HEAD {head[:7]}\n')
    if direct:
        print('Re-read these descriptions (their own files changed):')
        for code, name, hits in direct:
            print(f'  {code:<5} {name}')
            for h in hits:
                print(f'          {h[len(prefix):] if h.startswith(prefix) else h}')
    else:
        print('No plate\'s own files changed since it was captured.')
    if missing:
        print('\nNever captured (no record in board.state.json): ' + ', '.join(missing))
    if shared:
        print('\nAlso changed, and drawn by many screens (named once):')
        for n in sorted(shared):
            print(f'  {n}')
    return 1 if direct or missing else 0


# --- The page ----------------------------------------------------------------

CSS = r"""
:root{
  --ground:#E8EAED; --mount:#FFFFFF; --ink:#14171A; --muted:#5A6169;
  --faint:#8A9199; --rule:#D3D7DC; --accent:#8A5D0B; --accent-bg:#F3E7CD;
  --shadow:0 1px 2px rgba(16,20,24,.08),0 8px 24px rgba(16,20,24,.08);
}
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){
    --ground:#101214; --mount:#191C1F; --ink:#E6E9EC; --muted:#9AA1A9;
    --faint:#6C747C; --rule:#282D32; --accent:#D9A63E; --accent-bg:#2C2517;
    --shadow:0 1px 2px rgba(0,0,0,.5),0 10px 30px rgba(0,0,0,.45);
  }
}
:root[data-theme="dark"]{
  --ground:#101214; --mount:#191C1F; --ink:#E6E9EC; --muted:#9AA1A9;
  --faint:#6C747C; --rule:#282D32; --accent:#D9A63E; --accent-bg:#2C2517;
  --shadow:0 1px 2px rgba(0,0,0,.5),0 10px 30px rgba(0,0,0,.45);
}
*{box-sizing:border-box}
body{margin:0;background:var(--ground);color:var(--ink);
  font-family:"IBM Plex Sans","Segoe UI",system-ui,sans-serif;
  font-size:16px;line-height:1.6;-webkit-font-smoothing:antialiased}
.wrap{max-width:1240px;margin:0 auto;padding:56px 24px 96px}
code,.mono{font-family:"IBM Plex Mono",ui-monospace,monospace}
code{font-size:.88em}
.eyebrow{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:11px;
  letter-spacing:.14em;text-transform:uppercase;color:var(--faint);margin:0 0 10px}
header.top{border-bottom:1px solid var(--rule);padding-bottom:32px}
h1{font-size:clamp(30px,4.6vw,46px);line-height:1.08;margin:0 0 14px;font-weight:600;letter-spacing:-.022em;text-wrap:balance}
.lede{font-size:17px;color:var(--muted);max-width:66ch;margin:0 0 24px}
.meta{display:flex;flex-wrap:wrap;gap:10px 28px;align-items:baseline}
.meta div{display:flex;gap:8px;align-items:baseline}
.meta .k{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:var(--faint)}
.meta .v{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:13px;color:var(--ink)}
.panel{margin-top:40px;border:1px solid var(--rule);border-radius:10px;background:var(--mount);padding:24px 26px}
.panel h2{font-size:21px;margin:0 0 12px}
.panel ul{margin:0;padding-left:20px;color:var(--muted);font-size:14.5px;max-width:92ch}
.panel li{margin:0 0 8px}
.panel li::marker{color:var(--accent)}
.index{margin-top:24px}
.index .sub{color:var(--muted);font-size:14.5px;margin:0 0 20px;max-width:70ch}
.index .sub code{background:var(--accent-bg);color:var(--accent);padding:1px 5px;border-radius:4px;font-weight:500}
.idx{display:grid;gap:22px;grid-template-columns:repeat(auto-fit,minmax(190px,1fr))}
.idx-col h3{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:10.5px;letter-spacing:.13em;
  text-transform:uppercase;color:var(--faint);font-weight:400;margin:0 0 9px;padding-bottom:7px;border-bottom:1px solid var(--rule)}
.idx-col ul{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:5px}
.idx-col a{display:flex;gap:9px;align-items:baseline;text-decoration:none;color:var(--muted);font-size:13.5px}
.idx-col a:hover,.idx-col a:focus-visible{color:var(--ink)}
.idx-col .k{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:11.5px;color:var(--accent);min-width:30px;font-weight:500}
.idx-col .n{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:9.5px;letter-spacing:.08em;color:var(--accent);border:1px solid var(--accent);border-radius:3px;padding:0 4px;margin-left:auto}
.retired{margin:18px 0 0;font-size:13.5px;color:var(--faint)}
section.act{margin-top:72px}
.act-head{display:flex;gap:18px;align-items:baseline;border-top:1px solid var(--rule);padding-top:22px;margin-bottom:8px}
.act-n{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:13px;color:var(--accent);letter-spacing:.06em}
h2{font-size:27px;line-height:1.2;margin:0;font-weight:600;letter-spacing:-.016em}
.act-sub{color:var(--faint);font-size:15px;margin:0}
.act-lede{color:var(--muted);font-size:15px;margin:10px 0 26px;max-width:72ch}
.band{margin-bottom:40px}
h3.band-t{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:11px;letter-spacing:.13em;
  text-transform:uppercase;color:var(--faint);font-weight:400;margin:0 0 14px;padding-bottom:8px;border-bottom:1px solid var(--rule);
  display:flex;gap:12px;align-items:baseline;flex-wrap:wrap}
h3.band-t .seq{letter-spacing:.04em;text-transform:none;color:var(--accent)}
.sheet{display:grid;gap:28px 24px;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));align-items:start}
figure.plate{margin:0;display:flex;flex-direction:column;scroll-margin-top:20px}
figure.plate:target .mount{outline:2px solid var(--accent);outline-offset:3px}
.mount{position:relative;background:var(--mount);border:1px solid var(--rule);border-radius:10px;padding:8px;
  box-shadow:var(--shadow);line-height:0;cursor:zoom-in;transition:transform .16s ease}
.mount:hover,.mount:focus-visible{transform:translateY(-2px)}
.mount:focus-visible{outline:2px solid var(--accent);outline-offset:3px}
.mount img{width:100%;height:auto;display:block;border-radius:4px;background:#0b0b0b}
.code{position:absolute;top:14px;left:14px;z-index:2;font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:11px;font-weight:500;
  letter-spacing:.06em;line-height:1;padding:5px 7px;border-radius:5px;background:var(--accent);color:var(--mount)}
.step{position:absolute;top:14px;right:14px;z-index:2;font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:10.5px;line-height:1;
  padding:5px 6px;border-radius:5px;background:var(--mount);color:var(--muted);border:1px solid var(--rule)}
figcaption{padding:12px 2px 0}
.cap-name{font-size:15px;font-weight:600;margin:0 0 6px;letter-spacing:-.005em;line-height:1.35}
.tags{display:flex;flex-wrap:wrap;gap:5px;margin:0 0 8px}
.tag{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:10px;letter-spacing:.08em;text-transform:uppercase;
  padding:1px 6px;border-radius:3px;border:1px solid var(--rule);color:var(--faint);line-height:1.6}
.tag.driven{color:var(--accent);border-color:var(--accent);background:var(--accent-bg)}
.tag.new{color:var(--mount);background:var(--accent);border-color:var(--accent)}
.cap-route{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:11px;color:var(--accent);margin:0 0 10px;line-height:1.5;word-break:break-word}
.cap-route .arrow{color:var(--faint)}
.lbl{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:10px;letter-spacing:.12em;text-transform:uppercase;color:var(--faint);margin:0 0 2px}
.cap-job,.cap-done{font-size:13.5px;margin:0 0 10px;line-height:1.5}
.cap-job{color:var(--ink)}
.cap-done{color:var(--muted)}
.cap-extra{font-size:12.5px;color:var(--muted);margin:0 0 10px;padding:6px 9px;border-left:2px solid var(--accent);background:var(--accent-bg);border-radius:0 5px 5px 0}
.cap-new{font-size:12px;color:var(--accent);margin:0 0 8px}
.cap-at{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:10.5px;color:var(--faint);margin:0}
.caveats{margin-top:64px;border-top:1px solid var(--rule);padding-top:26px}
.caveats h2{font-size:20px;margin-bottom:16px}
.cav{display:grid;gap:20px;grid-template-columns:repeat(auto-fit,minmax(230px,1fr))}
.cav h3{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:11px;letter-spacing:.1em;text-transform:uppercase;color:var(--faint);margin:0 0 6px;font-weight:400}
.cav p{margin:0;font-size:14px;color:var(--muted)}
dialog.lb{border:0;padding:0;background:transparent;max-width:100vw;max-height:100vh;width:100%;height:100%;overflow:auto}
dialog.lb::backdrop{background:rgba(8,10,12,.88)}
dialog.lb .inner{min-height:100%;display:flex;align-items:center;justify-content:center;padding:28px}
dialog.lb img{max-width:min(420px,92vw);width:100%;height:auto;border-radius:10px;box-shadow:0 24px 70px rgba(0,0,0,.6)}
dialog.lb button{position:fixed;top:16px;right:18px;background:var(--mount);color:var(--ink);border:1px solid var(--rule);border-radius:6px;
  padding:7px 12px;cursor:pointer;font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:12px}
@media (max-width:520px){.wrap{padding:32px 16px 64px}.sheet{grid-template-columns:1fr}}
@media (prefers-reduced-motion:reduce){*{transition:none!important}}
"""

SCRIPT = r"""
(function(){
  var lb=document.getElementById('lb'),img=document.getElementById('lbi'),x=document.getElementById('lbx');
  function open(src,alt){img.src=src;img.alt=alt||'';if(lb.showModal)lb.showModal();}
  document.querySelectorAll('.mount').forEach(function(m){
    m.addEventListener('click',function(){open(m.querySelector('img').src,m.getAttribute('aria-label'));});
    m.addEventListener('keydown',function(e){
      if(e.key==='Enter'||e.key===' '){e.preventDefault();open(m.querySelector('img').src,m.getAttribute('aria-label'));}
    });
  });
  x.addEventListener('click',function(){lb.close();});
  lb.addEventListener('click',function(e){if(e.target===lb||e.target.classList.contains('inner'))lb.close();});
})();
"""


def esc(s: str) -> str:
    return html.escape(s, quote=True)


def route(s: str) -> str:
    return ' <span class="arrow">›</span> '.join(esc(p.strip()) for p in s.split('›'))


def day(iso: str) -> str:
    d = dt.date.fromisoformat(iso)
    return f'{d.day} {d.strftime("%b")} {d.year}'


def build(out: str) -> None:
    captions = load(CAPTIONS)
    state = load(STATE).get('plates', {})
    board = captions['board']
    plates = captions['plates']

    shas = {state[p['file']]['sha'] for p in plates.values() if p['file'] in state}
    dates = sorted({state[p['file']]['captured'] for p in plates.values() if p['file'] in state})
    driven = sum(1 for p in plates.values() if p['how'] == 'driven')
    # New means new to the board: a code the last board did not carry.
    previous = set(board.get('previous', []))
    fresh = {c for c in plates if c not in previous}
    new = len(fresh)
    at = ', '.join(sorted(s[:7] for s in shas)) or 'not recorded'
    when = day(dates[-1]) if dates else 'unknown'

    parts: list[str] = []
    w = parts.append
    w('<!doctype html><html lang="en"><head><meta charset="utf-8">')
    w('<meta name="viewport" content="width=device-width,initial-scale=1">')
    w('<title>Run Screen Board</title>')
    w('<link rel="preconnect" href="https://fonts.googleapis.com">')
    w('<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>')
    w('<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500;600&display=swap">')
    w(f'<style>{CSS}</style></head><body><div class="wrap">')

    # Header.
    w('<header class="top">')
    w(f'<p class="eyebrow">{esc(board["eyebrow"])}</p>')
    w(f'<h1>{esc(board["title"])}</h1>')
    w(f'<p class="lede">{esc(board["lede"])}</p>')
    w('<div class="meta">')
    for k, v in (
        ('Build', '26 · 1.0.0+26'),
        ('Rendered', when),
        ('Captured at', at),
        ('Plates', f'{len(plates)} · {new} new since 2 Sep'),
        ('Driven', f'{driven} of {len(plates)}'),
        ('Surface', board['surface']),
    ):
        w(f'<div><span class="k">{esc(k)}</span><span class="v">{esc(v)}</span></div>')
    w('</div></header>')

    # What changed.
    w('<section class="panel"><p class="eyebrow">Since the last board (2 Sep, build 12)</p>')
    w('<h2>What changed</h2><ul>')
    for line in board['changed']:
        w(f'<li>{esc(line)}</li>')
    w('</ul></section>')

    # Index.
    w('<section class="panel index"><p class="eyebrow">Reference</p><h2>Every plate has a code</h2>')
    w('<p class="sub">Say <code>C7</code> or <code>L5</code> and the screen is unambiguous. Codes are pinned to the screen, not to its position: a new screen gets a new code and a screen that no longer exists retires its code rather than handing it on.</p>')
    w('<div class="idx">')
    for act in captions['acts']:
        w(f'<div class="idx-col"><h3>{esc(act["title"])}</h3><ul>')
        for band in act['bands']:
            for code in band['plates']:
                p = plates[code]
                flag = '<span class="n">new</span>' if code in fresh else ''
                w(f'<li><a href="#{code}"><span class="k">{code}</span>{esc(p["name"])}{flag}</a></li>')
        w('</ul></div>')
    w('</div>')
    retired = board.get('retired', {})
    if retired:
        w('<p class="retired">Retired: ' + '; '.join(f'<code>{esc(c)}</code> {esc(t)}' for c, t in retired.items()) + '</p>')
    w('</section>')

    # Acts.
    for act in captions['acts']:
        w('<section class="act">')
        w(f'<div class="act-head"><span class="act-n">{esc(act["n"])}</span><div><h2>{esc(act["title"])}</h2>'
          f'<p class="act-sub">{esc(act["sub"])}</p></div></div>')
        w(f'<p class="act-lede">{esc(act["lede"])}</p>')
        for band in act['bands']:
            seq = band.get('sequence', False)
            w('<div class="band"><h3 class="band-t">')
            w(esc(band['title']))
            if seq:
                w('<span class="seq">' + ' → '.join(band['plates']) + '</span>')
            w('</h3><div class="sheet">')
            for i, code in enumerate(band['plates'], 1):
                p = plates[code]
                png = os.path.join(PLATES, p['file'] + '.png')
                data, iw, ih = webp(png)
                uri = 'data:image/webp;base64,' + base64.b64encode(data).decode('ascii')
                rec = state.get(p['file'])
                label = f'{p["name"]} ({code})'
                w(f'<figure class="plate" id="{code}"><div class="mount" tabindex="0" role="button" aria-label="Enlarge {esc(label)}">')
                w(f'<span class="code">{code}</span>')
                if seq:
                    w(f'<span class="step">{i}/{len(band["plates"])}</span>')
                w(f'<img src="{uri}" width="{iw}" height="{ih}" alt="{esc(p["name"])}" loading="lazy"></div><figcaption>')
                w(f'<p class="cap-name">{esc(p["name"])}</p><div class="tags">')
                w(f'<span class="tag {esc(p["how"])}">{esc(p["how"])}</span>')
                if p.get('platform'):
                    w(f'<span class="tag">{esc(p["platform"])}</span>')
                if p.get('size'):
                    w(f'<span class="tag">{esc(p["size"])}</span>')
                if code in fresh:
                    w('<span class="tag new">new</span>')
                w('</div>')
                if p.get('isnew'):
                    w(f'<p class="cap-new">{esc(p["isnew"])}</p>')
                w(f'<p class="cap-route">{route(p["reach"])}</p>')
                w(f'<p class="lbl">The job</p><p class="cap-job">{esc(p["job"])}</p>')
                w(f'<p class="lbl">Done right</p><p class="cap-done">{esc(p["done"])}</p>')
                for key in ('changed', 'note'):
                    if p.get(key):
                        w(f'<p class="cap-extra">{esc(p[key])}</p>')
                if rec:
                    w(f'<p class="cap-at">captured {esc(rec["sha"][:7])} · {esc(day(rec["captured"]))}</p>')
                else:
                    w('<p class="cap-at">not yet captured</p>')
                w('</figcaption></figure>')
            w('</div></div>')
        w('</section>')

    # How to read it.
    w('<section class="caveats"><h2>How to read a plate</h2><div class="cav">')
    for title, text in board['caveats']:
        w(f'<div><h3>{esc(title)}</h3><p>{esc(text)}</p></div>')
    w('</div></section></div>')
    w('<dialog class="lb" id="lb"><button type="button" id="lbx">Close ×</button><div class="inner"><img id="lbi" alt=""></div></dialog>')
    w(f'<script>{SCRIPT}</script></body></html>')

    page = '\n'.join(parts)
    with open(out, 'w', encoding='utf-8', newline='\n') as f:
        f.write(page)
    print(f'{out}: {len(plates)} plates, {len(page.encode("utf-8")) / 1_048_576:.1f} MB')


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--out', default=os.path.join(APP, 'plates', 'board.html'),
                    help='where to write the page (default plates/board.html, gitignored)')
    ap.add_argument('--stale', action='store_true',
                    help='list plates whose descriptions may have gone out of date')
    args = ap.parse_args()

    captions = load(CAPTIONS)
    if args.stale:
        return stale(captions, load(STATE))

    missing = [c for c, p in captions['plates'].items()
               if not os.path.exists(os.path.join(PLATES, p['file'] + '.png'))]
    if missing:
        print('No picture for ' + ', '.join(missing) + '. Regenerate the plates first:\n'
              '    flutter test test/plates/<file>.dart', file=sys.stderr)
        return 1
    build(args.out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
