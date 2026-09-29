#!/usr/bin/env python3
"""Count the store listing copy against each store's field limits.

    python tool/check_listing.py              # from apps/mgk_run
    python apps/mgk_run/tool/check_listing.py # or from anywhere

Reads `docs/app-store-listing.md` and `docs/play-listing.md` and exits non-zero
on an overrun, a missing disclosure, or a claim the code does not support.

**Why a script rather than eyes.** The limits are counted in characters, not
words, and the failure modes are asymmetric and both bad: the subtitle and
promotional text are *silently truncated* mid-word in search results, while
keywords and the description are *rejected* at upload. Neither is a thing to
find out on submission day, and neither is a thing a human counts reliably in a
90-character sentence with an em dash in it.

It also checks the two rules that are easy to get wrong and impossible to see:
keywords must not carry a space after the comma (the space is billed as a
keyword character), and no word may appear in both the name and the keywords,
because Apple indexes the name separately and a repeat wastes the field.

The description's limit is generous, so the useful number there is not whether
it fits but how much room is left for the paragraph somebody will want to add.

**The Play listing is checked for what is true on Android**, which is less
than on an iPhone: no Apple ID, no Apple Health, no iPhone. It must also carry
Google's health disclaimer word for word, and each subscription's description
must match the App Store one, because the paywall prints that field on both
platforms.
"""
from __future__ import annotations

import io
import os
import re
import sys

# Resolved from this file rather than the working directory, so the check runs
# the same from `apps/mgk_run` or from the repository root.
DOCS = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'docs')
DOC = os.path.join(DOCS, 'app-store-listing.md')
PLAY_DOC = os.path.join(DOCS, 'play-listing.md')

# Apple's limits, App Store Connect, checked 2026-09. If one of these changes,
# it changes here and nowhere else.
LIMITS = {
    'name': 30,
    'subtitle': 30,
    'promotional text': 170,
    'keywords': 100,
    'description': 4000,
    # The subscription localisation fields, which are an order of magnitude
    # tighter than everything above and are the ones that actually bite. The
    # first draft of both product descriptions ran to 82 and 99 characters.
    'subscription display name': 30,
    'subscription description': 45,
    # App Review Information > Notes.
    'review notes': 4000,
}

# Google Play's limits, Play Console, checked 2026-09.
PLAY_LIMITS = {
    'title': 30,
    'short description': 80,
    'full description': 4000,
    'subscription name': 55,
    'benefit': 40,
    'benefits per subscription': 4,
}

NAME = 'MGKFitness: Run'

# Google's Health Content and Services policy asks a health or fitness app's
# listing to carry this, verbatim. Apple does not; both listings do anyway.
HEALTH_DISCLAIMER = (
    'MGKFitness: Run is not a medical device and does not diagnose, treat, '
    'cure, or prevent any medical condition. Consult a healthcare professional '
    'for medical advice, diagnosis, or treatment.'
)

# What neither description may claim, because the code does not do it.
CLAIMS = [
    # Negation-aware, so "never writes to Health" -- the sentence App Review
    # wants to read -- is not mistaken for the claim it denies.
    (r"(?<!never )(?<!not )(?<!n't )\bwrit\w+ (it |them |runs )?(back )?to "
     r"(apple )?health",
     'the app only READS from HealthKit'),
    (r'\belevation\b', 'elevation is never recorded (ADR-0024)'),
    (r'heart rate|cadence', 'neither is captured by the recorder'),
    (r'\baudio\b|voice cue', 'in-run audio is deferred (ADR-0006)'),
    (r'\bstrava\b', 'ADR-0002 forbids naming it'),
    (r'apple watch app|watch app', 'there is no companion watch app'),
    # Until 2026-09-29 the description said runs from a watch arrived through
    # Apple Health. Nothing ever imported one, and WORKOUT is no longer asked
    # for (health_read_types.dart): Health is read for step count only.
    (r'\bwatch(es)?\b', 'nothing from a watch reaches the log'),
    (r'\bworkouts?\b', 'workouts are not read from Health'),
    (r'better model', 'Premium is the same model with more allowance (ADR-0038)'),
]


def flat(text: str) -> str:
    """Whitespace folded, so a phrase wrapped across lines still matches."""
    return ' '.join(text.split())


def fenced(md: str, after: str) -> str:
    """The first fenced block following a heading containing `after`."""
    i = md.lower().find(after.lower())
    if i < 0:
        raise SystemExit('no heading matching %r' % after)
    m = re.search(r'```[a-z]*\n(.*?)```', md[i:], re.S)
    if not m:
        raise SystemExit('no fenced block under %r' % after)
    return m.group(1).rstrip('\n')


def subtitles(md: str) -> list[tuple[str, str]]:
    """Every numbered subtitle candidate, with its backticked text."""
    i = md.find('## Subtitle')
    j = md.find('\n## ', i + 1)
    out = []
    for n, line in enumerate(md[i:j].split('\n'), 1):
        m = re.match(r'^(\d+)\. \*\*`([^`]+)`\*\*|^(\d+)\. `([^`]+)`', line)
        if m:
            out.append((m.group(1) or m.group(3), m.group(2) or m.group(4)))
    return out


def subscription_fields(md: str) -> list[tuple[str, str]]:
    """The display names and descriptions from the subscription table.

    Read out of the table rather than kept in a second list, so the counts and
    the copy cannot part company. A row looks like:

        | Coach | `Coach` (5) | `A training plan, ...` (37) |
    """
    # Anchored on the localisation table's own header, not merely on the
    # section: the tier table above it also has three columns and backticks,
    # and reading that one reported `paid` as a display name.
    i = md.find('| | Display name | Description |')
    if i < 0:
        raise SystemExit('no subscription localisation table found')
    j = md.find('\n## ', i + 1)
    out = []
    for line in md[i:j].split('\n'):
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if len(cells) != 3 or cells[0] in ('', '---') or '`' not in line:
            continue
        for kind, cell in (('display name', cells[1]), ('description', cells[2])):
            m = re.search(r'`([^`]*)`', cell)
            if m:
                out.append(('%s %s' % (cells[0].lower(), kind), m.group(1)))
    return out


def promo(md: str) -> str:
    i = md.find('## Promotional text')
    j = md.find('\n## ', i + 1)
    quoted = [l[2:].strip() for l in md[i:j].split('\n') if l.startswith('> ')]
    return ' '.join(quoted)


def play_subscriptions(md: str) -> dict[str, dict[str, list[str]]]:
    """Each `### <tier>` under `## Subscriptions`, as its `key: value` lines."""
    i = md.find('## Subscriptions')
    if i < 0:
        raise SystemExit('no ## Subscriptions in play-listing.md')
    j = md.find('\n## ', i + 1)
    section = md[i:j if j > 0 else len(md)]
    out: dict[str, dict[str, list[str]]] = {}
    for m in re.finditer(r'^### (.+?)\n.*?```[a-z]*\n(.*?)```', section, re.S | re.M):
        fields: dict[str, list[str]] = {}
        for line in m.group(2).split('\n'):
            if ':' in line:
                key, value = line.split(':', 1)
                fields.setdefault(key.strip().lower(), []).append(value.strip())
        out[m.group(1).strip()] = fields
    return out


def report(label: str, text: str, limit: int, fails: list) -> None:
    n = len(text)
    room = limit - n
    flag = 'OK ' if room >= 0 else 'OVER'
    if room < 0:
        fails.append('%s is %d over its %d limit' % (label, -room, limit))
    print('  %s %-28s %4d / %-4d  %+d' % (flag, label, n, limit, room))


def must_have(text: str, needles: list[tuple[str, str]], where: str,
              fails: list) -> None:
    for needle, why in needles:
        ok = flat(needle).lower() in flat(text).lower()
        print('  %s %s' % ('OK  ' if ok else 'MISS', why))
        if not ok:
            fails.append('%s is missing %s' % (where, why))


def no_claims(text: str, claims: list[tuple[str, str]], where: str,
              fails: list) -> None:
    for pattern, why in claims:
        hit = re.search(pattern, text, re.I)
        print('  %s %s' % ('MISS' if hit else 'OK  ', why))
        if hit:
            fails.append('%s claims %r, but %s' % (where, hit.group(0), why))


def check_app_store(md: str, fails: list) -> dict[str, str]:
    """The App Store listing. Returns the subscription descriptions by tier."""
    print('App Store: field lengths')
    report('name', NAME, LIMITS['name'], fails)
    for n, text in subtitles(md):
        report('subtitle %s' % n, text, LIMITS['subtitle'], fails)
    report('promotional text', promo(md), LIMITS['promotional text'], fails)

    descriptions: dict[str, str] = {}
    for label, text in subscription_fields(md):
        is_desc = 'description' in label
        limit = LIMITS['subscription description'] if is_desc \
            else LIMITS['subscription display name']
        report(label, text, limit, fails)
        if is_desc:
            descriptions[label[:-len(' description')]] = text

    kw = fenced(md, '## Keywords')
    report('keywords', kw, LIMITS['keywords'], fails)
    desc = fenced(md, '## Description')
    report('description', desc, LIMITS['description'], fails)
    notes = fenced(md, '## Review notes')
    report('review notes', notes, LIMITS['review notes'], fails)

    print('\nApp Store: keyword rules')
    if ', ' in kw:
        fails.append('keywords carry a space after a comma, which Apple bills')
        print('  OVER a space after a comma costs a character each time')
    else:
        print('  OK   no spaces after commas')

    words = {w.strip().lower() for w in kw.split(',')}
    name_words = {w.strip(':').lower() for w in NAME.split()}
    clash = {w for w in words if w in name_words}
    if clash:
        fails.append('keywords repeat the app name: %s' % ', '.join(sorted(clash)))
        print('  OVER repeats a word from the name: %s' % ', '.join(sorted(clash)))
    else:
        print('  OK   nothing repeated from the name')

    # A competitor's name in the keyword field is a rejection, and ADR-0002
    # makes this one specifically a thing we must never type.
    banned = {'strava', 'garmin', 'nike', 'runkeeper', 'apple'}
    named = {w for w in words if w in banned}
    if named:
        fails.append('keywords name another product: %s' % ', '.join(sorted(named)))
        print('  OVER names another product: %s' % ', '.join(sorted(named)))
    else:
        print('  OK   no other product named')

    print('\nApp Store: description must-haves')
    must_have(desc, [
        ('auto-renew', 'the auto-renew disclosure Apple requires'),
        ('Apple ID', 'where payment is charged'),
        ('cancel', 'how to cancel'),
        ('not medical advice', 'the medical disclaimer the app gates onboarding on'),
        (HEALTH_DISCLAIMER, "the health disclaimer, as Play's listing words it"),
        ('Apple Health', 'the HealthKit integration (Guideline 2.5.1)'),
        ('Privacy policy:', 'the privacy policy link'),
        ('Terms of use: https://mgkfitness.mgkcodes.com/run/terms',
         'our terms link (ADR-0040)'),
    ], 'the description', fails)

    print('\nApp Store: claims the code does not support')
    no_claims(desc, CLAIMS, 'the description', fails)

    print('\nApp Store: review notes')
    no_claims(notes, [c for c in CLAIMS if 'cadence' not in c[0]],
              'the review notes', fails)
    must_have(notes, [
        ('While Using', 'the location permission actually requested'),
        ('Before your coach answers', 'where the AI consent is asked'),
        ('press and hold', 'how a reply is reported'),
        ('Delete account', 'the in-app deletion path'),
    ], 'the review notes', fails)
    return descriptions


def check_play(md: str, apple_descriptions: dict[str, str], fails: list) -> None:
    print('\nGoogle Play: field lengths')
    report('title', fenced(md, '## Title'), PLAY_LIMITS['title'], fails)
    report('short description', fenced(md, '## Short description'),
           PLAY_LIMITS['short description'], fails)
    full = fenced(md, '## Full description')
    report('full description', full, PLAY_LIMITS['full description'], fails)

    subs = play_subscriptions(md)
    for tier, fields in subs.items():
        for name in fields.get('name', []):
            report('%s name' % tier.lower(), name,
                   PLAY_LIMITS['subscription name'], fails)
        benefits = fields.get('benefit', [])
        if len(benefits) > PLAY_LIMITS['benefits per subscription']:
            fails.append('%s has %d benefits; Play takes %d' % (
                tier, len(benefits), PLAY_LIMITS['benefits per subscription']))
        for n, benefit in enumerate(benefits, 1):
            report('%s benefit %d' % (tier.lower(), n), benefit,
                   PLAY_LIMITS['benefit'], fails)
            if re.search(r'£|\$|€|\bfree\b|\btrial\b', benefit, re.I):
                fails.append('%s benefit %r mentions a price or a trial, '
                             'which Play refuses' % (tier, benefit))

    print('\nGoogle Play: the paywall reads the same on both platforms')
    for tier, apple in sorted(apple_descriptions.items()):
        play = next((f.get('description', [''])[0] for t, f in subs.items()
                     if t.lower() == tier), None)
        ok = play == apple
        print('  %s %s: %r' % ('OK  ' if ok else 'MISS', tier, play))
        if not ok:
            fails.append('the Play description for %s is %r; the App Store one '
                         'is %r, and the paywall prints both' % (tier, play, apple))

    print('\nGoogle Play: full description must-haves')
    must_have(full, [
        (HEALTH_DISCLAIMER, "Google's health disclaimer, verbatim"),
        ('auto-renew', 'the auto-renew disclosure'),
        ('Google Play account', 'where payment is charged'),
        ('cancel', 'how to cancel'),
        ('AI', 'that the coach is an AI'),
        ('report', 'that an AI reply can be reported in the app'),
        ('Privacy policy:', 'the privacy policy link'),
        ('Terms of use: https://mgkfitness.mgkcodes.com/run/terms',
         'our terms link (ADR-0040)'),
    ], 'the Play description', fails)

    print('\nGoogle Play: nothing Apple-only, nothing Android does not do')
    no_claims(full, CLAIMS + [
        (r'\bapple\b|\biphone\b|app store|healthkit',
         'the Android listing names nothing of Apple\'s'),
        (r'health connect|\bsteps?\b',
         'Android reads no health data at all'),
    ], 'the Play description', fails)


def main() -> int:
    md = io.open(DOC, encoding='utf-8').read()
    fails: list[str] = []

    descriptions = check_app_store(md, fails)
    if os.path.exists(PLAY_DOC):
        check_play(io.open(PLAY_DOC, encoding='utf-8').read(), descriptions, fails)
    else:
        fails.append('docs/play-listing.md is missing')

    if fails:
        print('\n%d problem%s:' % (len(fails), '' if len(fails) == 1 else 's'))
        for f in fails:
            print('  - %s' % f)
        return 1
    print('\nAll fields fit, and nothing is claimed that the app does not do.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
