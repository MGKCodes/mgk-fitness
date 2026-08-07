# Roadmap — what happens next in Lift

Written 2026-08-07, at the end of the session that built photos, sync, auth and
the coach. It is ordered: each item assumes the one above it is done.

This is a working plan, not documentation of what exists. For that, see
[architecture.md](architecture.md) and the app READMEs. Delete this file when
it has been worked through.

---

## 1. Move the coach to OpenRouter

**The current implementation is wrong and should be changed before anything
else is built on it.** `supabase/functions/coach/index.ts` calls
`api.anthropic.com` directly with an `ANTHROPIC_API_KEY`. It works, but it
hard-codes a vendor into a deployed function, and changing model means a
function redeploy.

Going through OpenRouter means the model is a **configuration value, not a
code path** — swapping `anthropic/claude-sonnet-4.5` for something cheaper on
the accessory-advice turns, or something bigger for plan generation, becomes a
row in a table rather than a release.

What to change:

- `ANTHROPIC_API_KEY` → `OPENROUTER_API_KEY`, endpoint to
  `https://openrouter.ai/api/v1/chat/completions`. The request shape is
  OpenAI-style: `messages` with a `system` role entry rather than Anthropic's
  separate `system` field.
- Usage accounting reads `usage.prompt_tokens` / `usage.completion_tokens`
  instead of `input_tokens` / `output_tokens`. `coach.record_usage` already
  takes both.
- Send `HTTP-Referer` and `X-Title` headers; OpenRouter uses them for
  attribution and they are free to set.
- **Decide where the model name lives.** A `coach.models` table keyed by
  surface (`chat`, `plan_generation`, `session_note`) is the version worth
  having: it is what makes "change the model without an app update" true, and
  it lets the plan generator use a different model from the chat.
- OpenRouter can fall back across providers. Worth turning on — a coach that
  fails because one provider is down is a coach that fails on a Monday evening.

Keep everything else about the function as it is: the key stays server-side,
the entitlement check stays server-side, and the log is still read as the
caller so RLS decides what the model can see.

---

## 2. Persistent coach memory

Today's chat is session-only and says so in `coach_screen.dart`. The tables
already exist and are unused: `coach.conversations`, `coach.turns`
(append-only — `UPDATE` is denied at the grant layer), and `coach.summaries`
(one row per user, with `turns_covered`).

The point is not transcript storage. It is that **the coach should know a
lifter after three months** — that they train four days, that their left
shoulder complains on overhead work, that they respond to volume and not to
intensity. That is what makes it a coach rather than a chat window over a
database.

The shape that fits the schema:

1. **Every turn is written** to `coach.turns` as it happens, both sides,
   ordered by `seq`. Cheap, append-only, and the audit trail if a reply is
   ever wrong in a way that matters.
2. **A rolling summary** in `coach.summaries` holds the durable facts — goals,
   constraints, injuries, preferences, what has been tried. Regenerated when
   `turns_covered` falls far enough behind the turn count, not on every turn.
3. **Each request sends** the summary plus the last N turns, not the whole
   history. History grows without bound; the summary is what makes the context
   window a non-issue at month six.

Three things to decide before building it:

- **Retention and deletion.** This becomes a stored record of somebody
  discussing their body and their injuries. `core.delete_account` already
  cascades, but there should be a way to clear the coach's memory *without*
  deleting the account — and the app should say plainly that the coach
  remembers.
- **What the summary is allowed to contain.** A summary that records "user
  seems anxious about weight" is a different product from one that records
  "training 4x/week, shoulder impingement on overhead press". Constrain it in
  the prompt and consider making it visible to the lifter.
- **Whether the summary is editable.** A coach that has learned something wrong
  and cannot be corrected is worse than one that remembers nothing.

---

## 3. Coach-generated plans, and templates as its knowledge base

The biggest of the four, and the one with the most design still open.

**The template picker goes away as a user-facing feature.** Today
`template_picker_sheet.dart` offers 15 templates and 8 splits, and the lifter
chooses. That becomes the coach's raw material instead: the templates encode
what a sensible session looks like — push/pull/legs, upper/lower, full body,
the movement ordering, the compound-before-accessory rule — and the coach
composes from those known-good shapes rather than inventing a session from
nothing.

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

## 4. Navigation audit — entry and exit on every screen

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

## 5. Redesign the Track surface

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

- **Two migrations are committed and not pushed** —
  `20260807120000_lift_sync_columns.sql` must be applied before sync works
  against production. The `coach` edge function is not deployed.
- **Nothing is pushed to the remote.** 18 commits sit locally.
- **Liftio's ToS still contradicts the licence decision** made this session, in
  three files across `Liftio` and `getliftio.com`, and Liftio has no credits
  screen to point at. `mgk_lift`'s `credits_screen.dart` is a working
  reference. Draft wording exists.
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
