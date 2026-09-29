"""Build the voice-scribe field document from the repo's test sheet.

Generated, never hand-written. The sheet in `apps/mgk_run/docs/` stays the one
source and the place findings are finally written; this is transport, the same
relationship the published reading view has. Regenerate it per build rather than
editing it, or it becomes the second document carrying the same state -- which
is the failure this repository keeps paying for.
"""
import datetime
import os
import subprocess
import sys

SRC, OUT, BUILD = sys.argv[1], sys.argv[2], sys.argv[3]
sheet = open(SRC, encoding='utf-8').read()


def _git(repo, *args):
    """Run git in `repo`, or return None if it cannot answer."""
    try:
        done = subprocess.run(
            ('git', '-C', repo) + args,
            capture_output=True, text=True, check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    return done.stdout


# Which sheet this copy came from. A field document outlives the build it was
# generated for -- the sheet is rewritten per build, and the 2026-09-03 rewrite
# existed because the previous one told the tester to skip three surfaces the
# build shipped. A scribe holding a stale copy has to be able to see that it is
# stale, so the copy carries the commit it was cut from and the day it was cut.
REPO = os.path.dirname(os.path.abspath(SRC)) or '.'
SHA = (_git(REPO, 'rev-parse', '--short', 'HEAD') or 'unknown').strip()
# `--porcelain -- <path>` resolves the path against the CALLER's cwd, not
# against `-C`, so passing the sheet's own argv path reported clean while it
# was dirty -- the one case this marker exists for. Absolute, always.
DIRTY = (
    ' + uncommitted edits'
    if (_git(REPO, 'status', '--porcelain', '--', os.path.abspath(SRC)) or '').strip()
    else ''
)
GENERATED = datetime.date.today().isoformat()

PREAMBLE = f"""# MGKFitness: Run 1.0.0 — field test, build {BUILD}

**Generated {GENERATED} from `{os.path.basename(SRC)}` at commit
`{SHA}`{DIRTY}.** If that is not the commit you are working from, **this copy is
stale and should be regenerated rather than read** — the sheet is rewritten per
build, and a stale one tells you to skip what you came to test.

## Scribe brief — read this part, do not read it aloud

**You are the scribe for a live field test.** The person talking to you is
outdoors with a phone in one hand (an iPhone, an Android phone, or both in
turn), testing the app, and possibly running.
Everything below the line is the test sheet. Your job is to walk them through
it by voice and write down what they say — not to test anything yourself, and
not to fix anything.

## How to run the session

- **Speak briefly.** One prompt at a time, then stop and listen. They cannot
  scroll back through you.
- **Never read a table aloud.** Ask the question the row is asking, in your own
  words, in one sentence.
- **Follow *The running order*, not the section order.** The sections are
  printed by letter; the order they are done in is the numbered steps under
  *The running order*. Working the sections in printed order deletes an account
  before the purchase, which ends the afternoon.
- **Track where they are.** If they say "done with C", move to the next step of
  the running order and say which it is.
- They may go quiet for forty minutes mid-run. That is section F. When they come
  back, pick up where they left off rather than restarting.

## How to record

- **Every row starts as untested.** Mark a row `pass` only if they actually say
  it passed. Never infer a pass from silence, from a nearby answer, or from the
  absence of a complaint.
- **Some rows need a value, not a verdict** — they are listed under *Say these
  out loud*. For those, record what they actually said. If it is vague, ask
  **once** for the number or the wording, then write down whatever you get.
- **Do not debug and do not suggest fixes.** If something fails, capture it and
  move on. The one exception is a purchase (sections G and P): if one fails,
  ask them to read you the **ignore-reason string** from the `revenuecat`
  function log, because that screen looks identical for five different causes.
- **Capture "felt wrong but passed" verbatim.** Those are the most valuable
  thing on the sheet and the only findings it has no row for.

## What to produce at the end

When they say they are finished — or when they ask for it — output **exactly
this block and nothing else around it**. It gets pasted into a Claude Code
session that fills in the real sheet, so the shape matters more than the prose.

```
=== BUILD {BUILD} FINDINGS ===
half: free | paid | both
reached: <the last running-order step attempted>

<ROW ID>: pass
<ROW ID>: fail — <what happened, in their words>
<ROW ID>: <the value, for the value rows>

g-ignore-reason: <the exact string from the function log, or "n/a">
felt-wrong: <anything that passed but bothered them, one per line>
=== END ===
```

**Rows they never reached are simply absent.** Do not list them as untested and
do not pad the block — absence is the record, and a short honest block is worth
more than a complete-looking one.

**Nothing about a particular build lives in this brief.** What the build is,
which rows are new and what not to report are in the sheet's own *What build
{BUILD} is* and *Known gaps* sections, which are rewritten with it. This brief
used to carry two lines about build 14 and went on telling later scribes to
skip a row the later builds had.

---

"""

open(OUT, 'w', encoding='utf-8').write(PREAMBLE + sheet)
print('wrote', OUT)
