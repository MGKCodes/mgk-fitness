# 0011 — A plan has a shape

**Status:** Accepted

## Context

Runio assumed every runner is training for a dated race. Not as a decision —
nobody weighed it — but as an inheritance. [onboarding.md](../architecture/onboarding.md)
listed "event / target date" among the **required** slots, and four layers took
that as a type constraint: `IntakeSlots.missingRequired` demands it,
`RunnerProfile.eventDate` is non-nullable, `plans.event_date` is a non-null
column, and `buildSkeleton` counts backwards from it to decide how long the
block is.

The product spec compounded it, describing the Plan surface as working "for any
distance and **any block length**". The flexibility anyone considered was how
long the block runs, never whether there is one.

The consequence is a real runner the app cannot serve. Someone who runs their
local parkrun every Saturday and wants it timed has a training intent, a
schedule, and questions for a coach — and cannot complete onboarding, because
`IntakeSlots.isComplete` never returns true without an event date. The coach
would circle back to "when is your race?" until it hit the turn cap. The app not
listening, in the first conversation it ever has with them.

They are not an edge case. Neither is the runner who wants to run a marathon
"one day" with no race entered, nor the one who only wants their runs recorded.

## Decision

**A plan has a shape, and every shape is a plan.** There is no "no plan" state
for a runner who has told us anything about what they want. Four shapes:

| Shape | Target | Date | Training arc | Position is measured by |
|---|---|---|---|---|
| **Block** | yes | yes | ramp → peak → taper | week *n* of *N* |
| **Rhythm** | optional | no | hold a repeating pattern | consistency |
| **Horizon** | yes | none yet | ramp toward readiness | progress to ready |
| **Log** | no | no | none | nothing; the run log stands alone |

Four, because these are the combinations that change what the app must *do* —
what a week contains, which invariants apply, and what the coach is told. They
are not personas. A first 5 km with a date entered is a Block; the same runner
without one is a Horizon; "get back into it" is a Rhythm. Adding personas would
add rows without adding behaviour.

Consequences that follow:

- **`goalDistanceMeters` and `eventDate` become optional** on `RunnerProfile`
  and on the stored plan (a schema migration, additive and nullable).
- **The required-slot set is a function of the shape.** A Rhythm runner is never
  asked for a date, because there is not one. This stays in Dart, where the slot
  state has always lived (ADR-0003) — the fix for a bad required-set is a better
  required-set, not a model told to be lenient.
- **Validator rule sets are per shape.** Taper applies only to a Block; it is
  meaningless without an endpoint. Ramp and deload apply to Block and Horizon.
  A Rhythm's invariant is that the week matches the rhythm committed to, which
  is a far smaller rule set — applying the block rules to "5 km every Saturday"
  would reject a perfectly good plan.
- **The shape is model-proposed and Dart-validated**, like everything else. The
  model naming "block" does not make it one: if there is no date, it is a
  Horizon. A model under pressure will confidently pick the wrong shape, and
  that is precisely the class of error the validator exists to catch.
- **Consistency is a first-class measure, not a game.** For a Rhythm there is no
  volume ramp and no date to count down to; whether the runner has been showing
  up *is* the training state. A count of it ("parkrun, 14 this year") is the
  same class of thing as "week 1 of 16" — the runner's position in their own
  training. It is not the streak that
  [the product spec puts out of scope](../history/product-spec.md#8-out-of-scope), which
  is a reward mechanic: no badge, no penalty for breaking it, nothing unlocked.
  That line is amended to say so, because as written it would keep regenerating
  this argument.

**The shape must never reach the presentation layer.** The week list, session
brief, calendar and chat take a week and render it; none of them branch on
shape. A shape decides what is *in* a week, never what a week looks like. The
failure this forbids is four half-maintained Coach tabs, and it is the
constraint most likely to erode first — every shape-specific `if` in a widget is
this decision being lost.

## The obvious alternative

Keep one shape, and let everyone else use the app without a plan: log runs, ask
the coach questions, skip the Plan surface.

Rejected because it is what the app does today, and it is why this ADR exists.
It reads to the runner as a permanent empty state — the Coach tab currently
greets them with "No plan — that's fine" above a button offering to build one,
which is an apology dressed as a choice. It also strands the coach: with no
plan there is nothing to adapt, nothing to explain, and no week to reason about,
so the one feature these runners *would* use is the one most degraded.

## Cost function

Judge this by whether a runner who never enters a race gets a Coach tab worth
opening every week — a week with something in it, and a coach that never asks
about a race they have not got. If Rhythm runners still read as second-class,
the shape system has been implemented but not honoured.

The counter-signal to watch is `if (shape == ...)` appearing in
`lib/src/features/coaching/presentation/`. One is a smell; three means the
constraint above has failed and the surfaces are diverging.

## Disconfirming condition

Reverse this if the shapes stop differing in what they *do*. If Rhythm and
Horizon converge on the same weeks, the same invariants and the same brief, they
are one shape with two labels and should be collapsed — the point of four is
four behaviours, not four names.
