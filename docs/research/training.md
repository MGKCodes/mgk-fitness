# Training claims this app is built on

Every training rule in the code traces to a claim here. Each claim carries what
it rests on, how confident that is, when it was last checked, and — the part
that matters — **what breaks if it turns out to be wrong**.

This file exists because a claim got stale inside a fortnight of being used.
`TrainingSplit` and `PlanShape` were both written citing "twice a week beats
once a week", which is a real 2016 finding that a later review by the same group
substantially walked back. The code did not say where the claim came from, so
nothing pointed at what to re-check.

**Re-check anything older than a year.** Training science moves slowly, but it
moves, and a dated claim is one somebody can audit. An undated one is folklore.

---

## C1 — Weekly volume is the main driver of hypertrophy

**Claim.** Hypertrophy follows weekly hard sets per muscle in a dose–response,
with diminishing returns. Somewhere around 12–20 sets per muscle per week is a
reasonable working range for a trained lifter.

**Confidence.** High for the direction, moderate for the numbers. The
dose–response is consistent; the exact band is a summary of noisy data and
varies by muscle, individual and how "hard set" is defined.

**Rests on.** Schoenfeld et al., dose–response meta-regressions on weekly volume
and frequency ([SportRxiv](https://sportrxiv.org/index.php/server/preprint/view/460));
systematic review of resistance training volumes and hypertrophy
([PMC8884877](https://pmc.ncbi.nlm.nih.gov/articles/PMC8884877/)).

**Last checked.** 2026-08-20.

**Depends on it.** `PlanShape.minWeeklySets` / `maxWeeklySets`, and the
`setsPerMovement` assumption used to estimate weekly sets from a plan.

**If it is wrong.** The volume bounds are wrong and plans get accepted or
rejected on a bad number. The bounds are deliberately wide guard rails rather
than a prescription, so being somewhat off is survivable.

---

## C2 — Frequency, with volume equated, does little on its own

**Claim.** Once weekly volume is held constant, splitting it across more
sessions has little independent effect on hypertrophy.

**Confidence.** Moderate-to-high, and **this supersedes what this app was
originally built on.**

**Rests on.** Schoenfeld, Ogborn & Krieger (2016) found 2×/week beat 1×/week
([Sports Medicine 46:1689–1697](https://link.springer.com/article/10.1007/s40279-016-0543-8)),
but that analysis carried a known confounder: several of the higher-frequency
groups also did more weekly volume, and there were too few volume-equated
studies to separate the two. A later systematic review of 25 studies by the same
group found **no significant difference on a volume-equated basis**
([PubMed 30558493](https://pubmed.ncbi.nlm.nih.gov/30558493/)).

**Last checked.** 2026-08-20.

**Depends on it.** Nothing directly, and that is the point — no rule in this app
should say "train it twice because twice is better".

**Correction history.** Until 2026-08-20, `TrainingSplit` and `PlanShape` both
cited the 2016 result as though it were current. See C3 for the argument that
actually survives.

---

## C3 — One session a week is a poor way to deliver a week's volume

**Claim.** A muscle needing 12–20 hard sets a week is badly served by one
session, because sets late in a long session are performed under accumulated
fatigue and contribute less than the same set fresh.

**Confidence.** Moderate. This is a practical corollary rather than a directly
tested finding, and it is the honest justification for the rule the app
enforces — **not** C2, which says frequency itself is close to neutral.

**Rests on.** The volume dose–response in C1, plus the within-session fatigue
argument. Weaker evidence than C1; stated as reasoning rather than a result.

**Last checked.** 2026-08-20.

**Depends on it.** `PlanShape`'s rule that a muscle trained at volume must get
at least two exposures a week.

**If it is wrong.** The two-exposure rule becomes an arbitrary constraint that
rejects otherwise fine plans — a bro split being the obvious case. Worth
revisiting if anybody complains about it, because the rule is stricter than C2
justifies on its own.

---

## C4 — Varying exercises does not beat repeating them

**Claim.** Rotating movements and keeping the same ones produce similar
hypertrophy and strength. Variation has value against staleness and overuse, but
is not itself a growth stimulus.

**Confidence.** Moderate.

**Rests on.** Systematic review on varying resistance exercises
([ResearchGate](https://www.researchgate.net/publication/358212528_Does_Varying_Resistance_Exercises_Promote_Superior_Muscle_Hypertrophy_and_Strength_Gains_A_Systematic_Review));
practitioner synthesis on variation as planned rather than reactive
([Biolayne](https://biolayne.com/reps/issue-7/exercise-variation-for-strength-and-hypertrophy-change-is-not-always-good/)).

**Last checked.** 2026-08-20.

**Depends on it.** `MovementSlot.hasStalled` — main lifts never rotate,
accessories become eligible after six sessions without improvement.

**If it is wrong** — that is, if variation *does* drive growth — the rotation
interval is too conservative and slots should turn over faster.

---

## C5 — Progressive overload is necessary

**Claim.** Training has to get harder over time — load, reps, or sets — for
adaptation to continue.

**Confidence.** High. As close to settled as this field gets.

**Rests on.** Broad consensus; see the load-versus-repetition progression
comparison ([PMC9528903](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9528903/)),
which finds both routes work.

**Last checked.** 2026-08-20.

**Depends on it.** `SessionPrescription`'s progression rule, and the whole
argument that a movement you keep replacing cannot be progressed because there
is no previous number to beat.

---

## Not a research claim: how a week is shaped

**`TrainingSplit.forDays` is arithmetic, not evidence.** Five training days
does not divide into a three-day Push/Pull/Legs rotation: pinned to fixed
weekdays it comes out P, P, L, P, P, and legs is trained once that week. That
follows from the model, not from a study, and the earlier commit message that
attributed it to "the evidence" was wrong.

**A known modelling limit.** A plan here is a fixed set of weekdays, so a
*rolling* cycle — PPL repeating every third session regardless of what day it
lands on, which is how plenty of people actually run it — cannot be expressed at
all. Anybody training five days a week on a rolling PPL is served an
upper/lower instead. That is a real limitation rather than a considered
position, and it is worth revisiting before anybody calls the planner finished.
