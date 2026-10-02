#!/usr/bin/env python3
"""Build the submission sheet: every store field, ready to paste, in order.

    python tool/build_submission_sheet.py            # from apps/mgk_run
    python tool/build_submission_sheet.py --out x.html

Writes `../../store-assets/derived/submission-sheet.html`, a page with a Copy
button on every value and a tick against every step, in the order App Store
Connect and Play Console ask for them.

**It owns no copy.** Every value is read out of `docs/app-store-listing.md`,
`docs/play-listing.md`, `docs/store-setup.md` and `docs/play-setup.md` by the
same parsers `check_listing.py` counts with, so the sheet cannot say something
the docs do not. Change the docs, run the checker, build the sheet again.

**Why it exists.** The descriptions are hard-wrapped at eighty columns in the
docs, which is right for a file under review and wrong for a text box: pasted
as they stand, both stores would show a line break in the middle of every
sentence. The sheet unwraps them. And forty fields across two consoles is
where a submission gets a stale value typed from memory.

**It carries no passwords.** The review accounts' passwords are not in this
repository, so the review notes keep their `[PASSWORD_A]` and `[PASSWORD_B]`
placeholders and the sheet says to fill them in.

A missing field is an error, not a blank: the build stops and names it.
"""
from __future__ import annotations

import html
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
# No __pycache__ beside the tools: it is not ignored here, and is not wanted.
sys.dont_write_bytecode = True

import check_listing as listing  # noqa: E402  (the parsers, and the limits)

DOCS = os.path.join(HERE, '..', 'docs')
OUT = os.path.join(HERE, '..', '..', '..', 'store-assets', 'derived',
                   'submission-sheet.html')


def read(name: str) -> str:
    return io.open(os.path.join(DOCS, name), encoding='utf-8').read()


def need(pattern: str, text: str, what: str, flags: int = 0) -> str:
    m = re.search(pattern, text, flags)
    if not m:
        raise SystemExit('submission sheet: cannot find %s' % what)
    return m.group(1).strip()


def row(md: str, label: str) -> str:
    """The second cell of the table row whose first cell is `label`."""
    line = need(r'^(\| %s \|.*)$' % re.escape(label), md,
                'the table row %r' % label, re.M)
    return line.strip().strip('|').split('|')[1].strip()


def ticked(cell: str) -> str:
    """The backticked value in a table cell."""
    return need(r'`([^`]+)`', cell, 'a value in %r' % cell[:40])


def unwrapped(text: str) -> str:
    """A hard-wrapped description as a text box wants it.

    A paragraph becomes one line and a bullet becomes one line. A heading, a
    bullet's first line, a blank line and a `Label: https://` line each start
    afresh, so the two links at the foot stay on lines of their own.
    """
    out: list[str] = []
    for line in text.split('\n'):
        bare = line.strip()
        heading = bool(bare) and bare == bare.upper() and bare[0].isalpha()
        starts = (
            not bare
            or heading
            or line.startswith('- ')
            or re.match(r'^[A-Z][\w ]*: https?://', line) is not None
        )
        after_heading = (
            bool(out) and bool(out[-1]) and out[-1] == out[-1].upper()
            and out[-1][0].isalpha()
        )
        if starts or not out or not out[-1] or after_heading:
            out.append(bare if not line.startswith('- ') else line.rstrip())
        else:
            out[-1] += ' ' + bare
    joined = '\n'.join(out)
    # Nothing but the line breaks may have changed.
    if listing.flat(joined) != listing.flat(text):
        raise SystemExit('submission sheet: unwrapping changed the words')
    return joined


def build_number() -> str:
    spec = io.open(os.path.join(HERE, '..', 'pubspec.yaml'), encoding='utf-8').read()
    return need(r'^version:\s*\S+\+(\d+)', spec, 'the build number', re.M)


# --- the page ----------------------------------------------------------------

def esc(text: str) -> str:
    return html.escape(text, quote=True)


def inline(text: str) -> str:
    """A note's `code` and **bold**, and nothing else."""
    text = esc(text)
    text = re.sub(r'`([^`]+)`', r'<code>\1</code>', text)
    return re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', text)


class Sheet:
    def __init__(self) -> None:
        self.parts: list[str] = []
        self.ids: set[str] = set()
        self.section = ''

    def store(self, anchor: str, title: str, lead: str) -> None:
        self.parts.append(
            '<section class="store" id="%s"><div class="head"><h2>%s</h2>'
            '<p>%s</p></div>' % (anchor, esc(title), inline(lead)))

    def end_store(self) -> None:
        self.parts.append('</section>')

    def group(self, key: str, title: str, where: str) -> None:
        self.section = key
        self.parts.append(
            '<div class="group" data-group="%s"><div class="ghead"><h3>%s</h3>'
            '<span class="where">%s</span><span class="done" aria-live="polite">'
            '</span></div><ul>' % (key, esc(title), esc(where)))

    def end_group(self) -> None:
        self.parts.append('</ul></div>')

    def item(self, key: str, title: str, value: str | None = None,
             note: str = '', limit: int | None = None, tall: bool = False,
             kind: str = 'paste') -> None:
        ident = '%s-%s' % (self.section, key)
        if ident in self.ids:
            raise SystemExit('submission sheet: two items called %s' % ident)
        self.ids.add(ident)
        body = ''
        if value is not None and kind == 'paste':
            count = ''
            if limit is not None:
                if len(value) > limit:
                    raise SystemExit('submission sheet: %s is %d characters, '
                                     'over %d' % (ident, len(value), limit))
                count = '<span class="count">%d / %d</span>' % (len(value), limit)
            body = (
                '<div class="paste"><pre id="v-%s"%s>%s</pre><div class="tools">'
                '<button type="button" data-copy="v-%s">Copy</button>%s</div></div>'
                % (ident, ' class="tall"' if tall else '', esc(value), ident, count))
        elif value is not None:
            body = '<div class="answer %s">%s</div>' % (kind, inline(value))
        self.parts.append(
            '<li><label><input type="checkbox" id="c-%s"><span>%s</span></label>'
            '%s%s</li>' % (ident, esc(title), body,
                           '<p class="note">%s</p>' % inline(note) if note else ''))

    def html(self, build: str) -> str:
        return PAGE.replace('{{BUILD}}', esc(build)).replace(
            '{{BODY}}', '\n'.join(self.parts))


def build() -> str:
    apple = read('app-store-listing.md')
    play = read('play-listing.md')
    apple_setup = read('store-setup.md')
    play_setup = read('play-setup.md')
    number = build_number()

    limits, play_limits = listing.LIMITS, listing.PLAY_LIMITS
    subs = dict(listing.subscription_fields(apple))
    play_subs = listing.play_subscriptions(play)
    account_a = need(r'\*\*A\*\* `([^`]+@[^`]+)`', apple_setup,
                     "review account A's address")

    s = Sheet()

    # ---- App Store Connect ---------------------------------------------------
    s.store('app-store', 'App Store Connect',
            'In the order the site asks. The answers that are not copy are in '
            '`docs/store-setup.md` §10, section by section.')

    s.group('as-info', 'App Information', 'General ▸ App Information')
    s.item('name', 'Name', listing.NAME, limit=limits['name'])
    s.item('subtitle', 'Subtitle', listing.subtitles(apple)[0][1],
           limit=limits['subtitle'])
    s.item('category', 'Categories',
           'Primary **%s**, secondary **%s**' % (
               row(apple, 'Primary category'), row(apple, 'Secondary category')),
           kind='say')
    s.item('rights', 'Content Rights',
           '**Yes**, it contains third-party content, and **yes**, we have the '
           'rights (the map tiles are Esri\'s).', kind='say')
    s.item('age', 'Age Rating questionnaire',
           'Every answer is in `store-setup.md` §10, Age Rating. Expect **13+**.',
           kind='say')
    s.item('medical', 'Regulated Medical Device declaration',
           '**No**, it is not a regulated medical device. The page asks every '
           'app in Health & Fitness. Near the foot of App Information: '
           '**Declare Regulated Medical Device**.', kind='say')
    s.item('eula', 'License Agreement', "**Apple's Standard EULA.** Leave it.",
           kind='say')
    s.item('s2s', 'App Store Server Notifications, both URLs',
           '**RevenueCat\'s URL**, the same in Production and Sandbox, '
           '**Version 2**. Copy it from RevenueCat ▸ the App Store app ▸ Apple '
           'Server Notifications. Not our Supabase function. Review does not '
           'need it; refunds and cancellations reach us late without it.',
           kind='say')
    s.end_group()

    s.group('as-privacy', 'App Privacy', 'General ▸ App Privacy')
    s.item('policy', 'Privacy Policy URL',
           need(r'\*\*Privacy Policy URL\*\* `([^`]+)`', apple_setup,
                'the privacy policy URL'))
    s.item('choices', 'User Privacy Choices URL',
           need(r'\*\*User Privacy Choices URL\*\* \(optional\) `([^`]+)`',
                apple_setup, 'the privacy choices URL'))
    s.item('types', 'Data types',
           'Collects data: **Yes**. Tracking: **No**, for every type. The ten '
           'types and their purposes are the table in `store-setup.md` §10, '
           'App Privacy.', kind='say')
    s.end_group()

    s.group('as-subs', 'Subscriptions', 'Monetization ▸ Subscriptions')
    for tier in ('coach', 'premium coach'):
        s.item('%s-name' % tier.replace(' ', '-'),
               '%s: display name' % tier.title(),
               subs['%s display name' % tier],
               limit=limits['subscription display name'])
        s.item('%s-description' % tier.replace(' ', '-'),
               '%s: description' % tier.title(),
               subs['%s description' % tier],
               limit=limits['subscription description'],
               note='**The paywall prints this line**, so the old text would '
                    'show inside the app. Premium\'s changed on 30 September '
                    'and has to be changed here by hand.'
               if tier == 'premium coach' else '')
    s.item('review-shot', 'Review screenshot, on both products',
           '`Downloads\\run-iap-review-screenshot.png`', kind='file')
    s.end_group()

    s.group('as-version', 'The 1.0.0 version page', 'iOS App ▸ 1.0 Prepare for Submission')
    s.item('screens', 'Screenshots, iPhone 6.9" display',
           '`Downloads\\run-listing\\ios-still\\`, all six, in the order of '
           'their names (`1-run` first).', kind='file')
    s.item('promo', 'Promotional text', listing.promo(apple),
           limit=limits['promotional text'])
    s.item('description', 'Description',
           unwrapped(listing.fenced(apple, '## Description')),
           limit=limits['description'], tall=True)
    s.item('keywords', 'Keywords', listing.fenced(apple, '## Keywords'),
           limit=limits['keywords'])
    s.item('support', 'Support URL', ticked(row(apple_setup, 'Support URL')))
    s.item('marketing', 'Marketing URL',
           ticked(row(apple_setup, 'Marketing URL')),
           note='The site\'s home page. It is plain today and becomes the '
                'marketing page when that is built, at the same address.')
    s.item('version', 'Version', '1.0.0',
           note='The page offers `1.0`. The two are the same version to Apple; '
                'this is the one the store should show.')
    s.item('copyright', 'Copyright', ticked(row(apple_setup, 'Copyright')))
    s.item('build', 'Build', 'Choose build **%s**.' % number, kind='say')
    s.item('iap', 'In-App Purchases and Subscriptions',
           '**Add both**: Coach and Premium Coach. The section sits between '
           'Build and Game Center. **If it is not there**, open **Draft '
           'Submissions** at the foot of the page: the two may already be in '
           'the draft, and they go up with the version from there. If they are '
           'not, open Subscriptions and look for *Missing Metadata* on either '
           'product.', kind='say')
    s.item('group', 'The subscription group, into the same draft',
           'Subscriptions ▸ the **Run Coach** group ▸ **Add for Review** on the '
           'page of the group itself. Without it the draft says *"must be submitted '
           'with its subscription group"* and Submit for Review stays grey.',
           kind='say')
    s.end_group()

    s.group('as-review', 'App Review Information', 'the same page, further down')
    s.item('signin', 'Sign-in required: user name', account_a,
           note='The password is yours to type. It is not in the repository.')
    s.item('notes', 'Notes', listing.fenced(apple, '## Review notes'),
           limit=limits['review notes'], tall=True,
           note='**Replace `[PASSWORD_A]` and `[PASSWORD_B]`** after pasting, '
                'and nothing else.')
    s.item('contact', 'Contact information',
           'Your name, phone and email: whoever answers App Review.', kind='say')
    s.item('release', 'Version release',
           '**Manually release this version**, so approval does not publish it '
           'at whatever hour review finishes.', kind='say')
    s.end_group()

    s.group('as-submit', 'Add for Review', 'the button at the top')
    s.item('pricing', 'Pricing and Availability',
           'Price: **Free**. **Untick** "Make this app available" under Apple '
           'Silicon Mac, and "Make this app available on Apple Vision Pro": '
           'both arrive ticked, and the app is iPhone only.', kind='say')
    s.item('idfa', 'Advertising Identifier', '**No.**', kind='say')
    s.item('export', 'Export compliance',
           'Should not be asked. If it is, something changed in the build: stop.',
           kind='say')
    s.end_group()
    s.end_store()

    # ---- Play Console --------------------------------------------------------
    s.store('play', 'Google Play Console',
            '**Check the app named at the top right is MGKFitness: Run**; Lift '
            'lives in the same account. The declarations are the usual reason '
            'a first Play submission stalls. Their answers are in '
            '`docs/play-setup.md` §4.')

    s.group('gp-listing', 'Main store listing', 'Grow users ▸ Store presence ▸ Store listings ▸ Default store listing')
    s.item('title', 'App name', listing.fenced(play, '## Title'),
           limit=play_limits['title'])
    s.item('short', 'Short description',
           listing.fenced(play, '## Short description'),
           limit=play_limits['short description'])
    s.item('full', 'Full description',
           unwrapped(listing.fenced(play, '## Full description')),
           limit=play_limits['full description'], tall=True)
    s.item('icon', 'App icon', '`Downloads\\play-icon-512.png`', kind='file')
    s.item('feature', 'Feature graphic',
           '`Downloads\\play-feature-graphic.png`', kind='file')
    s.item('screens', 'Phone screenshots',
           '`Downloads\\run-listing\\play-still\\`, all six, in the order of '
           'their names.', kind='file')
    s.end_group()

    s.group('gp-settings', 'Store settings', 'Grow users ▸ Store presence ▸ Store settings')
    s.item('category', 'App category',
           '**%s**' % row(play, 'App category'), kind='say')
    s.item('email', 'Contact email', row(play, 'Contact email'))
    s.item('website', 'Website', row(play, 'Website'))
    s.end_group()

    s.group('gp-content', 'App content', 'Monitor and improve ▸ Policy and programs ▸ App content')
    s.item('policy', 'Privacy policy', row(play, 'Privacy policy'))
    s.item('access-name', 'App access: name of the instructions',
           need(r'- Name: `([^`]+)`', play_setup, 'the App access name'))
    s.item('access-user', 'App access: user name', account_a,
           note='The password is yours to type.')
    s.item('access-other', 'App access: any other information',
           listing.flat(need(r'Any other information: \*"(.+?)"\*', play_setup,
                             'the App access instructions', re.S)))
    s.item('deletion', 'Data safety: account deletion URL',
           need(r'deletion URL\s+`([^`]+)`', play_setup, 'the deletion URL'))
    s.item('fgs-task', 'Foreground service, location: the task',
           'Tick **Other** under *Background location updates*. Leave *Other '
           'tasks* unticked. The only field it opens is the video link; the '
           'description box belongs to the other tick.', kind='say')
    s.item('fgs-video', 'Foreground service: the video link',
           ticked(row(play_setup, 'Video')),
           note='On our own site. Recorded on an emulator from build 29\'s '
                'code; `play-setup.md` §4 says how.')
    s.item('rest', 'Every other declaration',
           'Ads **No**. Target audience **18 and over**. News **No**. '
           'Government **No**. Financial features **none**. Health apps: '
           '**Activity and fitness** only. Advertising ID **No**. Content '
           'rating and Data safety: the answers are tables in `play-setup.md` §4.',
           kind='say')
    s.end_group()

    s.group('gp-subs', 'Subscriptions', 'Monetize with Play ▸ Products ▸ Subscriptions ▸ each one')
    for tier, fields in play_subs.items():
        slug = tier.lower().replace(' ', '-')
        s.item('%s-name' % slug, '%s: name' % tier, fields['name'][0],
               limit=play_limits['subscription name'])
        s.item('%s-description' % slug, '%s: description' % tier,
               fields['description'][0])
        for n, benefit in enumerate(fields.get('benefit', []), 1):
            s.item('%s-benefit-%d' % (slug, n), '%s: benefit %d' % (tier, n),
                   benefit, limit=play_limits['benefit'])
    s.end_group()

    s.group('gp-production', 'Production', 'Publishing overview, then Test and release ▸ Production')
    s.item('managed', 'Managed publishing',
           '**Off for 1.0.0**, as the owner chose: the app goes live when '
           'Google approves it. On would hold it for a Publish button.',
           kind='say')
    s.item('countries', 'Countries / regions',
           'Production ▸ Countries / regions ▸ **Add countries / regions**, '
           'all of them, to match the App Store and the subscriptions (175).',
           kind='say')
    s.item('notes', 'Release notes, between the <en-GB> tags',
           listing.fenced(play, '## Release notes'), limit=500)
    s.item('promote', 'Promote the build',
           'Promote build **%s** from internal testing to Production, as a new '
           'release. It goes to review.' % number, kind='say')
    s.end_group()
    s.end_store()

    return s.html(number)


PAGE = r'''<title>Run Submission Sheet</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap">
<style>
  /* Layout: one column, two stores, each a run of groups in console order.
     A group is a list of steps: a tick, the field's name, and the value to
     paste. Single dark look on purpose: it is the app's own ground. */
  :root {
    color-scheme: dark;
    --ground: #1A1A1A;
    --panel: #232324;
    --well: #141415;
    --line: #3A3A3A;
    --ink: #FFFFFF;
    --silver: #C0C0C0;
    --dim: #8A8F98;
    --done: #9CC9A4;
    --type: 'Inter', system-ui, -apple-system, 'Segoe UI', sans-serif;
    --mono: ui-monospace, 'Cascadia Mono', Consolas, monospace;
  }
  body { background: var(--ground); color: var(--silver); font-family: var(--type); font-size: 15px; line-height: 1.55; padding-inline: 20px; padding-block: 40px 80px; }
  .page { max-width: 860px; margin-inline: auto; display: flex; flex-direction: column; gap: 48px; }
  header { display: flex; flex-direction: column; gap: 14px; }
  .eyebrow { font-size: 11px; font-weight: 700; letter-spacing: 0.22em; text-transform: uppercase; color: var(--dim); }
  h1 { margin: 0; font-size: clamp(28px, 5vw, 42px); line-height: 1.05; font-weight: 800; letter-spacing: -0.022em; color: var(--ink); text-wrap: balance; }
  h1 span { color: var(--silver); }
  h2 { margin: 0; font-size: 24px; line-height: 1.15; font-weight: 800; letter-spacing: -0.015em; color: var(--ink); }
  h3 { margin: 0; font-size: 16px; font-weight: 700; color: var(--ink); }
  p { margin: 0; max-width: 66ch; }
  strong { color: var(--ink); font-weight: 600; }
  code { font-family: var(--mono); font-size: 0.9em; color: var(--ink); overflow-wrap: anywhere; }
  nav { display: flex; flex-wrap: wrap; gap: 8px; }
  nav a { text-decoration: none; font-size: 13px; font-weight: 600; padding: 8px 14px; border: 1px solid var(--line); border-radius: 999px; color: var(--silver); }
  nav a:hover { color: var(--ink); border-color: var(--dim); }
  a:focus-visible, button:focus-visible, input:focus-visible { outline: 2px solid var(--ink); outline-offset: 3px; }
  .before { display: flex; flex-direction: column; gap: 8px; padding: 18px 20px; border: 1px solid var(--line); border-radius: 12px; }
  .before ul { margin: 0; padding-left: 18px; display: flex; flex-direction: column; gap: 6px; }
  .store { display: flex; flex-direction: column; gap: 28px; }
  .head { display: flex; flex-direction: column; gap: 6px; }
  .group { display: flex; flex-direction: column; gap: 4px; }
  .ghead { display: flex; flex-wrap: wrap; align-items: baseline; gap: 6px 14px; padding-bottom: 10px; border-bottom: 1px solid var(--line); }
  .where { font-size: 13px; color: var(--dim); }
  .done { margin-left: auto; font-size: 12px; font-weight: 600; font-variant-numeric: tabular-nums; color: var(--dim); }
  .done.all { color: var(--done); }
  .group ul { list-style: none; margin: 0; padding: 0; }
  .group li { display: flex; flex-direction: column; gap: 8px; padding: 14px 0; border-bottom: 1px solid var(--line); min-width: 0; }
  label { display: flex; align-items: flex-start; gap: 12px; cursor: pointer; font-weight: 600; color: var(--ink); }
  input[type="checkbox"] { width: 18px; height: 18px; margin: 2px 0 0; flex: 0 0 auto; accent-color: var(--silver); }
  li:has(input:checked) label span { color: var(--dim); text-decoration: line-through; }
  .paste, .answer, .note { margin-left: 30px; }
  .paste { display: flex; flex-direction: column; gap: 8px; min-width: 0; }
  pre { margin: 0; padding: 12px 14px; background: var(--well); border: 1px solid var(--line); border-radius: 8px; font-family: var(--type); font-size: 14px; line-height: 1.5; color: var(--ink); white-space: pre-wrap; overflow-wrap: anywhere; }
  pre.tall { max-height: 260px; overflow-y: auto; }
  .tools { display: flex; align-items: center; gap: 14px; }
  button { font: inherit; font-size: 13px; font-weight: 700; color: var(--ground); background: var(--silver); border: 0; border-radius: 999px; padding: 7px 16px; cursor: pointer; }
  button:hover { background: var(--ink); }
  .count { font-size: 12px; color: var(--dim); font-variant-numeric: tabular-nums; }
  .answer { font-size: 14px; }
  .answer.file::before { content: 'Upload'; display: inline-block; margin-right: 10px; font-size: 10px; font-weight: 700; letter-spacing: 0.16em; text-transform: uppercase; color: var(--dim); }
  .note { font-size: 13px; color: var(--dim); }
</style>

<div class="page">
  <header>
    <div class="eyebrow">MGKFitness: Run 1.0.0 · build {{BUILD}}</div>
    <h1>Every field, ready to paste. <span>Both consoles, in order.</span></h1>
    <p>Each value is read out of the listing docs, so it is what the checker counted. Ticks are kept in this browser only.</p>
    <nav aria-label="On this page">
      <a href="#app-store">App Store Connect</a>
      <a href="#play">Google Play Console</a>
    </nav>
  </header>

  <div class="before">
    <h3>Have these to hand</h3>
    <ul>
      <li>The pictures in <code>Downloads</code>: <code>run-listing\ios-still</code>, <code>run-listing\play-still</code>, <code>play-feature-graphic.png</code>, <code>play-icon-512.png</code> and <code>run-iap-review-screenshot.png</code>. To make them again: <code>python tool/export_store_assets.py --downloads</code>.</li>
      <li>The passwords of the two review accounts. They are not written here or in the repository.</li>
      <li>An Android phone on the Play build, for the foreground-service video Play asks for.</li>
    </ul>
  </div>

{{BODY}}
</div>

<script>
(function () {
  var KEY = 'run-submission-1.0.0';
  var saved = {};
  try { saved = JSON.parse(localStorage.getItem(KEY) || '{}') || {}; } catch (e) { saved = {}; }
  var boxes = Array.prototype.slice.call(document.querySelectorAll('input[type="checkbox"]'));

  function tally() {
    document.querySelectorAll('.group').forEach(function (group) {
      var all = group.querySelectorAll('input[type="checkbox"]');
      var done = group.querySelectorAll('input[type="checkbox"]:checked');
      var out = group.querySelector('.done');
      out.textContent = done.length + ' of ' + all.length;
      out.classList.toggle('all', done.length === all.length);
    });
  }

  boxes.forEach(function (box) {
    if (saved[box.id]) box.checked = true;
    box.addEventListener('change', function () {
      saved[box.id] = box.checked;
      try { localStorage.setItem(KEY, JSON.stringify(saved)); } catch (e) {}
      tally();
    });
  });
  tally();

  document.querySelectorAll('button[data-copy]').forEach(function (button) {
    button.addEventListener('click', function () {
      var pre = document.getElementById(button.getAttribute('data-copy'));
      function say(word) {
        button.textContent = word;
        setTimeout(function () { button.textContent = 'Copy'; }, 1600);
      }
      function select() {
        var range = document.createRange();
        range.selectNodeContents(pre);
        var selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        say('Selected: press Ctrl+C');
      }
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(pre.textContent).then(function () { say('Copied'); }, select);
      } else {
        select();
      }
    });
  });
})();
</script>
'''


def main() -> int:
    out = OUT
    if '--out' in sys.argv:
        i = sys.argv.index('--out')
        if i + 1 >= len(sys.argv):
            raise SystemExit('--out needs a file')
        out = sys.argv[i + 1]
    page = build()
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    io.open(out, 'w', encoding='utf-8', newline='\n').write(page)
    print('submission sheet -> %s (%d steps)' % (
        os.path.abspath(out), page.count('type="checkbox"')))
    return 0


if __name__ == '__main__':
    sys.exit(main())
