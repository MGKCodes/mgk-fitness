/**
 * Where things are, once they exist.
 *
 * The page is written before either app is in a store and before the
 * repository is public, so it has to say "soon" about both without a link
 * that goes nowhere. Each thing here is shown as coming until it is given an
 * address, and as a link from then on. Going live is an edit to this file and
 * nothing else.
 */

/** Each app's page in each store. Left out until the app is on sale there. */
export const stores: Record<"run" | "lift", { apple?: string; google?: string }> = {
  run: {},
  lift: {},
};

/**
 * The suite's accounts elsewhere, which sit in the bar as their marks. One
 * with no address is shown greyed and is not a link. Give it a `url` and it is
 * one. One that is not going to happen is taken out of the list, and is then
 * not shown at all.
 */
export const social: { name: "Instagram" | "TikTok"; url?: string }[] = [
  { name: "Instagram" },
  { name: "TikTok" },
];

/**
 * The source. Run and Lift are AGPL and live in one repository, with the
 * backend they share.
 *
 * **`open` is false because the repository is private today**, and a link to a
 * private repository is a 404 for everybody but its owner. Making it public
 * waits on its history being cleared of secrets (`apps/mgk_run/docs/roadmap.md`).
 * Set this to true the day it is public, not before.
 */
export const source = {
  open: false,
  repository: "https://github.com/MGKCodes/mgk-fitness",
  run: "https://github.com/MGKCodes/mgk-fitness/tree/main/apps/mgk_run",
  lift: "https://github.com/MGKCodes/mgk-fitness/tree/main/apps/mgk_lift",
  contributing: "https://github.com/MGKCodes/mgk-fitness/blob/main/CONTRIBUTING.md",
};
