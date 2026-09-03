# MGKFitness: Run — documentation

Three kinds of document live here, and the difference between them is
**lifecycle, not topic**. Filing something in the wrong tier is how it goes
stale without anybody noticing.

| Tier | Changes | Answers | Where |
|---|---|---|---|
| **Decisions** | Never — superseded, not edited | *Why is it this way?* | [`decisions/`](decisions/) |
| **Architecture** | Every time the code moves | *How does it work now?* | [`architecture/`](architecture/) |
| **Work** | Constantly, then stops | *What is left to do?* | this directory |

A decision that gets edited loses the record of what was believed when it was
made — which is the only thing it was for. An architecture document that never
gets edited becomes a confident lie. A work document has an end date, and is
archived when it arrives rather than maintained forever.

**If two documents both carry state about the same work, one of them is
already wrong.** That is not a hypothetical: on 2026-09-03 this directory had
two checklists for the RevenueCat setup and they disagreed about whether a
CURRENT offering existed — the one disagreement that sends a sandbox failure
hunting in the wrong layer.

---

## Shipping 1.0.0 — the live set

Four documents. They are four because they are read in four different places,
not because the subject is large.

- **[app-store-1.0.0.md](app-store-1.0.0.md)** — **the plan.** Six gates,
  what is left, and the order to do it in. Read at a desk. **This is the
  checklist and it carries the state.**
- **[store-setup.md](store-setup.md)** — **the runbook.** Every field in App
  Store Connect and RevenueCat, the five strings that must match exactly, and a
  table mapping each of the webhook's ignore-reasons to its cause. Read with a
  dashboard open, not at a desk.
- **[app-store-listing.md](app-store-listing.md)** — **the copy itself.** Name,
  subtitle, promotional text, description, keywords. Not writing *about* the
  listing — the listing, parsed by `tool/check_listing.py`, which fails on a
  character count, on a repeated keyword, or on a claim the code does not
  support. It is source, and it does not merge into anything.
- **[testflight-1.0.0-test-sheet.md](testflight-1.0.0-test-sheet.md)** — **the
  form.** Carried to a phone, ticked, handed back. It is consumed rather than
  maintained, and it is rewritten per build rather than edited.

Supporting the same push:

- **[compliance.md](compliance.md)** — GDPR, health data, the sub-processor
  table, and the App Review notes. The sub-processor table is the one that must
  agree with four other places; `legal_copy_test.dart` pins them together.
- **[openrouter-processor-agreement.md](openrouter-processor-agreement.md)** —
  an Article 28 obligation running in parallel, tracked because it has
  somebody else's clock on it.
- **[../../../store-assets/README.md](../../../store-assets/README.md)** — what
  App Store Connect will and will not accept as an image, and the script that
  checks it.

## Legal — written once, rendered three times

The source is here. `tool/build_legal_pages.py` generates both the published
web pages and the in-app copy from it, and `legal_copy_test.dart` asserts the
three renderings still agree word for word — because a reviewer compares them
and hand-maintaining the third is how they drift.

- **[privacy-policy.md](privacy-policy.md)**
- **[medical-disclaimer.md](medical-disclaimer.md)**

Generated, not edited: `legal-site/` here, and `web/public/run/` at the repo
root, which is what `mgkfitness.mgkcodes.com/run` serves.

## Decisions — the why

**[decisions/](decisions/)** — thirty ADRs, 0001 to 0030, one file each.

Superseded rather than edited, so a superseded ADR is still worth reading: it
records what was believed at the time and what the alternative was. Start with
[the index](decisions/README.md).

## Architecture — the how

**[architecture/](architecture/)** — how the pieces fit.

- [Overview](architecture/overview.md) — system design
- [Data model](architecture/data-model.md) — schema and the offline-first mirror
- [Run recording](architecture/run-recording.md) — GPS capture, persistence, HealthKit dedup
- [Plan generation](architecture/plan-generation.md) — LLM proposal, deterministic validator
- [Onboarding](architecture/onboarding.md) — conversational slot-filling
- [LLM & secrets](architecture/llm-and-secrets.md) — the proxy, and keeping keys out of the client

⚠ **Four of these six have not been touched since 2026-08-06** and predate the
purchase arc, the session-bounded coach, and the two-moments onboarding. Read
them against [`decisions/`](decisions/), which is current, and fix what you find
rather than working around it.

## History — read as history

These describe how things got here. **None of them describes how the app
behaves now**, and each says so.

- **[release-1.0.0.md](release-1.0.0.md)** — the build that took Run from
  "records a run" to "somebody can hold it". Roughly twelve commits stale: its
  phases are ticked but the account-removal work and everything after it is
  missing.
- **[roadmap.md](roadmap.md)** — the phased build order. Reconciled against
  `app-store-1.0.0.md` rather than maintained beside it.
- **[product-spec.md](product-spec.md)** — **stale, and the most misleading
  document in the repository.** It is titled *Runio*, marked
  *Pre-alpha (design)*, and its decisions table promises HealthKit writes the
  app does not perform. It used to be named here as the source of truth, which
  is why the listing copy was written against the code instead. Read it for how
  the product was conceived, never for what it does.
- **[../CHANGELOG.md](../CHANGELOG.md)** — what shipped, when.
- **[design/design-system.md](design/design-system.md)** — superseded by
  `packages/mgk_ui`, which is the design system now rather than a description
  of one.

## Elsewhere in the repository

- **[../../../docs/](../../../docs/)** — the suite: `architecture.md`,
  `database.md`, `design.md`, `naming.md`, `navigation.md`, `plan-model.md`,
  `coach-profile.md`. Lift's release documents are also there, at the root
  rather than under `apps/mgk_lift/docs/`, which is an inconsistency rather
  than a rule.
- **[../../../CONTRIBUTING.md](../../../CONTRIBUTING.md)** — suite-wide
  conventions.
- **[../CLAUDE.md](../CLAUDE.md)** — the load-bearing rules for changing code
  in this app.
- **[../../../supabase/](../../../supabase/)** — the schema, the Edge
  Functions, and a README per function. The `coach` one is the longest document
  in the repository and worth reading before touching the coach.
