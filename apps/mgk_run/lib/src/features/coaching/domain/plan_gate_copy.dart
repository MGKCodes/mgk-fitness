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

// ──────────────────────────────────────────────────────────────────────────
// PRICING
//
// **This is the one place the app talks about money. Change it here.**
//
// Settled by ADR-0029 (docs/decisions/0029-what-a-tier-costs-and-buys.md),
// which carries the arithmetic: what each tier nets after VAT and Apple's cut,
// and the spend ceiling sized against it in supabase/functions/coach/limits.ts.
//
// The two consts below are the single source of the figures. [planGateCostsCopy]
// interpolates them and `plan_gate_copy_test.dart` asserts it does, so a price
// cannot drift between the sentence a runner reads and the record of the
// decision behind it.
//
// If either price moves, three things move with it:
//
//   1. `supabase/functions/coach/limits.ts` — every ceiling there is a fraction
//      of that tier's net revenue, so a new price makes them the wrong size.
//   2. `docs/product-spec.md`.
//   3. The subscription products in App Store Connect.
//
// Keep the copy short. This is a sentence in a conversation, not a pricing page.
// ──────────────────────────────────────────────────────────────────────────

/// The coach, monthly. `product = 'paid'`, model tier `standard`.
const String kCoachPrice = '£1';

/// The sharper coach, monthly. `product = 'premium'`, model tier `sharp`.
const String kSharpCoachPrice = '£3';

/// What a plan costs, in the coach's voice.
///
/// See the PRICING block above before editing.
const String planGateCostsCopy =
    'Recording your runs is free and always will be. A plan is different: '
    'building one and keeping it honest week to week costs real money behind '
    'the scenes, so it needs a subscription. That is $kCoachPrice a month, or '
    '$kSharpCoachPrice for a coach that thinks harder about your week. Your '
    'runs and your history stay yours either way.';
