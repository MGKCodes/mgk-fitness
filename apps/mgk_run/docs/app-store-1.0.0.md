# App Store 1.0.0 — what stands between a green build and a live listing

[release-1.0.0.md](release-1.0.0.md) took the app from "records a run" to
"somebody can hold it", and it is nearly finished. This document picks up where
it stops, because the two are different problems: that one is about whether the
app is good, this one is about whether it can be **submitted, reviewed, and
approved**. An app can be finished and unsubmittable, and most of what follows
is not code.

Written 2026-09-01, against `run/release-1.0.0` at `478eef5`.

Tick items as they land. Where something is settled differently from how it is
written here, change the item and say why — same rule as the release plan, for
the same reason.

---

## Where we actually are

Green, and worth stating so the list below is read as short rather than long:

- **1,319 tests pass, analyzer clean.** Including `naming_test.dart`, which
  fails the build if a retired product name reaches a string a runner reads.
- **The branch is pushed** — `origin/run/release-1.0.0`, 34 commits. The Checks
  workflow runs on push; the three build workflows are manual-trigger only.
- **The iOS release pipeline exists and is configured**: `Run — iOS TestFlight`
  in `codemagic.yaml`, signing via the team's `frunt_asc` key, the provisioning
  profile for `com.mgkcodes.fitness.run` created by hand after the first build
  failed on its absence. Build numbers come from `$PROJECT_BUILD_NUMBER`, so
  `1.0.0+1` in the pubspec never needs bumping.
- **The deletion path is built and correctly scoped.** `delete_account` walks
  `array['lift', 'run']` plus `coach`, enumerating tables from the catalogue
  rather than a hard-coded list, so anything added later is covered the day it
  exists.
- **The privacy policy and medical disclaimer are written**, and rendered in-app
  from `lib/src/features/legal/`.
- **`ITSAppUsesNonExemptEncryption` is answered** in `Info.plist`, so no build
  lands in App Store Connect as "Missing Compliance" waiting on a hand answer.

**The app has already been to TestFlight.** `CHANGELOG.md` records it: built and
installed, never on a store. So the pipeline below is a path that has run
end to end, not an unknown — what has never happened is a *submission*. Day-to-day
development still happens on Windows against an Android emulator, which is why
the device questions in Gate 1 are answered on TestFlight rather than here.

---

## Gate 1 — The TestFlight round

**Build 11 — version 1.0.0 — succeeded end to end on 2026-09-01**, six minutes,
every step green including Publishing. Triggered against `run/release-1.0.0` on
workflow `run-ios-release`; `run.ipa` at 26.1 MB.

Four things that were genuinely unknown before it, and are not now:

- **`TARGETED_DEVICE_FAMILY = "1"` compiles.** It was an Xcode project edited
  from Windows and unverifiable here.
- **Code signing resolves for `com.mgkcodes.fitness.run`.** This is the step that
  failed on the first ever build with "No matching profiles found"; the profile
  created by hand in the Apple Developer portal is working.
- **The artefact globs matched**, so the failure this file warns about at
  length — a green build that publishes nothing and leaves TestFlight empty —
  did not happen.
- **An App Store Connect record already exists for the bundle id.** Publishing
  succeeded, and `codemagic.yaml`'s own setup notes say the upload step fails
  after a successful build when no listing exists. That answers a Gate 2 item
  that was written as "needs confirming".

`$PROJECT_BUILD_NUMBER` supplied build 11 and the pubspec's `1.0.0+1` was never
touched, as designed.

Re-trigger with the same settings when there is something new to test.

What this round exists to prove — none of it can be answered from Windows:

- [ ] **The 23 Aug run is recoverable.** The last open item in
      [release-1.0.0.md](release-1.0.0.md)'s Phase 0. With the log reading Drift,
      the run should simply appear. If it does not, it never finalized, and that
      is a new bug rather than the one already fixed.
- [x] **A backgrounded run survives with the screen locked — tested, and it
      works.** Confirmed on a live TestFlight build. The capability was built in
      `b493341`: iOS carries `UIBackgroundModes: location` with
      `allowBackgroundLocationUpdates: true` and
      `pauseLocationUpdatesAutomatically: false`, and Android got the foreground
      service that stops the silent freeze. **The result was never written down**,
      which is why [release-1.0.0.md](release-1.0.0.md) still listed it as an
      untested data-loss path a fortnight after it had been settled. It no longer
      does.
- [ ] **Widening the Health request does not re-prompt badly.** The app now asks
      for steps as well as workouts. Whether an existing install re-prompts is
      untested, and it sits awkwardly beside the onboarding doc's claim that
      neither permission can be asked twice.
- [ ] **The permission dialogs read correctly.** They were rewritten in `1fdaf6f`
      and have never been seen on a device. Check the wording against
      Settings › Run › Location afterwards, because copy sends people there.
- [ ] **A run records end to end on real hardware** — acquire, splits, pause,
      lap, finish, and the run appears in the log and on the profile.
- [x] **The test sheet is written** —
      [testflight-1.0.0-test-sheet.md](testflight-1.0.0-test-sheet.md), on the
      shape of Lift's. Six lettered sections, and a *Known gaps* list that names
      the `_Locked` dead end, the always-absent elevation and the five other
      things a tester would otherwise file. It carries the SQL to grant yourself
      an entitlement, since the purchase flow does not exist and without a row
      you test the free half and conclude the paid half is broken.

---

## Gate 2 — Hard blockers

App Store Connect will not accept a submission without these. None are code.

- [ ] **A published privacy policy URL.** Still the long pole, but the page now
      exists: `docs/legal-site/privacy-policy.html`, generated from
      `docs/privacy-policy.md` by `tool/build_legal_pages.py`. **It is not
      deployable yet** — see the four blockers below. What remains is hosting it
      somewhere stable under `mgkcodes.com` and pasting the URL into App Store
      Connect's required field.

      It is generated rather than written because
      [naming.md](../../../docs/naming.md) names the trap: **the in-app copy
      mirrors the published page word for word, and a reviewer does check.**
      That is three renderings of one text — the doc, `legal_copy.dart`, and now
      a web page — and hand-maintaining the third is how they drift. Verified at
      generation: 58 of 58 source blocks appear verbatim, and every phrase
      `legal_copy_test.dart` pins is present.
- [x] **The medical disclaimer page**, generated the same way from
      `docs/medical-disclaimer.md`. Same four blockers before it goes live.
- [ ] **Clear the four publication blockers**, which the policy's own draft
      banner names and the generated pages repeat in an HTML comment:
      1. ~~**Legal review** of the document.~~ **Dropped as a blocker
         2026-09-01** — out of reach for now, and the policy ships as the most
         accurate description we can write. Recorded as an accepted risk rather
         than a forgotten step, in the policy's own banner and in the
         generator's `BLOCKERS` list. What protects it is that the data flows
         were read off the running system rather than written from intent; what
         is unreviewed is legal *form*, not factual accuracy. Revisit when there
         is budget — a dated policy update is normal.
      2. ~~**A processor agreement with OpenRouter.**~~ **Also off the blocker
         list — and this document argued the opposite for a few hours, wrongly.**
         Naming a recipient in a privacy policy is an **Article 13 transparency
         duty**: tell people who receives their data. It does not assert that a
         contract exists, so publishing does not state anything untrue. The
         **Article 28** contract is a real and separate obligation that runs in
         parallel — disclosure does not cure it, and its absence does not make
         the disclosure false. The email went to `support@openrouter.ai` on
         2026-09-01; tracked in
         [openrouter-processor-agreement.md](openrouter-processor-agreement.md),
         not here.

         What the policy does instead is **claim only what we can stand behind**:
         it now says `data_collection: "deny"` is set on every request and is the
         strongest control available to us, and that we cannot audit the provider
         that ultimately serves one — a control we apply, not a promise we make
         for them.
      3. **Whether the configured `COACH_MODEL`'s provider trains on inference
         inputs.** A per-model property. Answer from the deployed secret;
         [compliance.md](compliance.md) is explicit that guessing from the repo
         is wrong. `data_collection: "deny"` is the control and it is set; what
         is unconfirmed is what it guarantees contractually.
      4. **The publication date** — replace the `PUBLICATION_DATE` token.

      Only item 3 can still change what the policy has to say, and less than it
      could have: the wording above no longer implies providers never retain, so a
      "best-effort" answer costs a sentence rather than a rewrite.
- [x] **An App Store Connect app record exists for
      `com.mgkcodes.fitness.run`** — proven by build 11 publishing successfully,
      since the upload step fails after a successful build when no listing
      exists. Still to check by eye: that the listing name is `MGKFitness: Run`
      per naming.md, since the record existing says nothing about what it is
      called.
- [ ] **App Privacy ("nutrition labels").** Must match the sub-processor table
      in [compliance.md](compliance.md): Supabase, OpenRouter, MapTiler. Health
      and fitness data, location, and identifiers all get declared, along with
      whether each is linked to identity. Backup consent makes several of these
      conditional, which the form has no way to express — say what is collected
      when consent is *on*.
- [ ] **Age rating questionnaire.**
- [ ] **Screenshots at Apple's current required sizes.** Read the exact set off
      App Store Connect rather than trusting a number written here; at time of
      writing it wants a 6.9" set. **The contact-sheet plates are not usable** —
      they are 393×852 logical renders for design review, not store assets.
- [ ] **App Review notes**, which [compliance.md](compliance.md) already says are
      needed and are easy to forget:
      - a written justification for always-on location ("recording a run with the
        screen off" is accepted),
      - exactly what health data is read, written, and shared, and with whom.
        Answer the model question from the deployed `COACH_MODEL` value, not from
        the repo.
- [ ] **A demo account, or a written note that one is not needed.** The app now
      opens on a working tracker with no account
      ([ADR-0019](decisions/0019-onboarding-is-two-moments.md)), which is a good
      answer — but the *coach* and *plans* sit behind an account, and a reviewer
      who cannot reach them may reject for incomplete functionality. Give them
      credentials.

---

## Gate 3 — Payments, and the dead end that ships today

**The app tells a free runner to upgrade and gives them no way to do it.**

`home_last_run.dart`'s `_Locked` state is a good piece of design — a dimmed
skeleton of the two rows a coach would fill, the words *"Upgrade to see this
stat"*, and a sentence naming what is behind the lock rather than only that
something is. Under it:

```dart
if (onUpgrade != null) ...<Widget>[
  AppTextButton(label: 'See what a coach adds', onPressed: onUpgrade),
],
```

**`home_shell.dart` never passes `onUpgrade`.** The only place that supplies one
is `test/home/last_run_test.dart`, so in the shipping app the button is not
rendered and the runner is told to upgrade with nothing to tap. That is an App
Review Guideline 2.1 risk on its own, whatever is decided about payments.

### What is already built

More than you would expect — the hard, security-shaped half is done:

- **`core.entitlements`** — one row per (user, app); `product` in
  free/paid/premium, `status` in active/expired/grace/refunded/revoked, plus
  platform, expiry and `source_txn_id`. **Client-read-only by design**: no
  INSERT/UPDATE/DELETE policy and no grant to `authenticated`, because the repo
  is public and a write path that exists is a write path somebody uses. Only
  `service_role` writes.
- **The server read path** — `supabase/functions/coach/entitlements.ts` reads
  it, `tierFor` maps a product to a model tier, the coach function calls it, and
  `entitlements_test.ts` covers it. Only `active` grants anything.
- **The client tier model** — `CoachAccess`, defaulting to `free`, every unknown
  answer resolving to `free`, and deliberately *not* read from a stored flag: a
  value a client can write is a value a client can forge.
- **Both UI states**, drawn and on the contact sheet — `H4` with a coach, `H5`
  free.
- **The gate copy**, as a placeholder that names no price on purpose.

### What does not exist

- **A purchase SDK.** Neither app has one — no `purchases_flutter`, no
  `in_app_purchase`, no StoreKit. RevenueCat is not wired anywhere.
- **The write path.** Three Edge Functions exist (`coach`, `daily-ai-summary`,
  `delete-account`) and none validates a receipt. **Nothing has ever written a
  row to `core.entitlements`.**
- **Pricing.** `plan_gate_copy.dart` says the tiers are undecided and
  `plan_gate_copy_test.dart` asserts no figure is quoted.
- **App Store Connect subscription products**, a RevenueCat account, and the
  ADR choosing between RevenueCat and StoreKit —
  [ADR-0014](decisions/0014-model-is-chosen-per-surface-and-per-tier.md) says
  "a verified App Store transaction" and stops there.

### Settled: 1.0.0 ships paid, on RevenueCat

The coach costs real money per request through OpenRouter, so it is a paid tier
and the `_Locked` state stays. **RevenueCat is the purchase path** —
[ADR-0028](decisions/0028-revenuecat-is-the-purchase-path.md) records the choice
and the reasoning: the suite spans Apple and Google, and the five statuses in
`core.entitlements` are the hard part rather than the paywall.

Done already, because it was cheap while the policy was unpublished:

- [x] **[ADR-0028](decisions/0028-revenuecat-is-the-purchase-path.md) written.**
- [x] **RevenueCat declared as a sub-processor** in all four places that have to
      agree: `docs/privacy-policy.md`, `legal_copy.dart`, `compliance.md`'s
      table, and the regenerated pages. `legal_copy_test.dart` now pins all four
      processors rather than the two that happened to be interesting.

What is left, roughly in order:

- [ ] **Decide the price.** Nothing technical waits on it, but three things do:
      `plan_gate_copy.dart` (which quotes no figure today, and whose test
      asserts that), `docs/product-spec.md`, and
      [ADR-0015](decisions/0015-spend-is-capped-over-three-windows.md) — whose
      spend ceilings in `supabase/functions/coach/limits.ts` are sized against a
      £1 monthly subscription that was always a placeholder. A different price
      means they are sized against the wrong number, so this is a cost control
      as much as a commercial decision.
- [ ] **RevenueCat account, and the products in App Store Connect.** The
      products have to exist before a build can offer them.
- [x] **The webhook Edge Function is built** — `supabase/functions/revenuecat`,
      the only thing that writes `core.entitlements`. Its mapping is pure and
      unit-tested (16 tests, no store and no database), and the ordering story
      turned out to need a migration: `source_txn_id` is not a watermark, so
      `event_ms` was added and an event must be strictly newer to win. A replay
      is a no-op, a late expiry cannot revert a live renewal, and a row inserted
      by hand loses to the first real event rather than blocking it.

      **Not deployed, and nothing works until it is.** Since
      [ADR-0030](decisions/0030-the-coach-is-the-paid-half.md) the coach is
      refused without a row, and no row can exist without this function. See its
      [README](../../../supabase/functions/revenuecat/README.md) for the deploy
      command, the two secrets, and the RevenueCat dashboard wiring.
- [ ] **Deploy it, and set the secrets.** `REVENUECAT_WEBHOOK_SECRET` and
      `REVENUECAT_PRODUCTS`, the latter carrying the real App Store product ids
      once they exist. Deployed with `--no-verify-jwt`, which is required rather
      than lax: RevenueCat has no Supabase token and authenticates with the
      shared secret instead.
- [ ] **The SDK in the client**, public key through `app_config.json` beside
      `SUPABASE_URL`, webhook secret server-side only.
- [ ] **Wire `onUpgrade`** in `home_shell.dart`, which is what closes the dead
      end above, and **the purchase screen it opens**.
- [ ] **Restore purchases.** Apple requires it; RevenueCat provides it, but it
      still needs a surface.
- [ ] **A processor agreement with RevenueCat**, alongside the OpenRouter one in
      [openrouter-processor-agreement.md](openrouter-processor-agreement.md).
- [ ] **App Privacy: declare Purchases and the identifier.**
- [ ] **Sandbox testing**, which needs a real device and a sandbox Apple ID — so
      it joins Gate 1 rather than being provable here.

**The client stays out of the decision.** `CoachAccess` keeps coming from the
server; the SDK presents and performs a purchase and nothing more. Reading
`CustomerInfo.entitlements.active` on device and unlocking from it would replace
a fact with a claim, which is the property `coach_access.dart` exists to hold.

---

## Gate 4 — Would pass the form and fail the review

- [x] **`TARGETED_DEVICE_FAMILY` set to `"1"` — iPhone only.** It was `"1,2"`,
      Flutter's default, which nobody chose: Apple would have required an iPad
      screenshot set and **reviewed the app on an iPad**, and nothing here has
      ever been laid out for one — the widest surface the board tests is 430pt,
      and the in-run detents are tuned across 320–430. Changed in all three of
      the Runner target's configurations (Debug, Release, Profile). iPhone-only
      is the honest description of what was built and matches
      [ADR-0001](decisions/0001-flutter-ios-only.md).

      `UISupportedInterfaceOrientations~ipad` is left in `Info.plist`. It is dead
      under device family 1 and harmless, and it documents the intent if iPad is
      ever reconsidered. **The change is unverified until a build runs** — it is
      an Xcode project edit made on Windows.
- [ ] **Decide what elevation does at launch.** The tiles are built end to end
      and permanently read "not recorded", because there is no barometric source
      ([ADR-0024](decisions/0024-elevation-is-barometric-or-absent.md)). That is
      defensible — absent beats a plausible wrong number — but a reviewer or a
      tester sees a metric the app advertises and never fills. Either build
      `CMAltimeter`, or make sure it reads as deliberate rather than broken.
- [x] **`steps` and `elevation_max_m` are mirrored.** `run.runs` gained both
      columns, and both sides of the seam read and write them. The gap was
      exactly as cheap to close as it looked — and it had gone unnoticed for a
      month *because* nothing rendered wrongly: absence is the designed state for
      both, so the loss showed up as an empty field rather than a bug.

      `mirror_round_trip_test.dart` now pins the invariant that broke: every
      column the mirror writes must be one the restore reads. The
      interface-level tests could not have caught it — they fake `RunBackup` and
      assert what a caller does with the result, which says nothing about a
      column list — so it reads the two files as text, the way `naming_test.dart`
      reads `lib/`.
- [x] **Elevation converts at display.** `Elevation` is in `mgk_units`
      alongside `Distance`, `Pace` and `Mass`, and the three sites that hardcoded
      `m` now use it — the in-run climb readout and both tiles on the finish
      screen.

      It follows the **distance** system rather than having a unit of its own,
      which is the difference from `Mass`: kilometres with pounds is an ordinary
      combination, and miles with metres of climb is not. There is deliberately
      no `ElevationUnit` to get wrong.

---

## Gate 5 — Documents that were wrong

Cleared 2026-09-01. Recorded rather than deleted, because three of the four were
the kind of staleness that is invisible until somebody acts on it.

- [x] **`compliance.md` described a function that no longer existed.** It said
      `runio_delete_account` sweeps "every table in the `runio` schema", a month
      after that schema was renamed to `run`. The real function is
      `core.delete_account(p_user_id, p_app)`, sweeping the target app schema
      plus `coach`. **The code was right and the document defending it to a
      regulator was not**, which is the worse way round. The broken link to the
      Edge Function README beside it is fixed too.
- [x] **`codemagic.yaml`'s header contradicted its own workflow list** — "Run
      has no Android workflow" above a `run-android-release` a few hundred lines
      below. Now says no Android *release*, which is what was meant and what the
      missing `publishing:` block actually enforces.
- [x] **`roadmap.md`** retitled, its two present-tense "Runio" lines fixed, and
      its *Definition of "v1 shippable"* reconciled with this document rather
      than maintained beside it — two checklists being how one goes stale.
- [x] **Lift's test sheet granted an entitlement that could not exist.** Found
      while writing Run's: it inserted `platform = 'manual'` against a
      `check (platform in ('apple', 'google'))`. It fails with a constraint
      violation rather than granting anything, so anyone who ran it tested the
      free half of Lift believing it was the paid one. Fixed to `'apple'`.
- [ ] **`release-1.0.0.md` is still ~12 commits stale.** Its phases are ticked
      but the account-removal work and everything after it is missing. Lower
      priority than the four above, because it misleads about *history* rather
      than about how the system behaves now.

---

## Explicitly not blocking

Recorded so nobody re-opens them under deadline:

- **Heart rate, cadence, active energy.** Stopped on purpose, with reasons, in
  [release-1.0.0.md](release-1.0.0.md)'s "Deliberately not built".
- **In-run audio** — [ADR-0006](decisions/0006-in-run-audio-deferred.md).
- **The Android release pipeline** — the APK workflow is a verification harness,
  not a product ([ADR-0021](decisions/0021-android-is-a-target.md) sets the
  intent; nothing ships to Play for Run at 1.0.0).
- **Going open source.** `roadmap.md` lists a git-history secret scrub as part of
  "v1 shippable". It is a prerequisite for making the repo *public*, not for
  shipping the app, and conflating them adds a hard job to the critical path for
  no store benefit.

---

## The order

1. ~~Set `TARGETED_DEVICE_FAMILY` to `"1"`~~ — done, and unverified until a
   build runs, which is the first thing the next build proves.
2. **Send the OpenRouter email** ([openrouter-processor-agreement.md](openrouter-processor-agreement.md)).
   It is the only item here whose clock is somebody else's.
3. **Run the TestFlight build**, and write the test sheet while it builds. It
   proves the device-family change and answers the rest of Gate 1; the payment
   work does not block it, because the app is on `free` until a webhook says
   otherwise.
4. **Decide the price**, which unblocks the App Store Connect products, the gate
   copy, and ADR-0015's ceilings.
5. **Publish the two legal pages** — the long pole, because it needs a hosted
   page and word-for-word parity with the in-app copy. Start it now; it does not
   depend on anything else here.
6. **Work the rest of Gate 1 on a device**, starting with the 23 Aug recovery.
7. ~~Fix Gate 5~~ — done, except `release-1.0.0.md`'s own staleness.
8. **Fill in Gate 2** in App Store Connect once there is a build to attach it to.
9. **Decide Gate 4's elevation question** last — it is the only item here that
   could reasonably change what 1.0.0 contains.
