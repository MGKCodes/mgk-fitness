# Roadmap — worked through, 2026-08-07

Written at the end of the session that built photos, sync, auth and the coach;
finished the same day. **All five items are done.**

It said to delete this file once it had been worked through. It is kept instead,
because three of the five were settled DIFFERENTLY from how they were written
and the reasoning is worth more than the plan was:

1. **The coach move to OpenRouter** was a reunification, not a rewrite — the
   proxy already existed and had been orphaned.
2. **The template picker shrank rather than went.** Removing it would have made
   the free app worse at the problem it exists to solve.
3. **The load rule became a schema property rather than a prompt instruction**,
   which is the difference between asking a model to behave and making
   misbehaviour unrepresentable.

It is all on production as of 2026-08-07 — four migrations applied and the
coach function deployed. What is left is in
[Carried-over debt](#carried-over-debt), and the entry that matters most is
`COACH_MODEL_ALLOWLIST`, which is live and lets a client pick a model eight
times the price of the default.

For what the app now IS, see [architecture.md](architecture.md),
[database.md](database.md) and [navigation.md](navigation.md).

---

## 1. Move the coach to OpenRouter — **done, 2026-08-07**

It turned out not to be a rewrite. The repo already contained a complete
OpenRouter proxy, inherited from Runio in the initial commit — `limits.ts`,
`usage_store.ts`, `surfaces.ts` and 76 tests — and commit `c2c792b` had
overwritten `index.ts` with a Lift-only Anthropic handler that imported none of
it. So item 1 was really **reunification**, and doing it the roadmap's way
would have written a second limiter next to the good one.

What was actually wrong, and is now fixed:

- Deploying that `index.ts` would have **broken Runio's coach**. One function
  per slug per project, and Runio's repo still defines the same slug — the
  arrangement that caused the account-deletion bug.
- **Lift's rate limiting did not work.** It called `usage_window(p_user_id,
  p_hours)` with no `.schema('coach')`; the real function is
  `coach.usage_window(p_user, p_since)`. `.rpc()` returns `{data, error}`
  rather than throwing, so `used` was null, the cap never bound, and no usage
  row was ever written. Both failures were silent.

The shape now: one function, both apps. `lift_chat` is a surface alongside
Run's, with its own persona and its own rate window. Which app pays is read
from `SURFACES[name].app`, never from the request, and resolves through
`core.entitlements` — which also gave Runio the real tier lookup its code had
been hard-coding to `free`.

**The `coach.models` table was dropped.** `modelFor` already routes per surface
and per tier through `COACH_MODEL` / `COACH_CHAT_MODEL`, and `supabase secrets
set` changes the model with no code change, which is the property that was
actually wanted. A table would have bought a per-request read and a second
place for the config to be wrong.

Cross-provider fallback is on. It was already OpenRouter's default, so
`allow_fallbacks: true` in `PROVIDER_ROUTING` changes no behaviour — it makes
the decision visible and testable, which is the point, because the other two
flags in that object narrow which providers are eligible to fall back to. A
coach that fails because one provider is down is a coach that fails on a Monday
evening; one that falls back to a provider training on injury notes is worse.

---

## 2. Persistent coach memory — **done, 2026-08-07**

The point was never transcript storage. It is that **the coach should know a
lifter after three months** — that they train four days, that their left
shoulder complains on overhead work, that they respond to volume and not to
intensity. That is what makes it a coach rather than a chat window over a
database.

### One thing the roadmap had wrong

The tables were not "unused". Runio is live on them — `coach_memory_mirror.dart`,
`coach_memory.dart`, its own memory migration — and **`coach.summaries` was
keyed on `user_id` alone**. Lift writing a memory would have silently replaced
the running one on any account that used both apps, and been replaced back the
next time they talked to the running coach. Special-category data, no earlier
version to restore, and nothing visible at the point of loss.

`20260807130000_coach_memory_per_app.sql` widens the key to `(user_id, app)`
and adds the same column to `coach.conversations`. `coach.turns` deliberately
does not get one: it reaches its app through its conversation FK, and a second
copy of that fact could disagree with the first.

Verified locally: `supabase db reset` replays every migration onto a clean
database, `supabase test db` passes 27/27, and Runio's app-less upsert was
POSTed at local PostgREST twice to prove it still updates its own row rather
than 409ing on the widened key. **Not yet applied to production.**

**`supabase/config.toml` was exposing only `public` and `graphql_public`**,
which is why none of this could be tested locally before today: every request
to `core`, `coach`, `lift` or `run` came back `PGRST106 Invalid schema`, which
`classifyFailure` reads as "the limiter is not installed" and the coach fails
closed on. Fixed in the same commit. It has to stay in step with the dashboard's
Settings → API → Exposed schemas.

### What is built

1. **Every turn is written** to `coach.turns`, both sides, ordered by `seq` —
   by the Edge Function, not the client, so the app cannot put words in the
   coach's mouth and then ask it to act on them. That also replaced the
   client-side history the previous session added: two sources of truth for a
   transcript is one too many.
2. **The rolling memory** is regenerated by `lift_summarise` once the
   transcript has run 20 turns ahead of it, inline on the turn that trips it.
3. **Each request sends** the memory plus the last 20 turns, read alongside the
   log in one parallel round trip.

### The three decisions, as settled

- **Retention and deletion.** Settings → Coach shows the memory in full with
  when it was last written, and offers to forget it — conversations and memory
  together, confirmed first, with the dialog saying plainly that the training
  log is untouched and the account stays. `20260807140000` also scopes
  `core.delete_account` to the new column, so deleting one app's data now takes
  that app's coach data with it. That was the GDPR gap
  `20260806130300_account_deletion.sql` named and could not close, and
  `supabase/tests/delete_account.sql` asserts both directions — the departing
  app's memory gone, the remaining app's kept — plus a bystander account left
  alone. Confirmed failing against the pre-change function before it was fixed.
- **What the memory may contain.** Constrained in `lift_summarise`'s prompt to
  what the lifter said rather than what the model concluded. No inference about
  their state of mind, nothing about their body or how they look, and nothing
  the database already holds. The reason it is constrained that hard is the next
  decision.
- **Editable: no.** The memory is rewritten from the transcript when it falls
  behind, so an edit would be reverted within a few conversations — a text field
  would be a promise the coach does not keep. Since the only control is erasure,
  the prompt carries the whole burden of being fair, and the screen says so
  rather than leaving the missing control looking like an oversight.

`coach.usage` deliberately survives a partial deletion: it holds no content,
self-prunes at 31 days, and erasing it would make deleting one app double as a
spend-cap reset.

### What is left

Nothing in this item. Two things it touched are worth carrying forward:

- The memory is **session-visible but not yet resumable** — reopening the app
  gives an empty screen and a coach that still knows you. That is defensible and
  documented in `coach_screen.dart`, but showing the stored transcript on open
  is a small job now that it exists.
- The regeneration is **inline**, so about one turn in twenty pays for a second
  short call. `EdgeRuntime.waitUntil` is the upgrade if that is ever felt.

---

## 3. Coach-generated plans — **done, 2026-08-07**

The biggest of the four. **The half where being wrong is expensive and
invisible is built**; what is left is app wiring.

### Built, 2026-08-07

- `lift.plans` / `plan_weeks` / `plan_sessions` (`20260807150000`), with
  `supabase/tests/lift_plans.sql` asserting the invariants by trying to break
  them. `plan_sessions.workout_id` is the join that makes "did they do the
  plan" answerable, and it is `ON DELETE SET NULL` so tidying the log cannot
  punch holes in the block.
- The three generation surfaces: `lift_intake`, `lift_skeleton`, `lift_week`.
- `PlanValidator`, which grades a proposed week and derives every target.
- `lift_swap`, below.

**The decision everything else hangs off: `lift_week` has nowhere to put a
weight.** The rule is that targets come from what the lifter has actually
lifted, and a prompt asking a model to honour that is a request where a schema
with no field for a kilogram is a guarantee. The model prescribes an intensity;
Dart resolves it against their own estimated 1RM, rounds to 2.5 kg, and returns
nothing when there is no qualifying set behind it. A null target is a real
prescription — "3×8, leave two in the tank" — and it is the common case for a
lifter a fortnight in, which is worth knowing when reading the Plan surface's
"targets come from what you have actually lifted".

### Also built

- **Generation orchestration** — `PlanGenerator` lays out the arc then fills
  the first two weeks, retrying a rejected week once with its own `violations`
  as the brief. Not the whole block: eight weeks generated on day one is eight
  weeks of guesses about a lifter nobody has watched train.
- **Persistence and the accept** that makes a draft `active`.
- **The intake conversation, the draft review, and Track's "Next up".**
- **Adaptation** — `lift_adapt` returns a DIFF, which is the representation the
  roadmap said it needed. Four changes (move, lighten, drop, swap a movement),
  each checked against the plan, each ticked individually. A finished session is
  never editable: it happened, and rewriting it would make the log a lie.
- **`active_session_screen.dart`'s contradiction is resolved.** A template still
  adds movements and no numbers; a planned session fills the weights in, because
  those came from the lifter's own logged sets rather than from a list written
  for nobody. Both rules are now written down next to each other.

### Mid-session swaps — `lift_swap`

Added 2026-08-07, on request: while training, "I don't like barbell bench
press, can we swap it out or do something else instead."

The only Lift prompt handed something by the client rather than reading it —
the session in progress, which is not a record yet. The device owns it until it
is finished (ADR-0004), so there is nothing to read and nothing to
misrepresent. It is rendered with what has already been done ("2 of 3 sets"),
because swapping the third set is a different question from swapping before the
first.

Same load rule, and this is where it matters most: a substitute is usually
something they have never done, which is exactly when a number would have to be
invented. It differs from the week validator in one deliberate way — unusable
options are **dropped and the rest kept**, because the lifter is standing
between sets. The reply always survives.

**The coach proposes; nothing moves until the lifter taps one.** Both halves of
applying it are wired, and this section said otherwise until 2026-08-07 — it
described the state at the time the prompt landed and was not revisited when
the app side followed an hour later. Check `_swap` and `_recordSwap` rather
than this paragraph.

`ActiveSessionScreen._swap` removes the old movement and seeds the new one's
sets the way a planned session's are — reps in, weight in when the coach could
derive one, blank when it could not. `LiftShell._recordSwap` then writes the
change back to `lift.plan_sessions`, because a plan that kept the original
would go on claiming they did something they swapped out. A failure there is
swallowed on purpose: the session is right either way, only the plan's copy is
behind, and that is not worth interrupting a workout for.

### The original plan for the templates, and what happened instead

**The template picker goes away as a user-facing feature.** Today
`template_picker_sheet.dart` offers 15 templates and 8 splits, and the lifter
chooses. That becomes the coach's raw material instead: the templates encode
what a sensible session looks like — push/pull/legs, upper/lower, full body,
the movement ordering, the compound-before-accessory rule — and the coach
composes from those known-good shapes rather than inventing a session from
nothing.

**Settled differently, 2026-08-07: the picker shrank rather than went.** Six
templates are offered — push, pull, legs, upper, lower, full body — and all
fifteen stay as the coach's material. Removing it entirely would have made the
free app worse at the blank-session problem it exists to solve, and tracking is
free. `offeredSplits` is derived from `offeredTemplates` rather than listed, so
the picker can never show a split whose Tuesday opens a hidden session.

This mirrors a decision already in the brain for Frunt: *"Templates: hidden
grounding layer, never a user-facing library."* Same reasoning, different
product.

### What a plan is

Mirror `run.plans` / `run.plan_weeks` / `run.plan_sessions`, which already
solve this exact problem for running and are worth copying rather than
re-deriving:

- `lift.plans` — one active per user (partial unique index on
  `status = 'active'`, as Run has), holding the goal, the start date, the
  number of weeks, the days available, and the intake answers.
- `lift.plan_weeks` — week number, phase (`base` / `build` / `peak` /
  `deload`), and the intent for that week.
- `lift.plan_sessions` — the unit that matters: scheduled date, weekday, a
  `kind`, the movements with target sets/reps/load, a `rationale`, a `status`
  (`planned` / `completed` / `skipped`), and a `workout_id` FK that gets set
  when the session is actually trained.

That last column is the join that makes the whole thing work: it is how "did
they do the plan" is answerable without guessing.

### How generation runs

1. **Intake as conversation, not a form.** The Plan surface already shows a
   mocked-up version of this. Goal, days per week, days unavailable,
   equipment, injuries. The model asks; the lifter answers in their own words.
2. **Structured output, not prose.** The generation call returns the plan as
   JSON matching the tables above. Prose that has to be parsed back into a
   schedule is how a plan generator becomes flaky.
3. **Targets come from their own numbers.** This is the actual advantage over
   a template and should be treated as the requirement it is: the estimated
   1RM machinery already exists in `TrainingStats`, and a plan that prescribes
   "3×5 @ 85kg" derived from a real logged set is a different product from one
   that says "3×5 heavy".
4. **The lifter approves before it is active.** Generated, shown, accepted —
   not generated and imposed.

### How a planned session becomes a tracked one

Track's "Next up" card shows today's planned session. Starting it pre-fills
the movements *and* the targets, and `plan_sessions.workout_id` is set on
finish.

Note this **changes an existing rule**. `active_session_screen.dart` currently
says a template adds movements and no numbers, because "a template says what to
do, not what to lift, and pre-filling weights would be the app asserting
something only the lifter knows." That reasoning holds for a static template
and stops holding for a coach that has read the log. Update the comment when
the behaviour changes, rather than leaving two contradictory rules in the code.

### Adaptation

"Shoulder is sore, can we move Thursday?" — the Plan surface already promises
this in its sales copy, so it is a claim with a deadline. The coach proposes a
diff to the upcoming week; the lifter approves it. Needs a proposal
representation that is not just a regenerated plan, or every small change
rewrites the block and loses the history of what was actually done.

### What the free tier keeps (decided)

A free lifter can still **build their own workout plans**, and still gets the
whole picture of their training — sessions, history, stats, photos. What they
do not get is **help deciding what to do and when to do it**.

So the picker does not simply vanish. It stops being the headline and becomes
the manual path: free lifters assemble a session themselves, paid lifters have
one assembled for them and adapted week to week. Removing it outright would
make the free app worse in order to sell the paid one, which is the opposite
of the positioning in *Tracking is never gated; the coach is the paid half*.

What changes for a paid lifter is that Track stops asking them to choose. The
plan already knows what today is.

---

## 4. Navigation audit — **done, 2026-08-07**

[navigation.md](navigation.md) is the inventory. The gap it found was the one
the roadmap predicted: **the active session had no back affordance at all**, so
the only exits were Finish (disabled until a set is ticked) and Discard at the
foot of a list. It has a back arrow now, deliberately unguarded — the session is
already persisted and Track offers to resume it.

Sign in and plan intake now block back while a request is in flight. The coach
screen and the sheets deliberately do not, and the doc says why.

### As originally written

Every screen needs an obvious way in, an obvious way back, and an obvious next
step. Some of this is already right and some is not; it has never been checked
as a whole.

Known so far:

- The screens pushed from Settings and Profile get a Material `AppBar` with a
  back arrow for free. Those are fine.
- `ActiveSessionScreen` has **no back affordance at all** — no `AppBar`, and
  the only exits are Finish (disabled until a set is ticked) and Discard. The
  Android system back gesture works, but nothing on screen says so, and a
  lifter who opened a session by accident has to find "Discard session" at the
  bottom of a list.
- `CoachScreen`, `PhotosSurface`, `PoseSeriesScreen`, `SeriesPlaybackScreen`
  and `SignInScreen` all have app bars, but none has been checked for what
  happens on back mid-action — mid-upload, mid-reply, mid-playback.
- The three shell surfaces have no back, correctly, being tab roots.

Do this as a pass over the whole app with a written inventory: for each screen,
how you get in, how you get out, what the next action is, and what back does if
something is in flight. The preview harness already enumerates every screen,
so it is the natural checklist.

---

## 5. Redesign the Track surface — **done, 2026-08-07**

Done after plans existed, as the item itself advised — the plan is the content
that fills it, and redesigning it empty would have meant designing it twice.

Three changes. Today's planned session is on it. An interrupted session says
what it was and how far in, because a different button label was not enough for
the one state where somebody has genuinely lost their place. And three figures
about their actual training — sessions this week, week streak, when the last one
was — absent rather than zeroed on an empty log, because three noughts on day
one reads as a scoreboard somebody is already losing.

**Then it was looked at on a device, which found more.** The rules that came
out of that pass are in [design.md](design.md); what they cost on this screen
was a headline that repeated the label of the card beneath it, and a
`hasOpenSession` bool the screen branched on separately from the session it was
derived from. Both are gone.

The general lesson is principle 9 and it is the one worth carrying forward:
`flutter analyze` and widget tests proved every one of these screens correct
while five of them had layout faults, because **neither can see a screen**. The
harness is now device-addressable (`--dart-define=screen=`), which is what made
looking cheap enough to actually do.

### As originally written

The direction is right and the execution is thin. Today it is an eyebrow, a
headline, a "Next up" card that says "Nothing scheduled", and a primary button
— over a photo that carries most of the visual weight.

Things it should probably do that it does not:

- Show what the plan has for today, once plans exist. "Next up" is currently a
  placeholder for exactly this.
- Show something about recent training. Track is the screen people open most
  and it currently tells them nothing they did not already know.
- Handle the resume case better. `hasOpenSession` changes the button, and an
  interrupted session deserves more than a different label.

Worth doing **after** plans exist, because the plan is the content that fills
it. Redesigning it empty means designing it twice.

---

## Carried-over debt

Not part of the five, but real, and each one is small:

- ~~**Migrations and the coach are not deployed.**~~ **Done 2026-08-07.** All
  four applied (`db push`) and the function deployed. Verified against
  production afterwards rather than trusting the exit code: `coach.summaries`
  is keyed `(user_id, app)`, all 1249 sets backfilled to `set_type = 'working'`,
  the three `lift.plan*` tables exist with their indexes and three policies, and
  `core.delete_account` carries the app-scoped sweep. The function answers `401
  unauthorized` unauthenticated.

  One thing worth recording, because it was worried about at length and turned
  out to be wrong: **`coach.summaries` was empty**, along with `conversations`
  and `turns`. Runio has never written a memory to production, so the primary
  key drop and re-add touched nothing. The migration that actually touched real
  data was `20260807120000`, adding `set_type` across 1249 rows.

  **Still unproven: a real `lift_chat` turn.** Everything above says the
  plumbing is right; none of it says the coach answers. That needs a signed-in
  lifter on a build pointed at production.

- ~~**`COACH_MODEL_ALLOWLIST` is set on production**~~ **Unset 2026-08-07**, and
  confirmed absent from `secrets list` afterwards rather than assumed from the
  command's exit code. Kept here because the reasoning is what matters, not the
  bullet: it had been set since 2026-07-29 and it broke the rule its own
  documentation sets. Its contents were all seven ids from
  `dev_coach_model.dart`, recovered by hashing candidates against the digest
  `secrets list` prints — which is also the technique to reach for next time a
  secret's value is needed and only its digest is available:

      nex-agi/nex-n2-mini, google/gemini-3.1-flash-lite-20260507,
      minimax/minimax-m3-20260531, qwen/qwen3.7-plus-20260602,
      z-ai/glm-5.2-20260616, google/gemini-3.6-flash-20260721,
      anthropic/claude-sonnet-5-20260630

  `surfaces.ts` says: *put only models you would let ANY runner use in the list
  — never the Sharp-tier model*, so that a forged request can sidegrade but
  never escalate. `anthropic/claude-sonnet-5` is $2.00/$10.00 against
  `COACH_MODEL`'s $0.25/$1.50, and is described in the dev list as "the quality
  ceiling". So a client CAN escalate. The spend cap bounds the damage because it
  is denominated in real OpenRouter cost, but it does not prevent it.

  Second problem, from the same file: several of those are served outside the
  UK/EU, and `dev_coach_model.dart` says that is *not acceptable for the `chat`
  surface in production, which carries a runner's own words about their body*.
  `data_collection: "deny"` stops training, not geography. `lift_chat` now
  carries the same class of data.

  Neither was ever reachable — no shipped client sends `model`, and Lift's never
  will — so it was a loosening rather than a live exploit. The fix was one line,
  and its only cost was the debug model-comparison workflow in `mgk_run`, which
  now has to set the secret again while it is in use:

      npx supabase secrets unset COACH_MODEL_ALLOWLIST

- **`DAILY_GLOBAL_LIMIT` is set on production** and nothing in this repo reads
  it. Almost certainly a legacy Liftio secret. Harmless, but it is one more
  thing that looks load-bearing to whoever reads the list next.

- **`daily-ai-summary` still calls `api.anthropic.com` directly.** Out of scope
  for item 1 — it predates the coach and is Liftio's, not the coach's — but it
  is now the only place in the repo holding an `ANTHROPIC_API_KEY`. The
  restructure migration says it stays app-local until a coach surface replaces
  it; that surface is worth adding while the surfaces table is fresh.
- ~~**Nothing is pushed to the remote.**~~ Stale as written: `origin/main`
  (`github.com/MGKCodes/mgk-fitness`, **private**) was current as of
  2026-08-07. Check `git log origin/main..HEAD` rather than trusting a count
  written into a document.

  Worth knowing while reading the code: several comments justify their design
  with "the repo is public" — the key never reaching the client, the abuse
  economics behind the spend cap. That reasoning is inherited from Liftio and
  Runio and it is sound, but **this** repo is private today. The designs are
  right either way; the stated premise is what is out of date.
- **Liftio's ToS still contradicts the licence decision** made this session, in
  three files across `Liftio` and `getliftio.com`, and Liftio has no credits
  screen to point at. `mgk_lift`'s `credits_screen.dart` is a working
  reference. Draft wording exists.
- **Runio's repo still defines `coach` and `delete-account`.**
  `C:\Projects\Runio\supabase\functions\` has both, pointed at this same
  project, and whichever repo deploys last wins. That is the arrangement that
  caused the account-deletion bug; moving the functions here was supposed to
  end it, and it has not until those two directories are deleted. Runio's copy
  of `surfaces.ts` has now diverged too (no `lift_chat`, no `app` field), so
  deploying from there would also take Lift's coach down.
- **Pose selection is session state.** `core.user_settings.progress_pose_set`
  is the column; nothing writes it.
- **Units are session state too.** `core.user_settings` is shared with Run and
  is where they belong; `InMemoryUnitPreferences` is still wired in
  `main.dart`.
- **The rest-timer buzz is foreground-only.** A scheduled local notification
  needs a plugin and a runtime permission.
- **Progress photos never sync.** The tables and the storage bucket exist. The
  screen currently promises "nothing is uploaded", and that sentence has to
  change in the same commit as the behaviour.
- ~~**`packages/mgk_ui` has no tests.**~~ **Started 2026-08-07** — eight, on the
  two components extracted that day. Deliberately narrow: they pin the layout
  rules that a screenshot catches and a compiler cannot (a lone conversation
  turn sits by the composer, a bubble never spans both margins, a destructive
  button never takes the primary fill). The rest of the package is still
  untested, and the useful ones to add next are the same kind — [design.md](design.md)
  says which rules are load-bearing.
