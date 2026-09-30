# Architecture Decision Records — Lift

An ADR captures a significant decision, the context that forced it, and the
consequences we accept. They are immutable once accepted — if a decision
changes, add a new ADR that supersedes the old one rather than editing history.

## Format

Each record uses: **Status · Context · Decision · Consequences.**

## Index

| # | Decision | Status |
|---|---|---|
| [0001](0001-liftio-is-replaced-not-relaunched.md) | Liftio is replaced, not relaunched | Accepted |
| [0002](0002-a-coach-conversation-is-a-session.md) | A coach conversation is a session, bounded by silence | Accepted |
| [0003](0003-exercise-illustrations-are-cc-by-sa.md) | The exercise illustrations are CC BY-SA 4.0, not first-party | Accepted |

## Decisions that bind Lift but live in Run's set

Run's [`decisions/`](../../../mgk_run/docs/decisions/) is where the shared ones
accumulated first, because Run was documented first rather than because they
belong to it:

- [0005 — AGPL-3.0 with DCO sign-off](../../../mgk_run/docs/decisions/0005-license-agpl.md),
  which [0003](0003-exercise-illustrations-are-cc-by-sa.md) carves an exception
  out of.
- [0025 — A coach conversation is a session, bounded by silence](../../../mgk_run/docs/decisions/0025-a-coach-conversation-is-a-session.md).
- [0030 — The coach is the paid half, on both apps](../../../mgk_run/docs/decisions/0030-the-coach-is-the-paid-half.md).
- [0042 — A screen that leads with its photograph may carry it at strength](../../../mgk_run/docs/decisions/0042-a-screen-that-leads-with-its-photograph.md):
  Track and Sign in, from the redesign's R1.
