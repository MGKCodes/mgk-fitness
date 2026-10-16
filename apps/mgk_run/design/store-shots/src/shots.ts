/**
 * The six pictures, in the order the stores show them, and the words on each.
 *
 * **The tag says what costs money.** Both stores ask a listing to make clear
 * which of the things it shows need a purchase (App Review guideline 2.3.2),
 * and three of these six are the coach. So each of those three says it is the
 * subscription, rather than leaving a reader to find out at the paywall.
 *
 * **No picture says "Free".** Apple counts it as a price, which guideline
 * 2.3.7 keeps out of screenshots: Lift 2.0.0 was rejected for exactly these
 * words on 7 October 2026. The free pictures carry no tag; the description
 * may still say what is free.
 *
 * **Every line is checked against docs/app-store-listing.md, "What the app may
 * not claim".** Nothing here mentions elevation, heart rate, a watch, Health
 * or audio.
 */
export type Shot = {
  /** The screen, as test/plates/store.dart names it. */
  screen: string;
  /** Empty for a free picture: the space is kept, so every headline sits level. */
  tag: string;
  /** Two lines: the first in white, the second in silver. */
  lines: [string, string];
};

export const SHOTS: Shot[] = [
  {screen: '2-run', tag: '', lines: ['Track every run.', 'No account needed.']},
  {screen: '1-home', tag: 'Coach · Subscription', lines: ['Know what to run', 'today.']},
  {screen: '3-finished', tag: '', lines: ['Every run, kept', 'on your phone.']},
  {screen: '4-plan', tag: 'Coach · Subscription', lines: ['A real plan,', 'adjusted weekly.']},
  {screen: '5-coach', tag: 'AI coach · Subscription', lines: ['Ask the coach', 'about any run.']},
  {screen: '6-year', tag: '', lines: ['Your year,', 'at a glance.']},
];

/**
 * The clock in the status bar when nothing says otherwise. Home's greeting
 * follows the real clock when the screens are drawn, so `store.dart` writes
 * the time that agrees with it to `clock.json` and `render.sh` passes it in.
 */
export const TIME = '18:41';
