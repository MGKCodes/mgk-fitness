# The MGK Fitness profile, and what the coach is allowed to know

Written while designing the coach's second half. The first half — that it
remembers you between conversations — shipped on 2026-08-07 and is described in
[roadmap.md](roadmap.md) item 2. This is the other half: **what it knows about
you before you tell it anything**, and where that lives.

Nothing here is built. It is written first because three of the decisions are
hard to reverse once a migration lands, and one of them is a legal obligation
rather than a preference.

> **2026-08-28: still true, and it now costs something.** Lift's plan intake
> was designed around seven questions — the four training ones, and the three
> body facts below. The four shipped; the three were cut, because there is no
> `core.body_metrics`, no `height_cm` and no `year_of_birth` for their answers
> to land in, and asking a question whose answer is dropped on the floor is
> worse than not asking it. The control is not the blocker: `CoachAsk` and the
> coach screen's wheel already ask for all three, and ship. **What §1 is
> waiting on is the table.** When it lands, `IntakeField` is where the three
> questions go back, and `intake_flow_test.dart` has a test that fails when
> they do.


---

## 1. The profile is the parent. The apps are children of it.

**There is one person and there are several apps.** You are a certain age, a
certain height and a certain weight, and none of those become different facts
because you opened a different binary. A goal does: "get stronger" is a Liftio
sentence, and Runio has no business reading it as though it meant the same
thing.

So the split is not "shared things and private things". It is **the body versus
the training**:

| Lives in | Holds | Why there |
|---|---|---|
| `core` | weight over time, height, year of birth | Properties of the person. True in every app, editable from any of them. |
| `lift` | primary goal, days available, experience | Properties of a training plan. Meaningless to a runner. |
| `run` | its own goals, in its own vocabulary | Same, mirrored. |

This is the existing schema decision — *"One schema per domain, and the coach
belongs to nobody"* — applied one level further down. It also removes a question
that looked real and was not: whether the two apps should share a goal
vocabulary with per-app subsets. They should not share it at all, so there is
nothing to subset.

### Year of birth, not age, and not a full date

**Age is a value that is wrong for up to a year and never says so.** Store the
input, derive the output. That much is ordinary.

Year rather than a full date of birth is the same minimisation argument that
governs everything below: programming cares whether somebody is thirty or sixty,
not whether their birthday has passed. A full date is more personal data
carrying no more usable signal, and asking for it invites the question of why.

### Weight is a series, not a field

A goal of "lose weight" or "gain weight" cannot be served by a single number,
and neither can a coach that is supposed to notice things. `core.body_metrics`
is rows with a `recorded_at`, the same shape `core.progress_photos` already
uses, with a latest-value view for the callers that only want today's.

The difference this makes is not storage. It is that a trend becomes something
the coach **observes** rather than something it was once told.

---

## 2. It is collected in conversation, and corrected as prose

**The coach asks.** Not a form with five fields — a coach that opens with a
questionnaire is a form wearing a coach's voice, and the product's claim is that
it answers back.

Corrections go to Settings, where `CoachMemoryScreen` already shows what the
coach has kept and clears it. Body facts belong on that surface rather than in a
second one beside it, because a lifter deciding what to share needs one place
that answers "what does it know".

### The record stays typed underneath

"Editable as text" and "the planner needs `weight_kg` as a number" are both
true, and the gap between them is where this goes wrong. Someone will edit the
prose to `I'm 82 now`.

**Structured record, prose presentation.** An edit goes through the coach, which
extracts the fields and writes them — the same mechanism that already writes
`coach.summaries`, so no new machinery. The alternative, parsing prose at plan
time, turns a typo into bad programming silently and a fortnight later.

---

## 3. Nothing is collected until something needs it

**A tracking-only lifter is never asked for their weight**, because nothing they
use consumes it. GDPR's minimisation rule is that personal data must be limited
to what is necessary for the purpose; there is no purpose here until there is a
plan to build.

This resolves a tension that is easy to miss. "Conversational onboarding" sounds
like first-run, and first-run happens to everybody — so an onboarding that asks
for height and weight would collect health data from people who will never have
a coach. **The coach's onboarding is therefore the plan path, not app install.**

That also lines up with the two rules already in force: tracking is never gated,
and the coach is the paid half. The purpose is established at the moment of
collection rather than argued for afterwards.

---

## 4. A lapsed subscription retains. Only a person deletes.

**Erasing on lapse was rejected.** It is the tidiest privacy story and the worst
product one: somebody who resubscribes in March should not have to re-tell a
coach about the shoulder they described in January. Re-collection is not a
neutral cost when the thing being re-collected is an injury history.

So the data is kept, and **the obligation moves to disclosure**. Retention that
is not erasure has to be stated, bounded and honoured.

### The period needs a reason, not a number

Twelve months is the proposal, and the justification is what makes it lawful
rather than the figure: training is seasonal, lapses commonly run a few months,
and a training history is only worth anything with continuity. A year covers the
realistic return without keeping data against a person who has gone for good.

**This is the one open item that cannot ship unanswered**, because the privacy
policy has to say it. What that policy must state:

- what is held (weight history, height, year of birth) and why (to build and
  adapt a training plan),
- that it is retained after a subscription lapses, for how long, and on what
  reasoning,
- that deletion is available on request and in the app, and takes effect on
  both,
- that it is shared between MGK Fitness apps, which is the point of the account.

I have not drafted policy text. That is an outward-facing legal document and
wants your name on the wording.

### Deletion is user-initiated, and already half-built

`core.delete_account(p_user_id, p_app)` exists, is `service_role` only, and
already scopes a partial deletion to one app while reporting whether the login
can go. In-app account deletion is not optional for the App Store either —
Guideline 5.1.1(v) requires it wherever an app supports account creation.

---

## 5. Runio asks before it assumes

> "I detected your MGK Fitness account — are these details still right?"

**Correct, and not merely polite.** Technically the row is in `core` and Runio
may simply read it. But an app volunteering your weight when you never told
*that* app your weight reads as surveillance, even when it is the same account
and the same company. The acknowledgement is what turns a shared backend from
something that happened to you into the reason you have an account.

It also does real work: it is the moment stale data gets corrected, by the app
that noticed it was stale.

Which app has acknowledged the profile is state about the profile, so it belongs
next to it — `core.profile_acknowledgements (user_id, app, acknowledged_at)`
rather than a flag hidden in each app's schema.

---

## 6. The trap: `core` is not swept by construction

`core.delete_account` erases the app schemas by **enumerating every table with a
`user_id` column**, and its own comment says so with some pride: *"a table added
later is covered by construction."*

**`core` does not work that way.** Its shared rows are a hard-coded list —
`core.progress_photos`, `core.user_settings`, `core.profiles`
(`20260807140000_delete_account_scopes_the_coach.sql:178-180`).

So `core.body_metrics` and `core.profile_acknowledgements` will **silently
escape account deletion** unless that list is edited in the same migration that
creates them. A deletion that reports success while retaining health data is the
worst available failure: it is invisible, it is the exact thing a person asked
for, and it is the one that carries a fine.

Two options, and the first is a stopgap:

1. Add the tables to the list, and accept that the next person to add a `core`
   table has the same trap waiting.
2. Give `core` the same enumeration the app schemas get, with an explicit
   exclusion list for the rows that must outlive a partial deletion.

The second is the real fix and is a small change to a function that already has
ten functional tests behind it.

---

## Open

- **The retention period.** Twelve months, or another number with a better
  reason. Blocks the privacy policy, which blocks collecting anything at all.
- **Whether height belongs in the series or beside it.** Adults stop changing
  height; teenagers do not, and the app does not currently ask anybody's age
  before it would need this answer.
- **What Runio's coach does when the answer is "no, that's wrong".** Correcting
  it there writes to `core` and changes what Liftio's coach believes, which is
  right, and worth being deliberate about rather than incidental.
