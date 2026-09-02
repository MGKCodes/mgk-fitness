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
// The two consts below are the record of what was agreed. **They are not what
// a runner is shown.** The copy quoted them for a day and should not have: a
// price typed into the binary is right in one storefront and wrong in every
// other, it is stale the moment pricing moves, and Apple expects the figure on
// screen to be the localised one StoreKit hands back. So the sentence names the
// tier and the store names the price, which is also the only arrangement that
// survives a currency the app has never heard of.
//
// Until RevenueCat is wired there is no price to show, and the sheet says so
// rather than inventing one. `plan_gate_copy_test.dart` asserts the copy quotes
// no figure at all.
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

/// The premium coach, monthly. `product = 'premium'`, model tier `sharp`.
///
/// Named for the **product**, not the model tier. `core.entitlements.product`
/// has said `premium` since the table was written, and the App Store calls it
/// Premium Coach, so the two names anybody ever says out loud now agree. The
/// third name, `sharp`, stays where it belongs: it is a model tier in
/// `entitlements.ts`, and a runner never meets it.
const String kPremiumCoachPrice = '£3';

/// What a plan costs, in the coach's voice.
///
/// See the PRICING block above before editing.
const String planGateCostsCopy =
    'Recording your runs is free and always will be. A plan is different: '
    'building one and keeping it honest week to week needs a subscription. '
    'Your runs and your history stay yours either way.';
