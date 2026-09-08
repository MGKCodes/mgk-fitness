# After 1.0.0 — the edge of the push

Two things came out of the build 12 field test on 2026-09-04 that **cannot be
built as written**, because neither of them is specified. They are not deferred
on merit and they are not rejected. They are held here because putting them on
[app-store-1.0.0.md](app-store-1.0.0.md) would make them look like work when
they are still only subjects, and a checklist row nobody can finish is a row
that never goes green.

**Everything else from that field test is 1.0.0 scope**, and it is tracked in
`app-store-1.0.0.md`, which is the only checklist carrying state. The defects
are recorded against their rows in
[testflight-1.0.0-test-sheet.md](testflight-1.0.0-test-sheet.md). Nothing on
this page is a defect and nothing on it blocks submission.

**This document exists so these are not mistaken for either done or
forgotten** — which is the only fate available to an unspecified item that lives
nowhere.

**A third entry was added on 2026-09-08 and is a different shape.** Heart rate
and calories from Health *is* specified; it is deferred on cost rather than
stranded on meaning. It is here because this is where the edge of the 1.0.0 push
is written down, and the filing rule below applies to it in one direction only:
it needs no specification, so it is ready to become work whenever the release
after this one has room.

It is a work document, so it has an end date: it ends when both entries have
either a specification or a written decision not to build them, and it is
archived then rather than maintained. See [the filing rule](README.md).

---

## 1. Plan depth

> *"Plan feature needs more depth generally."*

There is no acceptance criteria in that sentence, and no way to tell a finished
version from the one that shipped. Depth of **what** — more sessions in a week,
more variety across the block, a longer horizon, or an explanation attached to
each session saying why it is what it is? Those are four different builds, they
touch different halves of
[plan generation](architecture/plan-generation.md), and only one of them is
mostly a prompt change.

It also collides with the load-bearing rule that the model proposes and the
validator disposes: anything that adds depth adds structure the validator has to
be taught, and "more depth" does not say which.

## 2. Interactivity on the finish screen

> *"Finish/summary screen could use more interactivity."*

Recorded verbatim, and the tester said explicitly that it was **not specified
further**. Interactivity is a means rather than a requirement, so the half that
is missing is what it would be for: tapping a split to see where on the route it
was run, scrubbing the route against the pace trace, naming the run. Each is a
different screen and a different test, and nothing in the note chooses between
them.

Worth reading alongside the finish screen's one open question, which *is*
specified and *is* 1.0.0 scope: whether elevation reading "not recorded" on two
of six tiles looks deliberate or broken
([ADR-0024](decisions/0024-elevation-is-barometric-or-absent.md)). That one has
a decision to make. This one does not have a question yet.

## 3. Heart rate and calories, read from Health

**Unlike the two above, this one is specified.** It is here because it was
deferred on cost at submission time, not because nobody could say what it means.

The finished-run screen has `avgHr` and `caloriesEst` fields on `RunSummary`
and tiles ready to draw them. `recording_run_recorder.dart` never sets either,
so a recorded run shows neither, and the preview fixture that *does* fill them
is why the plate looked richer than the product. Same shape as the elevation
tiles and [ADR-0024](decisions/0024-elevation-is-barometric-or-absent.md): built
end to end, fed by nothing.

**The decision, taken 2026-09-08:** keep the tiles, populate them from HealthKit
over the run's own time window, and show an unavailable state otherwise. Not
built for 1.0.0.

**What it would have cost on submission day**, which is why:

1. **A wider permission sheet.** `HEART_RATE` and `ACTIVE_ENERGY_BURNED` join
   `kHealthReadTypes`, and that file's own doc says adding a type *"widens the
   sheet the runner is shown, so it is a product decision as much as a technical
   one"*.
2. **A regenerated and redeployed privacy policy.** The policy names exactly
   what health data is read; it is generated, and `legal_copy_test.dart` pins it
   word for word across three renderings — the source, `legal_copy.dart`, and
   the live `mgkfitness.mgkcodes.com/run/privacy`. All three move together.
3. **Changed App Privacy declarations** in App Store Connect, against a table
   [compliance.md](compliance.md) says must agree with four other places.

And it is iOS-only, so none of it can be exercised from Windows — it would have
reached a device untested, on a TestFlight list that already had 23 unproven
purchase rows on it.

**The acceptance criteria are already writable**, which is what makes this a
1.0.1 item rather than a subject: a run recorded in the app shows an average
heart rate and an energy figure matching what Health holds for the same window,
and shows an unavailable state on a phone that has neither.

---

## What has to happen before either becomes work

A specification, and it needs three things in this order:

1. **What somebody can do that they cannot do now** — one sentence, in the
   product's terms rather than the screen's.
2. **How you would know it was done.** This is the acceptance criteria, and it
   is what turns a subject into a row on a checklist.
3. **Which tier it lands in.** A change to what a plan contains is a decision as
   well as a build, so it wants an ADR in [`decisions/`](decisions/) before any
   code. A change to the finish screen may want neither.

Written that way, each becomes an item on the next release's plan. Written any
other way, it becomes a line somebody ticks without anybody having agreed what
it meant.
