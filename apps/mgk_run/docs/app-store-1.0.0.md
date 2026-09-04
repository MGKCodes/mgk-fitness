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

- **1,391 tests pass, analyzer and format clean** — verified 2026-09-04, after
  the build 12 field-test fixes (3 skipped by design, `@Tags(['live'])`, they
  hit the real backend). 199 Deno tests pass alongside them. Including
  `naming_test.dart`, which fails the build if a retired product name reaches a
  string a runner reads.

  **Build 12 is superseded. Build 13 (`75a89df`) was triggered 2026-09-04** and
  carries eighteen commits of fixes, none of them yet on a device. What is
  written below as done on hardware was done on *build 12*.
  [The test sheet](testflight-1.0.0-test-sheet.md) is rewritten for build 13:
  86 rows, with section G moved **before** the outdoor run because it is the
  most submission-critical thing on it and has never once run — last time it sat
  behind the weather and the afternoon ended first.

  **This is the only place the figure is written down.** It said 1186 in
  `apps/mgk_run/CLAUDE.md` while the suite passed 1352, so that second copy was
  deleted rather than corrected — a number kept in two places is a number that
  drifts, and the same failure had two release checklists disagreeing about the
  RevenueCat offering.
- **The iOS pipeline has run end to end.** `Run — iOS TestFlight` in
  `codemagic.yaml`, signing via the team's `frunt_asc` App Store Connect key,
  publishing with `submit_to_testflight: true`. **Build 12 succeeded on
  2026-09-02**, every step green including Publishing — the first build carrying
  the RevenueCat SDK, the paywall, the wired `onUpgrade`, the gate sheet's
  surface and the `appl_` key. Triggered through Codemagic's REST API rather
  than the UI. Build numbers come from `$PROJECT_BUILD_NUMBER`, so `1.0.0+1` in
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
- **Every screen is on a board** —
  [the contact sheet](https://claude.ai/code/artifact/9ddfd186-11ad-4260-bde9-ef8b7a5d9190),
  rendered 2026-09-02 at `31b7ce3`.

  **Two counts, both true, and they are not the same thing.** The board shows
  **73** plates (33 of them driven through the real app). `board.state.json`
  records **77** captures. The four it holds that the board does not show are
  `account-gate`, `keep-runs-safe`, `settings-no-account` and `hero_weights`.
  This page said 73, was changed to 77 on 2026-09-03, and is now precise
  instead — a single number here could only ever have been wrong about one of
  the two.

  **Neither count includes the paywall.** `flows.dart` generates `paywall` and
  `paywall-store`; `board.state.json` carries neither, because the board
  predates them. The board's own *Not on the board yet* table still lists the
  purchase screen as missing "because RevenueCat is chosen and unbuilt", which
  has been untrue since 2026-09-02.

  **And `board.state.json` is maintained by hand.** `plate()` writes PNGs into
  the git-ignored `plates/` and never touches the state file, so the stamps are
  a human promise rather than a record. Every one still reads `31b7ce3` while
  `flows.dart` has moved three times since (`406aab4`, `7f0692a`, `34b5439`).
  It should be written by the harness. Not a phone job, and not a blocker.

**What has never happened is a submission.** Day-to-day development is on
Windows against an Android emulator, which is why every device question below is
answered on TestFlight rather than here.

---

## Gate 1 — What only a device can answer

Build 11 settled four unknowns: `TARGETED_DEVICE_FAMILY = "1"` compiles, code
signing resolves for the bundle id, the artefact globs match, and an App Store
Connect record exists.

**Build 12 is in TestFlight and carries everything below.** Every item in this
gate is now answerable in one sitting, and none of them has been answered:
nothing from 1 Sep onwards has been on a phone, the payment arc included.

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
- [ ] **Sandbox purchase.** Both products are Ready to Submit, the offering is
      CURRENT, and `REVENUECAT_ACCEPT_SANDBOX=true` is already set on the
      deploy — so the only missing piece is a sandbox Apple ID and a device.
      Section G of [the test sheet](testflight-1.0.0-test-sheet.md) walks the
      whole chain. Belongs to Gate 3 but lands here, because it cannot be proven
      from Windows. **Unset the flag before submitting.**

---

## Gate 2 — Submission blockers

App Store Connect will not accept a submission without these. None are code.

- [x] **A published privacy policy URL** — **`https://mgkfitness.mgkcodes.com/run/privacy`**,
      live 2026-09-03.

      Verified rather than assumed: 200 with a valid certificate, reachable with
      no cookies and no login (App Review has no account), `/nope` correctly
      404s, and `/run/privacy-policy.html` 308s to the clean URL so each document
      answers at exactly one address.

      **And it is serving the generated artefact.** The live page still carries
      the `GENERATED by tool/build_legal_pages.py` banner, which is the exact
      string `legal_copy_test.dart` asserts on — so the word-for-word parity a
      reviewer checks between the page and the app is enforced by CI rather than
      by discipline. That is the whole reason `web/` lives in this repository.

      Still to paste into App Store Connect's required field. `web/` is a Next.js app serving
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
      the listing's terms field and in App Store Connect's EULA field.

      **The in-app half is finished, 2026-09-03.** The paywall links to it
      (`purchase_screen_test.dart`), and `legal_screen.dart` now carries a
      fourth row pointing at the same URL, so it is reachable from Settings by
      somebody who is not mid-purchase — a reviewer working through Settings,
      or a runner reading what they agreed to afterwards. `kTermsOfUseUrl` moved
      to `legal/domain/legal_urls.dart` so that neither screen owns it and
      `legal/` does not import `coaching/` to show a legal document.
      `legal_screen_test.dart` pins the row and the destination.

      **What is left is both App Store Connect fields**, which is form-filling
      in Gate 2's sitting rather than code.
- [x] **A support URL** — **`https://mgkfitness.mgkcodes.com/run/support`**,
      live 2026-09-03 and verified alongside the policy. It answers the three things a
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

The order is load-bearing: since ADR-0030 the coach is refused without a row,
and no row can exist until the webhook is deployed. **Nothing about the paid
half works until this list is finished.**

#### Steps 1–5: the two dashboards

Apple's agreements, tax and banking; the subscription group and its two
products; the RevenueCat project with its entitlements and a CURRENT offering;
the deployed webhook and its secrets; and the webhook registration.

- [x] **All of it, confirmed 2026-09-03.** **The checklist lives in
      [store-setup.md](store-setup.md) §1–7 and nowhere else** — every field,
      the five strings that must match exactly, and a table mapping each of the
      webhook's own ignore reasons to its cause.

      **It used to be listed here as well, with its own tick boxes, and the two
      copies disagreed.** This page said the RevenueCat setup was complete while
      the runbook still had the offering unticked — and no CURRENT offering is
      the single misconfiguration that produces a calm, correct and entirely
      misleading paywall reading *"Not available to buy yet"*. A sandbox failure
      would have been hunted in the app.

      Two checklists for one job is how one of them goes stale, which Gate 6
      already recorded about `roadmap.md` and which this page then did anyway.
      The runbook is finer-grained and is read with a dashboard open, so it
      keeps the boxes. This stays the plan.

#### Steps 6–11: code in this repository

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
- [x] **7. The purchase screen `C5` opens onto** — `PurchaseScreen`, driven all
      the way from the coach mark so the route is evidence rather than the
      render alone.

      **It is not on the board**, and this said "plate `paywall` on the board"
      until 2026-09-03. `flows.dart` generates `paywall` and `paywall-store`,
      but the board was captured at `31b7ce3` before either existed and
      `board.state.json` carries neither. The store-sized one is exported to
      `store-assets/derived/run-iap-review-screenshot.png` and is what satisfies
      the per-product review screenshot in [store-setup.md](store-setup.md) §2.

      Two naming systems collided in that sentence, which is why it went
      unnoticed: `C5` is a **board code**, and board codes exist only inside the
      published contact sheet — nowhere in `test/plates/`. `paywall` is a
      **harness plate id**. They are not the same namespace. Prices come from
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
      opened), **`C4`** (the coach answering), `S4` (a year of running). Take
      them from a real device on TestFlight, not from the plate harness — the
      basemap tiles are absent in the harness, and the map is half of what makes
      `R4` worth showing.

      **This said `C3` until 2026-09-03, which named one plate and described
      another.** On the board `C3` is the conversation merely opened and `C4` is
      the coach answering a suggestion — and the answering one is the picture
      that argues for a coach. Read off the board rather than inferred.

      Those are **board codes, and they exist only inside the published contact
      sheet** — not in `test/plates/`, so they cannot be resolved from this
      repository. The mapping onto the semantic plate ids in `board.state.json`
      lives in section H of
      [the test sheet](testflight-1.0.0-test-sheet.md), once: do not copy it
      here.

      ⚠ **The list of which six to shoot is in three places** — here, section H
      of the test sheet, and `app-store-listing.md`, which
      `store-assets/README.md` names as its home. Three copies of one list is
      the failure this page has already recorded twice, and it has not been
      resolved: it is written down here so the next person to touch it picks an
      owner rather than adding a fourth.
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

      **It costs more than it looked, found 2026-09-03 by looking at the
      plate.** `run-complete` is the finished-run screen, and it is also listing
      screenshot **H3**. The plate shows a six-tile grid with elevation gain and
      max elevation filled in, because its fixture supplies altitude; on a
      device both read "not recorded". So the App Store shot has **two of six
      tiles empty** — and the plate is precisely why nobody noticed, since it
      renders a state the app cannot produce.

      That reframes the decision. It is not only whether absence reads as
      deliberate to a reviewer, it is whether a third of the stat grid reads as
      deliberate in a picture chosen to sell the app. Three ways out: build
      `CMAltimeter`, drop the two tiles for 1.0.0, or shoot H3 framed on the
      splits instead. **The phone answers which.**

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

**Five of the nine steps below are done, and a sixth is sent and waiting on
somebody else.** What is left is one sitting on a phone, one form-filling
session in App Store Connect, and one decision.

⚠ **Step 7 happened on 2026-09-04 and did not close.** The sitting stopped at
section F, so the purchase chain (G, 22 rows) and the listing screenshots
(H, 6 rows) were never reached — the two things build 12 was cut to test. It
found four blockers and a fifth nobody had filed as one, all now fixed and none
of them on a device. **Step 7 is therefore still open, against build 13**, and
the rows it never reached are still the rows that decide whether 1.0.0 can be
submitted at all.

A new open item, from the same afternoon: **plans anchor week 1 to
`mondayOf(now)`**, so a plan built on a Friday opens with Monday to Thursday
already behind it. Race day is fixed (a session may no longer land on it); this
half is a decision rather than a patch, because the fix is the anchor — start
on the coming Monday, or count the block backwards from race day as ADR-0027
already claims it does — and either changes what every plan looks like.
`PlanRules.rejectPastDays` exists ready for it.

*Said "six" until 2026-09-03, while only five were struck through. Step 2 is
sent, not finished — counting a posted email as done is how the one item with
somebody else's clock on it stops being chased.*

Struck through is finished — kept rather than deleted, because the sequence is
the useful part and a list that only shows what remains loses it.

1. ~~**Apple's paid-applications agreement, tax and banking.**~~ Active, and
   held by the team rather than the app.
2. **The OpenRouter reply** — sent 2026-09-01, tracked in
   [openrouter-processor-agreement.md](openrouter-processor-agreement.md).
   **Still outstanding, and the only thing waiting on somebody else.** Blocker 3
   depends on it, and only for a sentence.
3. ~~**Stand up `mgkfitness.mgkcodes.com`, settle the EULA and the support
   URL.**~~ Live 2026-09-03; both URLs verified against the running site, and
   the served page still carries the banner `legal_copy_test.dart` asserts on.
4. ~~**Run a TestFlight build.**~~ Build 12, 2026-09-02, every step green.
5. ~~**Gate 3, the wiring**~~ — the two dashboards, the webhook, the SDK, the
   purchase screen. Everything except the sandbox purchase itself.
6. ~~**Write Gate 4's copy.**~~ Description, keywords and promotional text
   drafted and machine-checked by `tool/check_listing.py`. The subtitle is three
   drafts with one still to pick.

Then what is actually left:

7. **One sitting on the phone**, working
   [the test sheet](testflight-1.0.0-test-sheet.md) end to end. **Attempted on
   build 12, 2026-09-04, and it did not finish** — it stopped at section F, so
   G and H are still unproven. It was not wasted: it found the purchase chain
   granting nothing, the coach reachable through six ungated doors, sync doing
   nothing in either direction, plans training on race day, an account created
   silently offline, and a backup switch that promised erasure and performed
   none. All fixed; none verified on hardware. **Cut build 13 and work the whole
   sheet, G and H included.** Unset `REVENUECAT_ACCEPT_SANDBOX` when it is over.
8. **Fill in Gate 2's forms** in App Store Connect — App Privacy, the age
   rating, the review notes, and a demo account with an `active` entitlement
   row. Nothing blocks this beyond wanting the phone's answers first.
9. **Decide Gate 5's elevation question** last. It is the only item that could
   reasonably change what 1.0.0 contains, and the only one the phone can
   actually inform: a plate cannot tell you whether "not recorded" reads as
   deliberate or as broken.
