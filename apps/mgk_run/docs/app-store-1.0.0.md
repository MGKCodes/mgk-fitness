# App Store 1.0.0 — everything between a green build and a live listing

[release-1.0.0.md](release-1.0.0.md) took the app from "records a run" to
"somebody can hold it". This document picks up where it stops, because the two
are different problems: that one is about whether the app is good, this one is
about whether it can be **submitted, reviewed, and approved**. An app can be
finished and unsubmittable, and most of what follows is not code.

Written 2026-09-01 against `478eef5`. **Rewritten 2026-09-02 against
`31b7ce3`**, which is where the first version had already gone stale — the
payment half landed, the price was settled, and the listing material had never
been written down at all.

Tick items as they land. Where something is settled differently from how it is
written here, change the item and say why — same rule as the release plan, for
the same reason.

---

## Where we actually are

Green, and worth stating so the list below is read as short rather than long:

- **1,333 tests pass, analyzer and format clean.** Including `naming_test.dart`,
  which fails the build if a retired product name reaches a string a runner
  reads.
- **The iOS pipeline has run end to end.** `Run — iOS TestFlight` in
  `codemagic.yaml`, signing via the team's `frunt_asc` App Store Connect key,
  publishing with `submit_to_testflight: true`. **Build 11 succeeded on
  2026-09-01** — six minutes, every step green including Publishing, `run.ipa`
  at 26.1 MB. Build numbers come from `$PROJECT_BUILD_NUMBER`, so `1.0.0+1` in
  the pubspec never needs bumping.
- **An App Store Connect record exists** for `com.mgkcodes.fitness.run` —
  proven rather than assumed: the upload step fails after a successful build
  when no listing exists, and it did not.
- **The deletion path is built and correctly scoped.** `core.delete_account`
  walks `array['lift', 'run']` plus `coach`, enumerating tables from the
  catalogue rather than a hard-coded list.
- **The legal documents are written and rendered** — privacy policy, medical
  disclaimer and a delete-account screen, all from `lib/src/features/legal/`,
  with the web versions generated from the same source by
  `tool/build_legal_pages.py`.
- **`ITSAppUsesNonExemptEncryption` is answered** in `Info.plist`, so no build
  lands as "Missing Compliance" waiting on a hand answer.
- **The purchase back end is built** — `core.entitlements`, the coach's
  server-side read, the client tier model, the gate sheet, and the `revenuecat`
  Edge Function that is the only thing that writes a row.
- **Every screen is on a board**, recaptured at `31b7ce3` —
  [the contact sheet](https://claude.ai/code/artifact/9ddfd186-11ad-4260-bde9-ef8b7a5d9190),
  73 plates, with `test/plates/board.state.json` recording what each was taken
  at.

**What has never happened is a submission.** Day-to-day development is on
Windows against an Android emulator, which is why every device question below is
answered on TestFlight rather than here.

---

## Gate 1 — What only a device can answer

Build 11 settled four unknowns: `TARGETED_DEVICE_FAMILY = "1"` compiles, code
signing resolves for the bundle id, the artefact globs match, and an App Store
Connect record exists. Re-trigger `run-ios-release` against `run/release-1.0.0`
when there is something new to test — and there is: **nothing from 1 Sep onwards
has been on a phone**, including the whole payment arc.

- [x] **A backgrounded run survives with the screen locked.** Confirmed on a
      live TestFlight build. iOS carries `UIBackgroundModes: location` with
      `allowBackgroundLocationUpdates: true` and
      `pauseLocationUpdatesAutomatically: false`.
- [x] **The test sheet is written** —
      [testflight-1.0.0-test-sheet.md](testflight-1.0.0-test-sheet.md).
- [ ] **The 23 Aug run is recoverable.** The last open item in
      [release-1.0.0.md](release-1.0.0.md)'s Phase 0. With the log reading
      Drift, the run should simply appear. If it does not, it never finalized,
      and that is a new bug rather than the one already fixed.
- [ ] **Widening the Health request does not re-prompt badly.** The app now asks
      for steps as well as workouts. Whether an existing install re-prompts is
      untested, and it sits awkwardly beside the onboarding doc's claim that
      neither permission can be asked twice.
- [ ] **The permission dialogs read correctly.** Rewritten in `1fdaf6f` and
      never seen on a device. Check the wording against Settings › Run ›
      Location afterwards, because the copy sends people there.
- [ ] **A run records end to end on real hardware** — acquire, splits, pause,
      lap, finish, and the run appears in the log and on the profile.
- [ ] **The coach gate opens, and the coach opens behind it.** New since build
      11 and proven nowhere but a widget test: an unentitled runner tapping the
      mark should meet the sheet, an entitled one the conversation. Grant
      yourself a row with the SQL in the test sheet.
- [ ] **Sandbox purchase**, once there are products. Needs a sandbox Apple ID
      and `REVENUECAT_ACCEPT_SANDBOX=true` on a non-production deploy. Belongs
      to Gate 3 but lands here, because it cannot be proven from Windows.

---

## Gate 2 — Submission blockers

App Store Connect will not accept a submission without these. None are code.

- [ ] **A published privacy policy URL.** **The site is built; it is not
      deployed.** `web/` is a Next.js app serving
      `mgkfitness.mgkcodes.com/run/privacy`, `/run/medical-disclaimer` and
      `/run/support`, verified locally end to end. What remains is a Vercel
      project (root directory `web`), a CNAME, and pasting the URL into the
      required field.

      **Where it goes is settled: `mgkfitness.mgkcodes.com/run`.** A suite
      subdomain with a path per app, which is the shape the naming already
      implies — the platform owns the domain and each app owns a path, exactly
      as `kPlatformName` owns the bundle id and each app owns the suffix. Lift's
      pages land beside it at `/lift` without a second decision.

      **Settled 2026-09-02, then re-settled the same day: it lives in `web/`,
      here.** The first answer was the MGKCodes studio site, and reading that
      repo changed it.

      **Two things about that site change the job, and neither was known when
      the subdomain was chosen.** It already hosts app legal pages, and the
      pattern is not what we assumed:

      1. **The routes are paths, not a subdomain** — `mgkcodes.com/privacy/liftio`,
         `/terms/liftio`, `/support/liftio`. A subdomain needs middleware host
         rewriting, a DNS record and a Vercel domain, *and* leaves the two apps
         with different URL shapes for the same kind of page.
      2. **The prose is hand-typed into JSX.** `app/privacy/liftio/page.tsx` is
         671 lines and `app/terms/liftio/page.tsx` is 743, with the policy text
         inline and **nothing testing it against the app**. Copying that pattern
         for Run makes a *fourth* hand-maintained rendering of a text a reviewer
         compares word for word — which is the exact failure
         `tool/build_legal_pages.py` was written to stop, reintroduced in a repo
         where no test can catch it.

      Both problems disappear by putting the site in this repository. The
      generator now writes to `web/public/run/` as well as `docs/legal-site/`,
      the pages are served **verbatim** rather than reproduced by a component,
      and `legal_copy_test.dart` reads the served bytes directly — so the third
      rendering finally joins the two that were already pinned to each other.
      Confirmed by breaking it: renaming a sub-processor on the served page
      alone fails the suite. That check is why the site is here and not in a
      repository of its own.

      The studio site's own Liftio pages were retired the same day, redirected
      to `getliftio.com` rather than deleted, because a shipped listing carries
      whatever URL it was submitted with.

      It is generated rather than written because
      [naming.md](../../../docs/naming.md) names the trap: **the in-app copy
      mirrors the published page word for word, and a reviewer does check.**
      Three renderings of one text — the doc, `legal_copy.dart`, and the web
      page — and hand-maintaining the third is how they drift. Verified at
      generation: 58 of 58 source blocks appear verbatim.
- [x] **The medical disclaimer page**, generated the same way.
- [ ] **A Terms of Use (EULA).** *New, and a hard blocker rather than a nicety.*
      Guideline 3.1.2 requires an auto-renewable subscription's purchase surface
      to carry **functional links to both the Terms of Use and the privacy
      policy**, and App Store Connect wants a EULA URL. There is no terms
      document anywhere in this repo — `legal_screen.dart` offers three rows and
      none of them is one. Two ways to satisfy it:

      1. **Apple's standard EULA** — nothing to write, a link Apple hosts. This
         is what Signal does, and
         [ADR-0005](decisions/0005-license-agpl.md) already establishes why AGPL
         is compatible: the App Store problem is a multi-copyright-holder
         problem, and MGKCodes is the sole holder.
      2. **A custom EULA**, generated into `legal-site/` alongside the other two
         and surfaced as a fourth row in `legal_screen.dart`.

      **Settled 2026-09-02: Apple's standard EULA.**
      `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/` goes in
      the listing's terms field and in App Store Connect's EULA field. **The
      in-app half is built**: the paywall links to it, and
      `purchase_screen_test.dart` asserts the link is there. Still owed is a
      fourth row in `legal_screen.dart` pointing at the same URL, so it is
      reachable from Settings by somebody who is not mid-purchase.
- [ ] **A support URL.** **Written, not deployed** — `web/app/run/support/page.tsx`,
      at `mgkfitness.mgkcodes.com/run/support`. It answers the three things a
      runner actually writes in about, and says plainly which two we cannot fix:
      Apple takes the payment, so Apple cancels and Apple refunds.
- [ ] **Clear the remaining publication blocker.** The policy's own banner and
      the generator's `BLOCKERS` list carry four; two are closed:
      1. ~~**Legal review.**~~ **Dropped 2026-09-01** — out of reach for now,
         recorded as an accepted risk rather than a forgotten step. What protects
         it is that the data flows were read off the running system; what is
         unreviewed is legal *form*, not factual accuracy.
      2. ~~**A processor agreement with OpenRouter.**~~ Off the blocker list.
         Naming a recipient is an **Article 13** transparency duty and does not
         assert that a contract exists. The **Article 28** contract is a real and
         separate obligation running in parallel; the email went to
         `support@openrouter.ai` on 2026-09-01 and is tracked in
         [openrouter-processor-agreement.md](openrouter-processor-agreement.md).
      3. **Whether the configured `COACH_MODEL`'s provider trains on inference
         inputs.** A per-model property. Answer from the deployed secret;
         [compliance.md](compliance.md) is explicit that guessing from the repo
         is wrong. `data_collection: "deny"` is the control and it is set; what
         is unconfirmed is what it guarantees contractually. **The only item that
         can still change what the policy has to say** — and less than it could
         have, since the wording no longer implies providers never retain.
      4. **The publication date** — replace the `PUBLICATION_DATE` token.
- [ ] **App Privacy ("nutrition labels").** Must match the sub-processor table in
      [compliance.md](compliance.md): Supabase, OpenRouter, RevenueCat, MapTiler.
      Declare, with linkage to identity:

      | Type | What | Linked |
      |---|---|---|
      | Health & Fitness | Workouts and steps read from HealthKit; runs, traces, plans | Yes |
      | Location | Precise, in use **and** in background | Yes |
      | Identifiers | The Supabase `user_id`, which RevenueCat holds as a pseudonymous app user id | Yes |
      | Purchases | Subscription state | Yes |
      | User Content | The runner's own messages to the coach, which reach OpenRouter | Yes |
      | Contact Info | Email, for the account | Yes |

      Backup consent makes several of these conditional and the form has no way
      to express that. **Declare what is collected when consent is on**, which
      is the honest reading of a form that cannot say "sometimes".
- [ ] **Age rating questionnaire.** Nothing objectionable. The one to think about
      is whether the coach counts as user-generated content: it does not — there
      is no sharing and no second user anywhere in the product.
- [ ] **App Review notes**, which [compliance.md](compliance.md) already says are
      needed and are easy to forget:
      - a written justification for always-on location ("recording a run with the
        screen off" is accepted),
      - exactly what health data is read, written, and shared, and with whom —
        answered from the deployed `COACH_MODEL`, not from the repo,
      - how to reach the paid half, since a reviewer's account has no entitlement.
- [ ] **A demo account.** The app opens on a working tracker with no account
      ([ADR-0019](decisions/0019-onboarding-is-two-moments.md)), which is a good
      answer for the free half — but the coach and plans sit behind an account
      *and now behind an entitlement*
      ([ADR-0030](decisions/0030-the-coach-is-the-paid-half.md)). A reviewer who
      cannot reach them may reject for incomplete functionality. **Give them
      credentials, and grant that user a `core.entitlements` row**, or the demo
      account meets exactly the gate they are trying to get past.

---

## Gate 3 — RevenueCat, end to end

**Settled: 1.0.0 ships paid.** The coach costs real money per request through
OpenRouter, so it is the paid half and the gate stays.
[ADR-0028](decisions/0028-revenuecat-is-the-purchase-path.md) records the
purchase path, [ADR-0029](decisions/0029-what-a-tier-costs-and-buys.md) the
prices, [ADR-0030](decisions/0030-the-coach-is-the-paid-half.md) what is gated.

### Built already

- [x] **`core.entitlements`** — one row per (user, app); `product` in
      free/paid/premium, `status` in active/expired/grace/refunded/revoked, plus
      platform, expiry, `source_txn_id` and `event_ms`. **Client-read-only by
      design**: no INSERT/UPDATE/DELETE policy and no grant to `authenticated`,
      because the repo is public and a write path that exists is a write path
      somebody uses. Only `service_role` writes.
- [x] **The server read path** — `supabase/functions/coach/entitlements.ts`,
      `tierFor` mapping a product to a model tier, covered by
      `entitlements_test.ts`. Only `active` grants anything.
- [x] **The client tier model** — `CoachAccess`, defaulting to `free`, every
      unknown answer resolving to `free`, and deliberately *not* read from a
      stored flag: a value a client can write is a value a client can forge.
- [x] **The refusal is a door** — `CoachGateSheet`, plate `C5` on the board.
      Before it, the app offered the coach to everybody and let the Edge Function
      refuse, which surfaced as *"The coach hit a problem. Please try again."*:
      untrue, and an invitation to retry something guaranteed to fail.
- [x] **The dead end is closed.** `HomeShell` now passes `onUpgrade`, so the
      locked last-run card's *"See what a coach adds"* renders and opens that
      sheet. It shipped for a month saying "Upgrade to see this stat" with
      nothing to tap — Guideline 2.1 on its own, whatever is decided about
      payments. `test/home/upgrade_door_test.dart` pins it.
- [x] **The gate copy quotes no price.** A figure compiled into the binary is
      right in one storefront and wrong in every other, and Apple expects the
      localised one StoreKit hands back. `kCoachPrice` / `kSharpCoachPrice`
      remain as the record `limits.ts` is sized against; they are not shown.
- [x] **The webhook Edge Function is built** — `supabase/functions/revenuecat`,
      the only writer of `core.entitlements`. Its mapping is pure and unit-tested
      (16 tests, no store and no database). Ordering needed a migration:
      `source_txn_id` is not a watermark, so `event_ms` was added and an event
      must be strictly newer to win. A replay is a no-op, a late expiry cannot
      revert a live renewal, and a row inserted by hand loses to the first real
      event rather than blocking it.
- [x] **RevenueCat declared as a sub-processor** in all four places that have to
      agree: `docs/privacy-policy.md`, `legal_copy.dart`, `compliance.md`'s
      table, and the generated pages. `legal_copy_test.dart` pins all four
      processors.

### The wiring, in the order it has to happen

The order is load-bearing: since ADR-0030 the coach is refused without a row, and
no row can exist until step 4 is deployed. **Nothing about the paid half works
until this list is finished.**

**Steps 1 to 5 are a click-through in two dashboards, and
[store-setup.md](store-setup.md) is the runbook for them** — every field, the
five strings that must match exactly, and a table mapping each of the webhook's
own ignore reasons to its cause. Read that rather than this for the doing; this
stays the checklist.

- [ ] **1. Apple: paid-applications agreement, tax and banking.** Nothing about
      subscriptions exists in App Store Connect until Business ▸ Agreements is
      active. **This is the longest lead time on the page and nothing depends on
      it** — start it first, then do everything else while it clears.
- [ ] **2. The subscription group and two products.** One group, because the two
      tiers are alternatives and a runner should move between them without a
      second purchase. Per product:
      - reference name, **product id**, duration 1 month
      - price: £1 (`paid`) and £3 (`premium`) per ADR-0029; let Apple's matrix
        set every other storefront
      - localised display name and description (en-GB at minimum)
      - **review screenshot and review notes, per product** — a common cause of
        "Missing Metadata" that holds up the whole submission
      - free trial / introductory offer: **no**, unless there is a reason. A
        trial on a £1 product costs more in support than it earns.
- [ ] **3. RevenueCat: account, project, products imported.** App configured with
      the App Store Connect shared secret and the in-app purchase key;
      entitlement identifiers mapped onto the two products.
- [ ] **4. Deploy the webhook and set its secrets.**

      ```bash
      supabase functions deploy revenuecat --no-verify-jwt
      supabase secrets set REVENUECAT_WEBHOOK_SECRET='<a long random string>'
      supabase secrets set REVENUECAT_PRODUCTS='{"<real product id>":{"app":"run","product":"paid"}, ...}'
      ```

      `--no-verify-jwt` is required rather than lax: RevenueCat is not a
      signed-in user, has no Supabase token, and authenticates with the shared
      secret — which is checked before anything else happens. The product ids are
      **configuration rather than code**, so adding a SKU or changing a price
      does not need a deploy. Full detail in the function's
      [README](../../../supabase/functions/revenuecat/README.md).
- [ ] **5. RevenueCat ▸ Integrations ▸ Webhooks.** URL
      `https://<project>.supabase.co/functions/v1/revenuecat`; Authorization
      header set to `REVENUECAT_WEBHOOK_SECRET` **verbatim** — no `Bearer`
      prefix, because it is compared as-is.
- [x] **6. The SDK in the client.** `purchases_flutter ^10.10.1`, behind a
      `PurchaseClient` interface with a `RevenueCatPurchases` implementation and
      a `FakePurchases` that lets the whole thing be driven from Windows. The
      public key rides in `app_config.json` as `REVENUECAT_PUBLIC_KEY`;
      `codemagic.yaml` writes it, warns loudly when it is unset, and **fails the
      build if it is not an `appl_` key** — a Google key here would configure
      the SDK against the wrong store and fail at the moment of purchase.
      `HomeShell` calls `identify` with the Supabase user id whenever there is a
      session, because the webhook keys the row on it and refuses an
      `RCAnonymousID:` rather than writing to nobody.
- [x] **7. The purchase screen `C5` opens onto** — `PurchaseScreen`, plate
      `paywall` on the board, driven all the way from the coach mark so the
      route is evidence rather than the render alone. Prices come from
      `Offerings`; `purchase_screen_test.dart` prices a fixture in dollars and
      asserts the pounds ADR-0029 settled appear nowhere. It carries both tiers,
      **Restore purchases**, functional links to the **Terms of Use** (Apple's
      EULA) and the **privacy policy**, and the auto-renew disclosure — four
      Guideline 3.1.2 requirements, each with a test named after it.

      Two things the tests caught rather than review: the legal links were a
      `Row` that **overflowed a 430pt phone by 29 pixels**, which on the
      narrowest supported 320pt would have clipped a link Apple requires to be
      functional; and a cancelled purchase was about to be reported as a
      failure, which it is not.
- [x] **8. `CoachAccess` still comes from the server.** `PurchaseClient` has no
      `isSubscribed` and will not get one. The screen reports success only once
      `core.entitlements` agrees, and **polls for it** — zero, one, two, three
      and five seconds — because RevenueCat tells the Edge Function
      server-to-server while the store's sheet is still dismissing, so the first
      read after a payment usually says `free`.

      When the row never arrives it says *"Payment went through. The coach can
      take a minute to unlock"* rather than reporting an error: the money moved,
      and inviting a second purchase is the one outcome worse than waiting. The
      single place the SDK's own view is read is `restore`, and it decides which
      sentence to show rather than what anybody owns.
- [ ] **9. Sandbox purchase on a device** — Gate 1.
- [ ] **10. A processor agreement with RevenueCat**, alongside the OpenRouter
      one.
- [ ] **11. App Privacy: Purchases and the identifier** — Gate 2.

---

## Gate 4 — The listing itself

**The copy is drafted, in
[app-store-listing.md](app-store-listing.md)** — one document, so this stays a
checklist and the writing lives somewhere it can be edited as writing. Every
character count there is verified by `tool/check_listing.py`, which also refuses
a description claiming something the code does not do. What is left here is the
art, and the choices only you can make.

### App information — set once, not per version

- [ ] **Name** (30) — `MGKFitness: Run`, per
      [naming.md](../../../docs/naming.md). Already check by eye that the
      existing App Store Connect record says this: the record existing says
      nothing about what it is called. The **home screen** label stays `Run`
      (`CFBundleDisplayName`), which is deliberate — iOS truncates at roughly
      twelve characters and `MGKFitness: Run` and `MGKFitness: Lift` would both
      render as `MGKFitness:…` on the same phone.
- [ ] **Subtitle** (30) — **three drafted, one to pick.** Recommended:
      `Track runs. Get a real plan.` (28). It sits under the name in every search
      result and is the second thing anybody reads.
- [x] **Primary category** Health & Fitness, **secondary** Sports.
- [ ] **Content rights.** Run does not ship third-party content the way Lift does
      (Lift's exercise illustrations are CC BY-SA), but the **MapTiler basemap**
      is third-party and attribution obligations apply. Confirm the in-app map
      attribution is present and answer the question accordingly.
- [ ] **Licence agreement** — Apple's standard EULA, or the custom one from
      Gate 2.
- [ ] **Age rating** — Gate 2.

### Version information — 1.0.0

- [x] **Promotional text** (170) — drafted at 158, which leaves room for a
      launch line. Changeable without review, so it is the right place for
      anything that will move.
- [x] **Description** (4000) — drafted at 3,182, so there is room for a
      paragraph somebody wants to add. What it had to do, and does:
      - lead with the free half, because it is most of the app and because the
        gate copy already makes that promise — a listing that leads with the
        subscription and a gate that leads with what is free are two different
        products
      - say plainly that the coach is a subscription, and name what it does
      - carry the **medical disclaimer in short form**. The app gates onboarding
        on it; a listing that omits it is claiming something the app refuses to.
      - **auto-renewable subscription disclosure**: title, length, price, and
        that payment is charged to the Apple ID — Apple wants this in the
        description as well as on the paywall
- [x] **Keywords** (100) — drafted at 90. Comma-separated with no space after
      the comma, because the spaces count; nothing repeated from the name, which
      Apple indexes separately; and no competitor named, which is a rejection.
      `check_listing.py` asserts all three.
- [ ] **Support URL** — Gate 2. Required.
- [ ] **Marketing URL** — optional; `mgkcodes.com` if there is a page worth
      landing on.
- [x] **Copyright** — `2026 MGKCodes Ltd`.
- [ ] **Screenshots.** **Read the exact required set off App Store Connect
      rather than trusting a number written here** — at time of writing it wants
      a 6.9" set (1320×2868 or 1290×2796) and derives the smaller sizes.
      Between three and ten; the first two are what shows in search, so they
      carry the argument on their own.

      **The board's plates are not usable as store assets** — they are 393×852
      logical renders at 2–3× for design review, and the store wants device-sized
      art with a caption band. What the board *is* good for is choosing which
      screens to shoot: the strongest six are `H1` (a plan and today's session),
      `R4` or `R5` (a run in progress), `F1` (a finished run), `P2` (a week
      opened), `C3` (the coach answering), `S4` (a year of running). Take them
      from a real device on TestFlight, not from the plate harness — the basemap
      tiles are absent in the harness, and the map is half of what makes `R4`
      worth showing.
- [ ] **App preview video** — optional, and genuinely optional. Skip for 1.0.0.
- [ ] **App icon.** Already in the binary; confirm the 1024×1024 marketing icon
      is set in App Store Connect and has **no alpha channel and no rounded
      corners** — the most common trivial rejection there is.
- [ ] **"What's New"** — not required for a first version.
- [ ] **Sign-in required?** Answer **no**, and say why in the review notes: the
      app opens on a working tracker with no account. Then give the demo account
      anyway, for the coach.
- [ ] **Contact information** for review — name, phone, email.

### Before hitting Submit

- [ ] **Export compliance** — already answered in `Info.plist`, so this should
      not appear. If it does, something changed.
- [ ] **Advertising identifier (IDFA)** — **no**. Nothing in the app advertises
      or attributes.
- [ ] **Version release option** — manual release, for a first version. Automatic
      means it goes live the moment review passes, at whatever hour that is.
- [ ] **Phased release** — irrelevant for 1.0.0 (it only applies to updates).

---

## Gate 5 — Would pass the form and fail the review

- [x] **`TARGETED_DEVICE_FAMILY` set to `"1"` — iPhone only**, and **proven by
      build 11**. It was `"1,2"`, Flutter's default, which nobody chose: Apple
      would have required an iPad screenshot set and **reviewed the app on an
      iPad**, and nothing here has ever been laid out for one — the widest
      surface the board tests is 430pt. iPhone-only is the honest description of
      what was built and matches [ADR-0001](decisions/0001-flutter-ios-only.md).
- [x] **`steps` and `elevation_max_m` are mirrored.** `run.runs` gained both
      columns and both sides of the seam read and write them.
      `mirror_round_trip_test.dart` pins the invariant that broke: every column
      the mirror writes must be one the restore reads.
- [x] **Elevation converts at display.** `Elevation` lives in `mgk_units`
      alongside `Distance`, `Pace` and `Mass`, following the **distance** system
      rather than having a unit of its own — kilometres with pounds is an
      ordinary combination, miles with metres of climb is not.
- [ ] **`NSHealthUpdateUsageDescription` describes a write that never happens.**
      `health_read_types.dart` requests `HealthDataAccess.READ` for `WORKOUT` and
      `STEPS` and nothing else, but `Info.plist` carries a purpose string saying
      *"Save the runs you record here into Health"*. The comment beside it admits
      the app does not write yet. A purpose string for a permission the binary
      never exercises is at best noise a reviewer reads and cannot verify, and at
      worst Guideline 5.1.1 — requesting access it does not use. Either build the
      write or drop the key; do not ship the sentence.
- [ ] **Decide what elevation does at launch.** The tiles are built end to end
      and permanently read "not recorded", because there is no barometric source
      ([ADR-0024](decisions/0024-elevation-is-barometric-or-absent.md)). That is
      defensible — absent beats a plausible wrong number — but a reviewer or a
      tester sees a metric the app advertises and never fills. Either build
      `CMAltimeter`, or make sure it reads as deliberate rather than broken.
      **The only item on this page that could reasonably change what 1.0.0
      contains**, which is why it is decided last.

---

## Gate 6 — Documents that were wrong

Cleared 2026-09-01, and again on 2026-09-02. Recorded rather than deleted,
because this is the kind of staleness that is invisible until somebody acts on
it.

- [x] **`compliance.md` described a function that no longer existed** —
      `runio_delete_account` sweeping "every table in the `runio` schema", a
      month after that schema was renamed to `run`. **The code was right and the
      document defending it to a regulator was not**, which is the worse way
      round.
- [x] **`codemagic.yaml`'s header contradicted its own workflow list.**
- [x] **`roadmap.md`** retitled and reconciled with this document rather than
      maintained beside it — two checklists being how one goes stale.
- [x] **Lift's test sheet granted an entitlement that could not exist** —
      `platform = 'manual'` against a `check (platform in ('apple','google'))`,
      so anyone who ran it tested the free half of Lift believing it was the paid
      one.
- [x] **This document was 18 commits stale**, which is what prompted the rewrite.
- [ ] **`product-spec.md` stopped tracking the build.** It is titled "Runio",
      is marked **"Pre-alpha (design)"**, and its decisions table promises
      HealthKit writes the app does not do. It is named as the source-of-truth
      product definition and is the document a listing would naturally be written
      from — which is why the listing copy was written against the code instead,
      and why this is worse than it looks.
- [ ] **`release-1.0.0.md` is still ~12 commits stale.** Its phases are ticked
      but the account-removal work and everything after it is missing. Lower
      priority than the rest, because it misleads about *history* rather than
      about how the system behaves now.

---

## Explicitly not blocking

Recorded so nobody re-opens them under deadline:

- **Heart rate, cadence, active energy.** Stopped on purpose, with reasons, in
  [release-1.0.0.md](release-1.0.0.md)'s "Deliberately not built".
- **In-run audio** — [ADR-0006](decisions/0006-in-run-audio-deferred.md).
- **The Android release pipeline.** The APK workflow is a verification harness,
  not a product ([ADR-0021](decisions/0021-android-is-a-target.md)); nothing
  ships to Play for Run at 1.0.0.
- **Going open source.** `roadmap.md` lists a git-history secret scrub as part of
  "v1 shippable". It is a prerequisite for making the repo *public*, not for
  shipping the app, and conflating them adds a hard job to the critical path for
  no store benefit.
- **Bests, and the coach's memory surface.** Named on the board as missing
  screens. Neither is a submission blocker.

---

## The order

Three things have somebody else's clock on them. Start those first and do
everything else while they run.

1. **Apple's paid-applications agreement, tax and banking** (Gate 3, step 1).
   Longest lead time on the page, and every subscription product is blocked
   behind it.
2. **The OpenRouter reply** — sent 2026-09-01, tracked in
   [openrouter-processor-agreement.md](openrouter-processor-agreement.md). Only
   blocker 3 depends on it, and only for a sentence.
3. **Stand up `mgkfitness.mgkcodes.com`, and settle the EULA and support URL**
   (Gate 2). The legal pages go at `/run`, generated and static, with
   word-for-word parity with the in-app copy. Depends on nothing else here, and
   the same subdomain later carries the marketing pages for both apps.

Then, in order:

4. **Run a TestFlight build** and work Gate 1 on a device, starting with the
   23 Aug recovery. The payment work does not block it — the app is on `free`
   until a webhook says otherwise.
5. **Gate 3, steps 2 to 8** — products, RevenueCat, the webhook deployed, the
   SDK, the purchase screen. This is the largest remaining body of code.
6. **Write Gate 4.** Subtitle, description, keywords, then screenshots off a
   real device once the paid half is reachable — the coach is worth two of the
   six shots and cannot be photographed until step 5 is done.
7. **Fill in Gate 2's forms** in App Store Connect, once there is a build to
   attach them to.
8. **Sandbox purchase on a device** (Gate 1), which is the last thing that can
   fail quietly.
9. **Decide Gate 5's elevation question** last — the only item that could
   reasonably change what 1.0.0 contains.
