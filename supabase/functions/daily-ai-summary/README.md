# `daily-ai-summary`

**Owner: the live React Native Liftio on the App Store. Not Run. Not
`apps/mgk_lift`. Do not delete.**

This was the only function in `supabase/functions/` without a README, which is
part of why it reads as orphaned. It is not orphaned — its caller is simply in
another repository.

## Who calls it

| Function | Called by | Gated on |
|---|---|---|
| `coach` | `apps/mgk_run`, `apps/mgk_lift` | `core.entitlements`, 402 before any token is spent (ADR-0030) |
| **`daily-ai-summary`** | **legacy Liftio (React Native), separate repo** | JWT + a daily per-user limit |
| `delete-account` | both Flutter apps | JWT, app-aware |
| `revenuecat` | RevenueCat's webhook | shared secret |

A repo-wide grep for `functions.invoke` finds four call sites and none of them
is this one. That is expected and is **not** evidence that it is dead. It was
read as exactly that during a gating audit on 2026-09-10, which is what prompted
this file.

## When it becomes deletable

When the App Store build of Liftio is superseded by `apps/mgk_lift`. The Flutter
rewrite does not use this function — its coach prose goes through `coach` on the
`lift_summarise` surface, entitlement-gated like everything else there. Until
that supersession actually ships, deleting this breaks the summary on every
phone running the live build.

See the decision *Liftio is replaced, not relaunched*.

## Known gap

No entitlement check. It verifies a JWT and spends a model call; `coach` reads
`core.entitlements` first and refuses an unpaid caller. So any signed-in account
can reach Haiku through this once per day.

Whether that is a defect is genuinely open, and this repository cannot settle
it: it depends on whether the daily summary was a paid feature in the shipped
Liftio and whether its gate was client-side only, and the client is not here.
What bounds the exposure meanwhile:

- one LLM call per user per day (`ai_summary_requests`)
- a global circuit breaker (`DAILY_GLOBAL_LIMIT`)
- a 2 KB payload cap

**If the answer turns out to be "it was paid"**, the fix is to read
`core.entitlements` the way `supabase/functions/coach/entitlements.ts` does,
against `app = 'lift'` — not to invent a second mechanism.
