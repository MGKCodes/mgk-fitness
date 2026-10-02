# After 1.0.0 — the edge of the push

Two things came out of the build 12 field test on 2026-09-04 that **cannot be
built as written**, because neither of them is specified. They are not deferred
on merit and they are not rejected. They are held here because putting them on
[app-store-1.0.0.md](app-store-1.0.0.md) would make them look like work when
they are still only subjects, and a checklist row nobody can finish is a row
that never goes green.

**Everything else from that field test is 1.0.0 scope**, and it is tracked in
`app-store-1.0.0.md`, which is the only checklist carrying state. Its defects
were fixed, and [the test sheet](testflight-1.0.0-test-sheet.md) re-tests
them. Nothing in sections 1 to 3 is a defect, and **nothing on this page blocks
submission**.

**This document exists so these are not mistaken for either done or
forgotten** — which is the only fate available to an unspecified item that lives
nowhere.

**A third entry was added on 2026-09-08 and is a different shape.** Heart rate
and calories from Health *is* specified; it is deferred on cost rather than
stranded on meaning. It is here because this is where the edge of the 1.0.0 push
is written down, and the filing rule below applies to it in one direction only:
it needs no specification, so it is ready to become work whenever the release
after this one has room.

**A fourth section was added on 2026-09-29, and it is the long one.** The
pre-release review that day found real problems that do not block submission,
and each was either fixed for build 26 or written down in section 4 with a date
to look at it again. They are specified, so they are work, not subjects; they
are here rather than on [app-store-1.0.0.md](app-store-1.0.0.md) because that
page is the list of what stands between the release candidate and the stores,
and none of these does.

It is a work document, so it has an end date: it ends when the first two
entries have a specification or a written decision not to build them, and every
row of section 4 is built or decided against. It is archived then rather than
maintained. See [the filing rule](README.md).

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

## 4. Deferred by the 2026-09-29 review

One line each. **Revisit** is the date to pick it up or decide against it, not
a promise to ship by then.

### Payments and the webhook

| Item | Revisit |
|---|---|
| **Grace periods, before the first renewal cycle.** A `BILLING_ISSUE` writes `grace`, which grants nothing, so a runner whose card fails loses the coach at once while the store is still retrying. Either grant during the store's grace window (`grace_period_expiration_at_ms`), or turn grace off in Play Console so the two stores behave alike | 2026-11-01 |
| **`TRANSFER` events are ignored.** They carry no `app_user_id`, so the webhook refuses them; handling one needs a RevenueCat secret key to fetch the new owner's entitlements | 2026-11-01 |
| **The webhook's read-then-write watermark can race.** Two events for one user can both read the old `event_ms` and both write. Make it one atomic SQL upsert with the `event_ms` condition inside it | 2026-11-01 |
| **`PRODUCT_CHANGE` writes the old product**, so a move between tiers is recorded as the tier being left | 2026-11-01 |
| **Sandbox grants look like paid ones** in `core.entitlements`. An `environment` column makes them countable (ADR-0037) | 2026-11-01 |

### The coach and its spend

| Item | Revisit |
|---|---|
| **Per-field clamps on coach requests, and a reserve-before-spend limiter.** The request size is capped as a whole, and a request is counted after it has spent, so requests arriving together can pass a ceiling together | 2026-10-15 |
| **`daily-ai-summary`** is a legacy Liftio function that is still deployed, and any signed-in user can make it spend. Recommended: undeploy it. Never redeploy it from `main` | 2026-10-06 |
| **The coach does not check the AI consent itself.** The app refuses to send without it; the Edge Function should refuse too (ADR-0036) | 2026-10-31 |
| **Premium's sharper model**, chosen by bake-off, if Premium subscribers cancel at the first renewal without nearing Coach's ceiling (ADR-0038) | 2026-11-15 |

### Data, deletion and retention

| Item | Revisit |
|---|---|
| **`core.delete_account` can take too much or too little across apps.** The per-app sweep has to be right before a second app's users start deleting | Before Lift 2.0.0 is submitted |
| **Retention is not enforced on a schedule.** The usage prune only runs when somebody makes a request, so a runner who stops using the coach keeps records past the 31 days the policy promises. Schedule it, or reword the policy | 2026-10-31 |
| **Foreign keys that bind each row to its owner, and index housekeeping**, across `run` and `coach` | 2026-11-15 |
| **Backup off, then on, never re-uploads the plan or the coach's memory**, only runs | 2026-10-31 |
| **Turning backup off with no connection has no retry.** The server copy stays until the runner switches it on and off again online | 2026-10-31 |
| **A same-account OS restore carries the backup answer across** (ADR-0035). Excluding it from iCloud and Google backup is native configuration | 2026-11-15 |

### Plans, recording and the app

| Item | Revisit |
|---|---|
| **Plan dates shift a day when the phone moves west** across time zones | 2026-11-15 |
| **The server half of local dates.** The app sends `local_date` and `utc_offset_minutes` with every coach request; the server still reasons in UTC | 2026-10-31 |
| **Adjusting a week from a week opened in the calendar** (`WeekAdjustSheet`) is not given the race-day calendar or what has already been run. *Adjust this week* on the Plan tab is, since build 28 | 2026-10-31 |
| **Manual laps are discarded at Finish** | 2026-10-31 |
| **A beginner at 0 km a week cannot build a plan** | 2026-10-31 |
| **The run's figures are not on Android 16's lock screen.** The readout is a quiet notification (`run_live`, low importance), and Android 16 leaves quiet notifications off the lock screen unless the runner switches them on. It is in the shade and the status bar. To put it on the lock screen: a new channel at default importance with no sound, or Android 16's Live Updates, which are the nearer match to the iPhone's Live Activity. An existing channel's importance cannot be raised, so it is a new channel id either way. Found 2 October 2026 | 2026-10-31 |
| **Play's two recommendations on build 29's release**, neither a blocker: *edge-to-edge may not display for all users*, and *R8 optimization* for memory and size. Open each on Production ▸ Release dashboard and read what it names before the next Android build | 2026-10-31 |
| **Approximate location on Android is not detected.** The iPhone warns (`663f574`); Android's plugin reports "unknown", so a coarse-only run still records nothing | 2026-10-31 |
| **The Esri map key is built into the app and expires 2027-09-29.** Serve the tile URL from the backend, read at launch and cached, so rotating the key needs no store release. Until then, the second key ships in an update by the end of August 2027 | 2027-03-01 |
| **A real offline map**, for the first run somewhere new with no signal. The phone keeps the tiles it has been shown and loads the ones around the runner when the app opens ([ADR-0043](decisions/0043-the-map-keeps-what-it-has-shown.md)), and Esri's terms forbid downloading an area. It needs a provider whose terms allow it, or tiles we host | 2026-12-01 |
| **Tell the model it is race week when the runner adjusts it.** The validator refuses a long run in race week and says why ([ADR-0044](decisions/0044-race-week-is-a-week-of-its-own.md)), but the adjust prompt in the coach function does not know, so a model can still propose one and spend the attempt. A prompt change and a function deploy | 2026-12-01 |
| **Native maps**, only if Esri's tiles disappoint on a phone. Google Maps on both platforms (free on phones, an official Flutter plugin, styleable to greyscale), not an Apple/Google split: Apple Maps has no Android version, can't be restyled, and its Flutter plugins are barely maintained. Either way it rebuilds the map layer and the web board can no longer draw it | 2026-12-01 |

### Accounts

| Item | Revisit |
|---|---|
| ~~**Email confirmation is off in Supabase Auth.**~~ **Done, not deferred.** On since 2026-09-30, with mail through SMTP2GO and the templates in `supabase/templates/`, proved end to end the same week | Closed |

### Before the repository goes public

None of these matters while the repository is private, and all of them matter
the day it is not.

| Item | Revisit |
|---|---|
| **Pull requests from forks can reach Codemagic secrets.** Drop the `pull_request` trigger, or move the checks to GitHub Actions | Before going public |
| **The `checks` workflow has never run**, and cannot pass as configured on `mac_mini_m2` | Before going public |
| **`.gitignore` gaps** for keystores and credential files | Before going public |
| **`scripts/codemagic-build.sh` does not validate its branch argument**, and the release workflows build from any branch | Before going public |
| **No Content-Security-Policy header** on `web/` | Before going public |
| **A demo JWT literal in `supabase/knowledge/sync.ts`** trips secret scanners | Before going public |

---

## What has to happen before 1 or 2 becomes work

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
