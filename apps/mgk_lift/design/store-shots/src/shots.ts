/**
 * The six pictures, in the order the stores show them, and the words on each.
 *
 * **The tag says what costs money.** Both stores ask a listing to make clear
 * which of the things it shows need a purchase (App Review guideline 2.3.2),
 * and three of these six are the coach. So every picture says "Free" or says
 * it is the subscription, rather than leaving a reader to find out at the
 * paywall.
 *
 * **Picture for picture, Run's listing** (apps/mgk_run/design/store-shots), so
 * the two read as one suite: free, coach, free, coach, coach, free, opening on
 * "Free. No account." and closing on the year (here, the training) at a glance.
 *
 * **Every line says something the description in docs/store-listing.md
 * already says**, which was written from the code: logging, with the rest
 * timer running in the first picture; today's session and the plan on the
 * subscription; the coach, which reads the log; every session kept on the
 * phone.
 *
 * `screen` names a screen in lib/preview/main.dart, which
 * tool/capture_store_screens.mjs draws.
 */
export type Shot = {
  /** The screen, as the preview harness names it. */
  screen: string;
  tag: string;
  /** Two lines: the first in white, the second in silver. */
  lines: [string, string];
};

export const SHOTS: Shot[] = [
  {screen: 'session-resting', tag: 'Free', lines: ['Log every set.', 'Free. No account.']},
  {screen: 'track-planned', tag: 'Coach · Subscription', lines: ['Know what to lift', 'today.']},
  {screen: 'session-summary-pb', tag: 'Free', lines: ['Every session,', 'kept on your phone.']},
  {screen: 'plan-standing', tag: 'Coach · Subscription', lines: ['A plan built', 'around your week.']},
  {screen: 'coach-resumed', tag: 'AI coach · Subscription', lines: ['Ask the coach', 'about any lift.']},
  {screen: 'profile', tag: 'Free', lines: ['Your training,', 'at a glance.']},
];

/** The clock in the status bar. No screen here shows the time of day. */
export const TIME = '18:41';
