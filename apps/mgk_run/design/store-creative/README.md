# Store creative assets

Run's App Store **creative assets**, which Apple added on 5 October 2026: the
**header** across the top of the product page, and the **search results**
picture shown in search instead of screenshots. Both appear on iOS and iPadOS
27 and later. Drawn in [Remotion](https://www.remotion.dev) from the app's own
screens, type and mark, with the store-shots kit (`../store-shots`).

**B was chosen on 9 October 2026**: the Slipstream header film, with A's
search picture. `render.sh` draws those two by default; the others are kept as
source and drawn only when named. Lift's header was then redrawn to match, as
its own launch looped (`apps/mgk_lift/design/store-creative`).

| Option | Files | The idea |
|---|---|---|
| **A · The name, then the app** | `header-name` + `search` | Header: `RUN »` at rest, as on Play's feature graphic. Search: "Track every run." over three screens |
| **B · Slipstream, looped** (chosen) | `header-slipstream` (film) + `search` | Header: the launch animation chosen on 1 October (`../launch-films`), same beats and curves, then at rest; it fades back to the start so the loop has no jump |
| **C · One picture** | `universal` | One 16:9 picture App Store Connect crops for both places |

## Rendering

From this folder, after `npm install`. The screens come from
`test/plates/store.dart` (see `../store-shots/README.md`), which writes
`store-assets/derived/screens/`. They are not in git, so a worktree has none
and `STORE` points at a folder that has them:

```
STORE=/c/Projects/mgk-fitness/store-assets/derived bash render.sh                      # all of them, to out/
STORE=... bash render.sh header-name search                                           # or the ones named
```

Each render is followed by `check.py`, which flattens a still to RGB (Apple
refuses alpha), checks the size against Apple's spec, and writes
`out/<name>-check.png` with the safe box ruled on. For a film it checks size,
frame rate and length and lays frames out on a sheet. A sheet shows frames,
not pace: watch the film for that.

## Where things are decided

- **Every word:** [`src/words.ts`](src/words.ts). Each line is copied from the
  listing (`docs/app-store-listing.md`), and its comment says from where. No
  price, no "Free", and nothing from the listing's "What the app may not claim".
- **The sizes and safe boxes:** [`src/spec.ts`](src/spec.ts). The sizes are
  Apple's specification; the safe boxes are the "Art Safe Area" layer of
  Apple's own Photoshop templates, which the specification does not state.
- **Uploading:** `python scripts/store/stores.py assets run` takes the files
  from `store-assets/derived/creative/` by name (`universal.png`,
  or `header.png`/`header.mp4` and `search.png`) and places them on the
  version open for changes. Copy only the chosen option's files there.

## Not checked here

Apple does not publish where the icon, name and Get button sit over the header.
App Store Connect's preview tool shows it once a file is in the Asset Library,
so check the chosen one there before the version goes for review. For the film,
set the poster frame (what shows before it plays) to the lockup at rest, not
the first frame's lone mark.

## Licence

Remotion is free for individuals and for companies of up to three people; a
larger company needs a company licence. Check that still holds before
rendering for a release.
