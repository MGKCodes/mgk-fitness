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

- **[release-2.0.0.md](release-2.0.0.md)** — the plan to put `apps/mgk_lift` on
  the App Store and Google Play as Liftio 2.0.0, replacing the shipped Expo
  build at 1.4.0.
- **[testflight-2.0.0-test-sheet.md](testflight-2.0.0-test-sheet.md)** — the
  form. Carried to a phone, ticked, handed back.
- **[lift-2.0.0-logging-rework.md](lift-2.0.0-logging-rework.md)** — the
  logging rework, Phases 0 to 6, with its decisions D1 to D6.
- **[submission-week.md](submission-week.md)** — everything between the branch
  and two store submissions, with the per-store checklists.
- **[store-setup.md](store-setup.md)** and
  **[store-listing.md](store-listing.md)** — the dashboards, in order, and
  every listing and privacy field, drafted.
- **[design-review-2026-09-30.md](design-review-2026-09-30.md)** — Matthew's
  pass over the screen board: 19 findings, not yet planned.
- **[handover-2026-09-30.md](handover-2026-09-30.md)** — where to start the next
  session, and what is waiting on whom.

Both lived in the suite's `docs/` until 2026-09-03, not by choice but because
this directory did not exist. Root `docs/` now means the suite and nothing else.

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
