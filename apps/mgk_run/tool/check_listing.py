#!/usr/bin/env python3
"""Count the App Store listing copy against Apple's field limits.

    python tool/check_listing.py

Run from `apps/mgk_run`. Reads `docs/app-store-listing.md` and exits non-zero on
an overrun.

**Why a script rather than eyes.** Apple's limits are counted in characters, not
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
"""
from __future__ import annotations

import io
import os
import re
import sys

DOC = os.path.join('docs', 'app-store-listing.md')

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
}

NAME = 'MGKFitness: Run'


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


def report(label: str, text: str, limit: int, fails: list) -> None:
    n = len(text)
    room = limit - n
    flag = 'OK ' if room >= 0 else 'OVER'
    if room < 0:
        fails.append('%s is %d over its %d limit' % (label, -room, limit))
    print('  %s %-28s %4d / %-4d  %+d' % (flag, label, n, limit, room))


def main() -> int:
    md = io.open(DOC, encoding='utf-8').read()
    fails: list[str] = []

    print('Field lengths')
    report('name', NAME, LIMITS['name'], fails)
    for n, text in subtitles(md):
        report('subtitle %s' % n, text, LIMITS['subtitle'], fails)
    report('promotional text', promo(md), LIMITS['promotional text'], fails)

    for label, text in subscription_fields(md):
        is_desc = 'description' in label
        limit = LIMITS['subscription description'] if is_desc \
            else LIMITS['subscription display name']
        report(label, text, limit, fails)

    kw = fenced(md, '## Keywords')
    report('keywords', kw, LIMITS['keywords'], fails)
    desc = fenced(md, '## Description')
    report('description', desc, LIMITS['description'], fails)

    print('\nKeyword rules')
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

    print('\nDescription must-haves')
    for needle, why in [
        ('auto-renew', 'the auto-renew disclosure Apple requires'),
        ('Apple ID', 'where payment is charged'),
        ('cancel', 'how to cancel'),
        ('not medical advice', 'the medical disclaimer the app gates onboarding on'),
        ('Privacy policy:', 'the privacy policy link'),
        ('Terms of use:', 'the terms link'),
    ]:
        ok = needle.lower() in desc.lower()
        print('  %s %s' % ('OK  ' if ok else 'MISS', why))
        if not ok:
            fails.append('description is missing %s' % why)

    print('\nClaims the code does not support')
    for pattern, why in [
        (r'writ\w+ (it |them |runs )?(back )?to (apple )?health', 'the app only READS from HealthKit'),
        (r'\belevation\b', 'elevation is never recorded (ADR-0024)'),
        (r'heart rate|cadence', 'neither is captured'),
        (r'\baudio\b|voice cue', 'in-run audio is deferred (ADR-0006)'),
        (r'\bstrava\b', 'ADR-0002 forbids naming it'),
        (r'apple watch app|watch app', 'there is no companion watch app'),
    ]:
        hit = re.search(pattern, desc, re.I)
        print('  %s %s' % ('MISS' if hit else 'OK  ', why))
        if hit:
            fails.append('description claims %r, but %s' % (hit.group(0), why))

    if fails:
        print('\n%d problem%s:' % (len(fails), '' if len(fails) == 1 else 's'))
        for f in fails:
            print('  - %s' % f)
        return 1
    print('\nAll fields fit, and nothing is claimed that the app does not do.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
