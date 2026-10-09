# Store creative assets

Lift's App Store **creative assets**, which Apple added on 5 October 2026: the
**header** across the top of the product page, and the **search results**
picture shown in search instead of screenshots. Both appear on iOS and iPadOS
27 and later. Drawn in [Remotion](https://www.remotion.dev) from the app's own
screens, type and mark, with the store-shots kit (`../store-shots`).

**Proposed on 9 October 2026, to match Run's choice:** `header-launch`, the
launch looped as a header film, with A's search picture. Run's B (Slipstream
looped) was chosen that day, and Lift's header follows it with Lift's own
launch rather than the rest clock. Once it is confirmed, write it here and make
`render.sh` draw only those two by default.

| Option | Files | The idea |
|---|---|---|
| **A · The name, then the app** | `header-name` + `search` | Header: the launch's last frame, the mark above LIFT. Search: "Log every set." over three screens |
| **B · Between sets** | `header-between-sets` (film) + `search` | Header: the rest dock at poster size, running in real time from 0:10 to REST OVER and on past zero, as the app does |
| **C · One picture** | `universal` | One 16:9 picture App Store Connect crops for both places |
| **The launch, looped** (proposed) | `header-launch` (film) + `search` | Header: lib/src/core/launch/launch_curtain.dart, beat for beat. The mark dips, drives up and lifts LIFT into place, then rests; it fades back to the start so the loop has no jump |

## Rendering

From this folder, after `npm install`. The screens come from
`tool/capture_store_screens.mjs` (see `../store-shots/README.md`); they are not
in git, so a worktree has none and `STORE` points at a checkout that does:

```
STORE=/c/Projects/mgk-fitness/apps/mgk_lift/screenshots/store bash render.sh          # all of them, to out/
STORE=... bash render.sh header-name search                                           # or the ones named
```

Each render is followed by `check.py`, which flattens a still to RGB (Apple
refuses alpha), checks the size against Apple's spec, and writes
`out/<name>-check.png` with the safe box ruled on. For a film it checks size,
frame rate and length and lays frames out on a sheet. A sheet shows frames,
not pace: watch the film for that.

## Where things are decided

- **Every word:** [`src/words.ts`](src/words.ts). Each line is copied from the
  listing, and its comment says from where. No price and no "Free".
- **The sizes and safe boxes:** [`src/spec.ts`](src/spec.ts). The sizes are
  Apple's specification; the safe boxes are the "Art Safe Area" layer of
  Apple's own Photoshop templates, which the specification does not state.
- **Uploading:** `python scripts/store/stores.py assets lift` takes the files
  from `apps/mgk_lift/screenshots/store/creative/` by name (`universal.png`,
  or `header.png`/`header.mp4` and `search.png`) and places them on the
  version open for changes. Copy only the chosen option's files there.

## Not checked here

Apple does not publish where the icon, name and Get button sit over the header.
App Store Connect's preview tool shows it once a file is in the Asset Library,
so check the chosen one there before the version goes for review.

## Licence

Remotion is free for individuals and for companies of up to three people; a
larger company needs a company licence. Check that still holds before
rendering for a release.
