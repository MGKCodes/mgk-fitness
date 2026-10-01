# MGKFitness: Lift — documentation

Lift's own documents. Anything shared with Run is in the suite's
[`docs/`](../../../docs/) — the test is whether it would still be true if one
app were deleted.

Documents tier by **lifecycle, not topic**, the same rule Run follows:

| Tier | Changes | Answers |
|---|---|---|
| **Decisions** | Never — superseded, not edited | *Why is it this way?* |
| **Architecture** | Every time the code moves | *How does it work now?* |
| **Work** | Constantly, then stops | *What is left to do?* |

## Shipping 2.0.0

Open work. Start with the first.

**Lift's release is worked from these four files and nothing else.** Run's
plans, runbooks and checklists are not inputs to Lift's work and are not to be
read or edited for it; where a step touches something both apps share (a
secret, an account, a workflow file), the step says so itself. Lift's work
happens in its own worktree, never in a checkout another session is using
([CONTRIBUTING.md](../../../CONTRIBUTING.md), *Two sessions at once*).

- **[submission-week.md](submission-week.md)** — what is left before both
  store submissions, checked against the code, production and Codemagic on the
  date at its top. The one list to work from.
- **[store-setup.md](store-setup.md)** — the dashboards, in order. Matthew's.
- **[store-listing.md](store-listing.md)** — every listing and privacy field,
  drafted for pasting.
- **[testflight-2.0.0-test-sheet.md](testflight-2.0.0-test-sheet.md)** — the
  form. Carried to a phone with the release candidate, ticked, handed back.

Closed, and kept because the code and the screen board cite their decisions by
number:

- **[lift-2.0.0-redesign.md](lift-2.0.0-redesign.md)** — R1 to R13.
- **[lift-2.0.0-logging-rework.md](lift-2.0.0-logging-rework.md)** — D1 to D6.
- **[design-review-2026-09-30.md](design-review-2026-09-30.md)** — the nineteen
  findings the redesign answered.

## History

- **[history/](history/)** — frozen on 1 October 2026, when they described a
  branch and a payments plan that no longer existed: the first release plan,
  the September submission plan, the August punch list and the 30 September
  handover. None of it is maintained; the path is the warning.

## The screen board

The [Lift Screen Board](https://claude.ai/artifact/UZKDFbA8qht1Nj9TQ3dQB1) is
every screen as the app renders it. Three steps, from `apps/mgk_lift`:

```bash
flutter build web -t lib/preview/main.dart --release
PLAYWRIGHT_DIR='C:/…/boardtools' node tool/capture_screens_web.mjs
SHARP_DIR='C:/…/boardtools' CAPTURE_DATE=YYYY-MM-DD node tool/build_screen_board.mjs
```

Then republish `screenshots/screen-board.html` to the board's own link, so it
stays one place.

- `boardtools` is any folder where `npm install playwright sharp` and
  `npx playwright install chromium` have run. Use Windows-style paths: Node
  reads a Git Bash `/c/Users/…` as `C:\c\Users\…`.
- The builder refuses to run when `lib/preview/main.dart` and
  `tool/screen_board.json` disagree about which screens exist.
- Set `previous`, `since` and the `first` tags in the JSON for a round that
  adds screens.
- **One plate is timing-sensitive.** `session-summary-pb` shows the coach's
  bubble, which is on screen for under three seconds, and a capture that lands
  late photographs the screen without it. Compare that plate with the published
  one before republishing.

## Decisions

- **[decisions/](decisions/)** — Lift's own ADRs. Start with
  [0001 — Liftio is replaced, not relaunched](decisions/0001-liftio-is-replaced-not-relaunched.md).

Decisions that bind **both** apps mostly sit in Run's
[`decisions/`](../../mgk_run/docs/decisions/), which is where they accumulated
first — [ADR-0025, a coach conversation is a session](../../mgk_run/docs/decisions/0025-a-coach-conversation-is-a-session.md)
binds Lift as much as Run.

The index is [decisions/README.md](decisions/README.md), which also lists the
shared ones that live in Run's set.

## Not here yet

**Architecture.** Lift has no `architecture/` directory, so the as-built
picture lives in the suite's [`architecture.md`](../../../docs/architecture.md)
and [`database.md`](../../../docs/database.md) plus the code. Run's
[`architecture/`](../../mgk_run/docs/architecture/) is the shape to copy when
it is worth writing — and a caution about the cost of not maintaining it: four
of its six files have gone stale.
