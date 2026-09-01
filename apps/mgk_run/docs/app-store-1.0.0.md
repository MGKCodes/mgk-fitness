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

**The app has never been compiled for iOS.** It has only ever been built for an
Android emulator on Windows. The first real iOS compile happens on Codemagic,
which makes the TestFlight round below a genuine unknown rather than a
formality.

---

## Gate 1 — The TestFlight round

Start it from the Codemagic UI: **Start new build** → branch
`run/release-1.0.0` → workflow **`Run — iOS TestFlight`**. The branch is the
step that matters; it defaults to `main`, where none of this exists.

Two steps have failed before and are worth watching in the log: **Set up code
signing** (the first build for this bundle id failed with "No matching profiles
found" — an App ID is not a provisioning profile) and the **artifacts** globs (a
pattern that matches nothing is ignored silently, and the failure mode is a
green build with an empty TestFlight).

What this round exists to prove — none of it can be answered from Windows:

- [ ] **The 23 Aug run is recoverable.** The last open item in
      [release-1.0.0.md](release-1.0.0.md)'s Phase 0. With the log reading Drift,
      the run should simply appear. If it does not, it never finalized, and that
      is a new bug rather than the one already fixed.
- [ ] **A backgrounded run survives on While-Using location.** Called out as an
      open question in the release plan and never tested. This is a data-loss
      path: if a run dies when the screen locks, nothing else on this list
      matters. Test it before anybody else runs with the app.
- [ ] **Widening the Health request does not re-prompt badly.** The app now asks
      for steps as well as workouts. Whether an existing install re-prompts is
      untested, and it sits awkwardly beside the onboarding doc's claim that
      neither permission can be asked twice.
- [ ] **The permission dialogs read correctly.** They were rewritten in `1fdaf6f`
      and have never been seen on a device. Check the wording against
      Settings › Run › Location afterwards, because copy sends people there.
- [ ] **A run records end to end on real hardware** — acquire, splits, pause,
      lap, finish, and the run appears in the log and on the profile.
- [ ] **Write the test sheet.** Lift has
      [testflight-2.0.0-test-sheet.md](../../../docs/testflight-2.0.0-test-sheet.md);
      Run has nothing equivalent. Use its shape — *Before you start*, *Known gaps
      — do not report these*, then lettered sections, then *What to send back*.
      The "known gaps" section is the load-bearing one: without it every tester
      reports the missing barometer as a bug.

---

## Gate 2 — Hard blockers

App Store Connect will not accept a submission without these. None are code.

- [ ] **A published privacy policy URL.** This is the biggest one and nothing
      exists today. The policy lives in `docs/privacy-policy.md` and is rendered
      in-app, but App Store Connect has a required **Privacy Policy URL** field
      and there is no public page to put in it. It has to be hosted somewhere
      stable under `mgkcodes.com`.

      [naming.md](../../../docs/naming.md) is explicit about the trap:
      **the in-app copy mirrors the published page word for word, and a reviewer
      does check that they match.** So publishing is not a copy-paste and forget
      — it is a second copy that now has to be kept in step.
- [ ] **The medical disclaimer, published the same way**, for the same reason.
      An app that prescribes physical load and shows a disclaimer only in-app has
      nothing to point a reviewer at.
- [ ] **An App Store Connect app record for `com.mgkcodes.fitness.run`.** Lift
      has one (id 6759969740). Whether Run does needs confirming — the
      `codemagic.yaml` setup notes say the upload step fails after a *successful*
      build when no listing exists, which is the expensive way to find out.
      Listing name is `MGKFitness: Run`, per naming.md.
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

## Gate 3 — Would pass the form and fail the review

- [ ] **`TARGETED_DEVICE_FAMILY` is `"1,2"` — the app is built for iPad.**
      This is Flutter's default and nobody chose it. Consequences: Apple requires
      an iPad screenshot set, and **reviews the app on an iPad**. Nothing here has
      ever been laid out for one — the widest surface the board tests is 430pt,
      and the in-run screen's detents are tuned across 320–430. An untested iPad
      layout in front of a reviewer is a rejection risk for no gain.

      Set it to `"1"` in `ios/Runner.xcodeproj/project.pbxproj` (three places).
      iPhone-only is the honest description of what was built, matches
      [ADR-0001](decisions/0001-flutter-ios-only.md), and removes the iPad
      screenshot requirement.
- [ ] **Decide what elevation does at launch.** The tiles are built end to end
      and permanently read "not recorded", because there is no barometric source
      ([ADR-0024](decisions/0024-elevation-is-barometric-or-absent.md)). That is
      defensible — absent beats a plausible wrong number — but a reviewer or a
      tester sees a metric the app advertises and never fills. Either build
      `CMAltimeter`, or make sure it reads as deliberate rather than broken.
- [ ] **`steps` and `elevation_max_m` are not mirrored.** `run.runs` has neither
      column, so a restore onto a new phone drops them silently. Two lines in
      `supabase_run_backup.dart`, two matching reads in `SupabaseRestore`, and a
      Postgres migration. Not a rejection risk; a real data-loss-on-upgrade risk,
      and cheap.
- [ ] **Elevation renders in metres for everyone**, in an app whose rule is
      "store metric, convert at display". Needs an `Elevation` type in
      `packages/mgk_units` — a local feet conversion on one screen while the
      in-run readout keeps metres is the two-numbers-for-one-thing bug.

---

## Gate 4 — Documents that are now wrong

These matter more than usual: two of them are what you hand a reviewer or a
regulator, and a confidently wrong compliance document is worse than none.

- [ ] **`compliance.md` describes a function that no longer exists.** It says
      `runio_delete_account` sweeps "every table in the `runio` schema" and that
      this makes the policy's "every Runio record" claim safe. The real function
      is `delete_account`, and it sweeps `array['lift', 'run']` plus `coach` —
      the `runio` schema was renamed to `run` in
      `20260806130000_restructure_schemas.sql`. **The code is right and the
      document is stale**, but this is the document that justifies a GDPR claim.
- [ ] **`codemagic.yaml`'s header contradicts its own workflow list.** It states
      "**Run has no Android workflow, deliberately** (ADR-0001)" while
      `run-android-release` sits at line 751. The spirit is intact — that
      workflow has no `publishing:` block and produces a downloadable APK for
      device testing, not a release — but the letter sends a reader looking for
      something that is right there.
- [ ] **`release-1.0.0.md` is ~12 commits stale.** It was last touched at
      `c26797c`; everything from the account removal onwards is missing from it,
      including work that closed items it still lists as open.
- [ ] **`roadmap.md` is titled "Runio — Roadmap"** and its *Definition of "v1
      shippable"* is the closest thing this project has to a release checklist —
      worth reconciling with this document rather than leaving two.

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

1. **Set `TARGETED_DEVICE_FAMILY` to `"1"`** before the TestFlight build, so the
   binary in front of testers is the binary you intend to ship.
2. **Run the TestFlight build**, and write the test sheet while it builds.
3. **Publish the two legal pages** — the long pole, because it needs a hosted
   page and word-for-word parity with the in-app copy. Start it now; it does not
   depend on anything else here.
4. **Work Gate 1 on a device**, starting with the backgrounded-run test.
5. **Fix Gate 4**, which is an hour and removes the risk of arguing a compliance
   claim from a document that describes a renamed schema.
6. **Fill in Gate 2** in App Store Connect once there is a build to attach it to.
7. **Decide Gate 3's elevation question** last — it is the only item here that
   could reasonably change what 1.0.0 contains.
