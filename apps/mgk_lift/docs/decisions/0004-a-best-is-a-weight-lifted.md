# 0004 — A personal best is a weight lifted, not an estimate

**Status:** Accepted (2026-10-12, issue #3)

## Context

Lift 2.0.0 measured a personal best on Epley's estimated one-rep max
(`weight × (1 + reps / 30)`, twelve reps or fewer). A set was a best when its
estimate went past every estimate before it. The bubble during a session and
the summary after it both said so: *"85 kg × 10, about 113 kg for one. Past
105 kg."*

That made the app announce bests nobody had lifted. 85 × 10 after a top set of
90 × 5 is a new best by the estimate (113 against 105) and a lighter weight by
the bar. And a movement's screen led with *Est. 1RM*, a number nobody loads,
in the tile beside *Heaviest*, so the estimate read as a best the lifter had
set.

Matthew's ruling on #3: *"PB toasts are only for sets with a new bigger weight
confirmation … the e1RM (and the extra rep range estimates) are just that,
estimates and to help guide the user, not tell them what their estimated PB
is."* Then: a best is also more reps at the current heaviest weight.

## Decision

**A personal best is a ticked working set that is heavier than any before it
on that movement, or as heavy for more reps.** `TrainingStats.topSet` finds a
movement's heaviest set and the most reps at that weight; `TopSet.beats`
compares two. Equal weights are equal within a gram, so 225 lb typed twice is
the same weight.

Unchanged: warm-ups never count, a movement with no history is not a best, and
matching a best is not setting one. The bubble and the summary share one rule
and one wording (`bestDetail`): *"92.5 kg × 3. Your heaviest yet, past 90 kg."*
or *"90 kg × 6. Your most reps at that weight, up from 5."*

**The estimate stays, as a guide.** It is the right tool for turning one set
into another, so it drives *Working weights* on a movement's screen (what to
load for 4–6, 7–11 and 12–16 reps) and the line of its progress over time. It
is never shown as a best, and no longer shown as a figure of its own.

## Consequences

- No more bests on a lighter weight. Somebody who does 85 × 10 after 90 × 5 is
  told nothing, which is true.
- High-rep work can now set a best: a heavier dumbbell for fifteens is
  heavier. 2.0.0 could not see it, because Epley stops at twelve.
- Bodyweight work still sets none. There is no weight to have gone past, and
  "more reps at 0 kg" would make every pull-up session a best.
- A best and the estimate can disagree, by design. A lifter can set a best
  while the estimate line goes down (a heavier single after a heavy five), and
  the line can go up with no best. They answer different questions.
- Bests already shown in 2.0.0 are not recomputed or withdrawn; nothing stored
  them. The rule applies from the next session.
