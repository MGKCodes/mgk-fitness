/// What the coach says at the gate in front of a plan.
///
/// This copy used to sit in the pre-account intro as `introCostsCopy`, said to
/// every runner before the sign-up form. It moved when onboarding split in two
/// (ADR-0019): recording and logging are free and need no cost conversation,
/// and the only moment a price is relevant is the one where a runner is deciding
/// whether to buy a plan.
///
/// ADR-0018's actual principle survives the move. "A cost discovered after
/// signing up is a cost that was hidden" was never about the sign-up form
/// specifically; it was about stating the price before the runner commits. The
/// commitment is now the purchase, and this is what is said immediately before
/// it.
library;

// ─────────────────────────────────────────────────────────────────────────────
// PRICING — PLACEHOLDER
//
// **This is the one place Runio talks about money. Change it here.**
//
// The tiers are not decided yet. ADR-0014 defines them architecturally and pins
// every runner to `free` until a verified App Store entitlement exists, so
// there are no figures to quote and inventing them would ship a commercial
// claim nobody has agreed.
//
// What is written below is deliberately true-but-vague: it says a plan is a
// paid thing and that recording runs is not, without naming a price, a tier, or
// a limit. When the pricing lands, replace [planGateCostsCopy] and check:
//
//   1. `test/coaching/plan_gate_copy_test.dart` — asserts no figure is quoted.
//      That test should be REPLACED, not deleted, once figures are real.
//   2. `docs/product-spec.md` — the tiers belong there too.
//   3. App Store metadata, if a subscription is being declared.
//   4. `docs/decisions/0015-spend-is-capped-over-three-windows.md` — its whole
//      cost argument is written against a £1 monthly subscription. If the price
//      moves, the spend ceilings in `supabase/functions/coach/limits.ts` are
//      sized against the wrong number.
//
// Keep it short. This is a sentence in a conversation, not a pricing page.
// ─────────────────────────────────────────────────────────────────────────────

/// What a plan costs, in the coach's voice.
///
/// See the PRICING block above before editing.
const String planGateCostsCopy =
    'Recording your runs is free and always will be. A plan is different: '
    'building one and keeping it honest week to week costs real money behind '
    'the scenes, so it needs a subscription. Your runs and your history stay '
    'yours either way.';
