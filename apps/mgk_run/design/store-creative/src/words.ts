/**
 * Every word on the header and search results assets.
 *
 * **Copied, not written.** Each line is a phrase the App Store listing already
 * says (docs/app-store-listing.md), so an asset cannot promise more than the
 * description does:
 *
 * - "Record a run the moment you open the app." is the description's first
 *   sentence.
 * - "Track every run." and "Every run, kept on your phone." are the first and
 *   third store pictures' headlines (store-shots/src/shots.ts).
 *
 * **What may not be said.** No price and no "Free": Apple's guidance for these
 * assets rules out pricing, and the listing's own rule since 2026-10-07 is that
 * store pictures never name one. Nothing from "What the app may not claim" in
 * the listing doc (Health writes, watch import, elevation, heart rate, audio
 * cues, Strava). The screens are the three the store pictures already show
 * untagged: a run being recorded, the finished run and the year.
 */
export const WORDS = {
  suite: 'MGKFITNESS',
  name: 'RUN',
  /** The header's line. */
  line: 'Record a run the moment you open the app.',
  /** The search results asset: a headline, and a line under it in silver. */
  search: ['Track every run.', 'Every run, kept on your phone.'] as [string, string],
  /** The universal asset's two lines: white, then silver. */
  universal: ['Track', 'every run.'] as [string, string],
};

/**
 * The screens, as test/plates/store.dart names them. `hero` is the one a
 * single phone shows: a run in progress, the map above and the figures at the
 * foot, so a phone showing it keeps its foot.
 */
export const SCREENS = {
  hero: '2-run',
  finished: '3-finished',
  year: '6-year',
};

/** The status bar's clock when nothing says otherwise, as store-shots has it. */
export const TIME = '18:41';
