# 0034 — A plan starts on the coming Monday

**Status:** Accepted

## Context

A plan was anchored to `mondayOf(now)` — the Monday of the week it was built in.
Built on a Friday, it opened with Monday to Thursday already behind it: four
days of a seven-day week gone, on the screen a runner had just asked for a plan
on.

Found by the build 12 field test on 2026-09-04 and held open since, recorded in
`plan_repository.dart` as *"a decision rather than a patch, because the fix is
the anchor and that changes what every plan looks like."*

## Decision

**A plan starts on the next Monday at or after the day it is built.** On a
Monday that is today; on a Friday it is three days away. `comingMondayFrom`
lives beside `mondayOf` in `stored_plan.dart`.

`PlanRules.rejectPastDays` needed nothing — it was already true everywhere but
adaptation, where it is off for a stated reason: a runner adjusting on Thursday
holds a week that already contains Monday.

## The alternatives, both real

**Exclude the past days the way race day is excluded.** Tried and reverted
before this session. It leaves week 1 with three usable days carrying a whole
week's prescribed volume — trading a week nobody can complete for a week nobody
should.

**Count the block backwards from race day**, which
[ADR-0027](0027-a-plan-ends-on-race-day.md) already claims it does. The more
correct fix and the larger one: it changes the shape of every generated plan
rather than only where it starts, and wants its own validation pass. Not taken
at submission time. It remains the answer if the disconfirming condition below
fires.

## Cost function

A plan that starts in up to six days, against a plan whose first week is already
spent. The delay is visible and explainable; the spent week is neither, and it
lands on a runner's first impression of the paid half.

## Consequences

**Every plan now spends its first days before its own start date**, and that
path was dead while the anchor was `mondayOf(now)`. Two things followed:

- `create` materialised `plan.weekOn(now)`, and `now` is now *before* the plan.
  For a rhythm that meant a brand-new plan materialising the last week of its
  cycle and then failing to find a next one to look ahead to. It asks
  `plan.startDate` instead, which is week 1 for either shape.
- `weekIndexOn` was **not** changed, and an attempt to clamp it was reverted. A
  progressing plan already clamps at 1; a rhythm's modulo wraps a negative index
  to the *last* week, and that is deliberate — it keeps `dateFor` an exact
  inverse, which `stored_plan_test.dart` pins as a round trip. For a plan whose
  weeks are all the same week, which index names it is a labelling question.

`home_shell.dart`'s missed-session rule no longer has past days to reason about,
and the gap comes off the test sheet's *"do not report these"* list.

Covered across all seven weekdays, because the defect was invisible on the two
the fixtures happened to use, plus the Monday boundary — "coming Monday" on a
Monday is today, or Monday becomes the one day you cannot start on.

## The disconfirming condition

Runners reporting that the plan feels like it has not started. If that happens
the anchor is wrong in the other direction, and counting back from race day
becomes the answer.

**Not yet judged on a phone.** Whether starting in up to six days reads as
sensible or as a delay is a product question a device answers, and this has only
been judged in tests.
