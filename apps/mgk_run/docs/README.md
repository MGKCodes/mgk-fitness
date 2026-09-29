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

Six documents, for two stores. They are six because they are read in different
places, not because the subject is large.

- **[app-store-1.0.0.md](app-store-1.0.0.md)** — **the plan, for both
  stores.** What is left, in order, and the gates behind it. Read at a desk.
  **This is the checklist and it carries the state.**
- **[store-setup.md](store-setup.md)** — **the Apple runbook.** Every field in
  App Store Connect and RevenueCat, including the submission forms and the
  review accounts, the five strings that must match exactly, and a table
  mapping each of the webhook's ignore-reasons to its cause. Read with a
  dashboard open, not at a desk.
- **[play-setup.md](play-setup.md)** — **the Google runbook.** Keystore,
  listing, Play Billing, RevenueCat's Google app, and every declaration Play
  Console asks for, with the answers. Read with Play Console open.
- **[app-store-listing.md](app-store-listing.md)** and
  **[play-listing.md](play-listing.md)** — **the copy itself.** Name, subtitle
  or short description, description, keywords, subscription text, review
  notes, and the one list of screenshots to shoot. Not writing *about* the
  listings — the listings, parsed by `tool/check_listing.py`, which fails on a
  character count, on a repeated keyword, on a claim the code does not
  support, or on anything Apple-only reaching the Android copy. They are
  source, and they do not merge into anything.
- **[testflight-1.0.0-test-sheet.md](testflight-1.0.0-test-sheet.md)** — **the
  form.** Carried to a phone, ticked, handed back. It is consumed rather than
  maintained, and it is rewritten per build rather than edited. Despite the
  name it covers both stores' test builds.

Supporting the same push:

- **[compliance.md](compliance.md)** — GDPR, health data, the sub-processor
  table, and what App Review asks about (the notes themselves are final in
  `app-store-listing.md`). The sub-processor table is the one that must agree
  with four other places; `legal_copy_test.dart` pins them together.
- **[openrouter-processor-agreement.md](openrouter-processor-agreement.md)** —
  an Article 28 obligation running in parallel, tracked because it has
  somebody else's clock on it.
- **[../../../store-assets/README.md](../../../store-assets/README.md)** — what
  App Store Connect will and will not accept as an image, and the script that
  checks it. Play's image rules are in `play-listing.md`.
- **[after-1.0.0.md](after-1.0.0.md)** — the edge of the same push. Two items
  from the build 12 field test that are **not** 1.0.0 scope because neither is
  specified — plan depth, and interactivity on the finish screen — one that is
  specified and was deferred on cost (heart rate and calories read from
  Health), and the list of things the 2026-09-29 pre-release review found and
  deliberately left for after launch, each with a date to revisit. It exists
  so none of them is mistaken for done or forgotten.

## Legal — written once, rendered three times

The source is here. `tool/build_legal_pages.py` generates both the published
web pages and the in-app copy from it, and `legal_copy_test.dart` asserts the
three renderings still agree word for word — because a reviewer compares them
and hand-maintaining the third is how they drift.

- **[privacy-policy.md](privacy-policy.md)**
- **[medical-disclaimer.md](medical-disclaimer.md)**
- **[terms-of-use.md](terms-of-use.md)** — our terms, served at `/run/terms`
  and linked from the paywall and Settings rather than rendered in the app
  ([ADR-0040](decisions/0040-our-terms-and-apples-eula.md)).

Generated, not edited: `legal-site/` here, and `web/public/run/` at the repo
root, which is what `mgkfitness.mgkcodes.com/run` serves.

## Decisions — the why

**[decisions/](decisions/)** — forty ADRs, 0001 to 0040, one file each.

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

## History — [`history/`](history/)

**Moved out of this directory on 2026-09-04, and the move is the point.** They
used to sit here alongside the live documents under a heading saying they were
stale, which is the same shape of protection this repository distrusts
everywhere else: a warning that depends on somebody reading a paragraph holds
until the next person. `docs/history/product-spec.md` cannot be mistaken for
current in a way `docs/product-spec.md` could.

Three documents, none maintained, none describing how the app behaves now:
`release-1.0.0.md`, `product-spec.md` and `design-system.md`.
[`history/README.md`](history/README.md) says what each one is for and why it
was kept rather than deleted.

Two things that read like history and stayed here, because other documents treat
them as live:

- **[roadmap.md](roadmap.md)** — the phased build order, reconciled against
  `app-store-1.0.0.md` rather than maintained beside it. Still cited as the
  source for pending work: the OpenRouter move is item 1, and Lift's template
  design is item 3.
- **[../CHANGELOG.md](../CHANGELOG.md)** — what shipped, when. A record that
  keeps being added to.

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
