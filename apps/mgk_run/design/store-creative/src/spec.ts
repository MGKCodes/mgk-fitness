/**
 * The three canvases App Store Connect takes for creative assets, and the part
 * of each that every device shows.
 *
 * The sizes are Apple's specification (Creative assets specifications, App
 * Store Connect Help, read 2026-10-09). The safe boxes are not in the
 * specification: they are the "Art Safe Area" layer of Apple's own Photoshop
 * templates (creative_assets-*_template-static.psd, downloaded the same day),
 * read with psd-tools. Outside the box is atmosphere: some devices and
 * orientations crop it away, so nothing that has to be read goes there.
 *
 * - **header**: the top of the product page, 21:9. A still or a 15 to 30 s
 *   muted loop.
 * - **search**: the search results asset, 3:2, drawn at the largest size.
 * - **universal**: one 16:9 PNG that fills both placements, cropped for each.
 *   Its box is the smallest of the three, because it has to survive both crops.
 */
export type Box = {x: number; y: number; w: number; h: number};
export type Canvas = {w: number; h: number; safe: Box};

export const SPEC = {
  header: {w: 3840, h: 1646, safe: {x: 1097, y: 493, w: 1646, h: 661}},
  search: {w: 3840, h: 2560, safe: {x: 836, y: 765, w: 2168, h: 1030}},
  universal: {w: 5244, h: 2950, safe: {x: 1921, y: 660, w: 1402, h: 962}},
} satisfies Record<string, Canvas>;

/** Apple takes exactly 30 or 60. Fifteen seconds is the shortest every video spec accepts. */
export const FPS = 30;
export const FILM_SECONDS = 15;

/** The app's colours that the kit does not carry (packages/mgk_ui AppColors). */
export const APP = {
  textSecondary: '#9CA3AF',
  success: '#16A34A',
};
