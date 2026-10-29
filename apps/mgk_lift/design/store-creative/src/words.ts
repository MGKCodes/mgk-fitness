/**
 * Every word on the header and search results assets.
 *
 * **Copied, not written.** Each line is a phrase the App Store listing already
 * says (apps/mgk_lift/store/listing.json, from docs/store-listing.md), so an
 * asset cannot promise more than the description does:
 *
 * - "Built for the minute between sets." is the description's first line,
 *   "Lift is a strength-training log built for the minute between sets."
 * - "Log every set." and "Every session, kept on your phone." are the first
 *   and third store pictures' headlines (store-shots/src/shots.ts).
 * - "Log a set / in one tap." is the promotional text's "Log a set in one
 *   tap", cut in two.
 * - The rest clock counts on past zero because the description says it does:
 *   "counts on past zero so you know how long you actually rested."
 *
 * **What may not be said.** No price and no "Free": Apple's guidance for these
 * assets rules out pricing, and the listing's own rule since 2026-10-07 is that
 * store pictures never name one. Nothing here shows the coach, the plan or the
 * photos, which are the subscription, so nothing needs a subscription tag.
 * The screens are the three the listing already calls free: logging, the
 * finished session and the training totals.
 */
export const WORDS = {
  /** The suite, over the app's name, as the launch and the feature graphic set it. */
  suite: 'MGKFITNESS',
  name: 'LIFT',
  /** The header's line. */
  line: 'Built for the minute between sets.',
  /** The search results asset: a headline, and a line under it in silver. */
  search: ['Log every set.', 'Every session, kept on your phone.'] as [string, string],
  /** The universal asset's two lines: white, then silver. */
  universal: ['Log a set', 'in one tap.'] as [string, string],
};

/**
 * The screens, as tool/capture_store_screens.mjs names them. `hero` is the one
 * a single phone shows; the session is in progress and resting, so the clock
 * is running at the foot of the screen.
 */
export const SCREENS = {
  hero: 'session-resting',
  finished: 'session-summary-pb',
  totals: 'profile',
};

/** The status bar's clock, as store-shots has it. No screen shows the time of day. */
export const TIME = '18:41';
