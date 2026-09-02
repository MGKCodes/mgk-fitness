# 0028 — RevenueCat is the purchase path, and the webhook is the truth

**Status:** Accepted

## Context

[ADR-0014](0014-model-is-chosen-per-surface-and-per-tier.md) settled that a
runner's tier decides which model serves them, and that the tier must come from
"an entitlement keyed to a verified App Store transaction". It did not say who
verifies it. That gap is now the only thing between the app and a paid release.

**Half of this is already built, and it is the half that is hard to retrofit.**

`core.entitlements` holds one row per (user, app), and it is **client-read-only
by construction**: no INSERT, UPDATE or DELETE policy, no grant to
`authenticated`, `service_role` alone. The repo is public, so a write path that
exists is a write path somebody uses. Its comment already names the writer —
"an Edge Function that has already validated the receipt with Apple or Google" —
which is a decision this record is only now making explicit.

The read path is finished too: `entitlements.ts` reads the row, `tierFor` maps
`product` to a model tier, the coach function calls it, and only `active` grants
anything. On the client, `CoachAccess` defaults to `free` and resolves every
unknown answer to `free`, deliberately not from a stored flag, because a value a
client can write is a value a client can forge.

**What does not exist is every part that touches a store.** No purchase SDK in
either app. No function that validates a receipt — three Edge Functions, and not
one of them writes an entitlement, so no row has ever existed. No products in
App Store Connect.

Three facts shape the choice:

- **The suite needs Apple and Google.** Run is iOS-only
  ([ADR-0001](0001-flutter-ios-only.md)), but Lift ships to both, so a
  suite-wide answer spans two stores. Doing it directly means StoreKit 2 *and*
  Google Play Billing, plus two unrelated server-notification formats — Apple's
  ASSN v2, JWS-signed, and Google's RTDN over Pub/Sub.
- **The status column is the hard part.** `core.entitlements.status` is
  `active | expired | grace | refunded | revoked`. Grace periods, billing
  retry, refunds and revocation are where subscription code goes wrong, and it
  goes wrong *quietly*: somebody keeps access after a refund, or loses it during
  a billing retry that was going to succeed. Deriving those five states from raw
  store notifications is the work; presenting a paywall is not.
- **The pricing is undecided**, and nothing here depends on it.

## Decision

**RevenueCat is the purchase and subscription-state provider for both apps.
Its webhook is the only thing that writes `core.entitlements`.**

- The app uses the RevenueCat SDK **only to present and perform a purchase**.
  It does not decide access.
- **A RevenueCat webhook calls a Supabase Edge Function**, which writes
  `core.entitlements` under `service_role`. That is the writer the migration
  comment already anticipated, so nothing about the schema changes.
- **The Supabase `user_id` is the RevenueCat App User ID.** It makes the
  webhook-to-row mapping trivial and it is a pseudonymous identifier, so no
  health data goes near them.
- **The client is never the source of truth.** `CoachAccess` keeps coming from
  the server. Reading `CustomerInfo.entitlements.active` on device and unlocking
  from it is specifically forbidden: it would replace a fact with a claim, which
  is the property `coach_access.dart` exists to hold.
- **The public SDK key ships in the client** via the existing
  `app_config.json` / `--dart-define-from-file` mechanism, alongside
  `SUPABASE_URL`. It is designed to be embedded and a public repo is fine. **The
  webhook secret is server-side only** and never reaches a client, per
  [ADR-0007](0007-secrets-via-backend-proxy.md).
- **The webhook function is idempotent and tolerates out-of-order events.**
  `source_txn_id` exists to compare against.

StoreKit 2 was the alternative and is genuinely good — `Transaction.currentEntitlements`,
auto-verified JWS, and the deployment target is already iOS 15. Had Run been the
only app it would have been close. It is not the iOS half that decides this; it
is Android and the five-state lifecycle.

## Consequences

**RevenueCat becomes a named sub-processor.** It receives an app user ID and
purchase data. That means an entry in `docs/privacy-policy.md`'s sub-processor
list and the matching one in `legal_copy.dart`, a row in `compliance.md`'s
table, a declaration in App Privacy, and a processor agreement alongside the
OpenRouter one. This is the real cost of the decision, and it is why it was
taken while the privacy policy was still unpublished — adding a sub-processor to
a live policy is more expensive than adding one to a draft.

**A third party sits on the money path.** If RevenueCat is down, purchases fail;
if their webhook is delayed, an entitlement lands late. Neither breaks the app —
`CoachAccess` resolves unknown to `free`, so the failure mode is a runner
briefly not getting what they paid for, which is recoverable and quiet in the
right direction. The reverse (granting what was not bought) is not possible from
a delayed webhook.

**The exit is cheap by construction, and that is the point.** The table, the
read path and the client model do not know RevenueCat exists. Replacing it means
writing a different Edge Function that writes the same five statuses to the same
row. Nothing above the writer changes.

**We accept a dependency we do not control the pricing of.** Historically free
under a monthly-tracked-revenue threshold, then a percentage. If that changes,
the exit above is what makes it survivable rather than fatal.

**Restore purchases comes with it**, which Apple requires and which would
otherwise be a task.

**ADR-0015 is now on the critical path for pricing.** Its spend ceilings in
`supabase/functions/coach/limits.ts` are sized against a £1 monthly
subscription that is still a placeholder
([ADR-0015](0015-spend-is-capped-over-three-windows.md)). Settling the price is
not a marketing decision alone; it re-sizes a cost control.

**What this does not decide:** the price, the tier names, or what `premium`
contains beyond `paid`. `plan_gate_copy.dart` still quotes no figure and
`plan_gate_copy_test.dart` still asserts that it does not.
