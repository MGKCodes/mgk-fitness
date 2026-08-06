# Notices

Third-party material in this repository, and one unresolved question about it.

The code is [AGPL-3.0](LICENSE). This file covers everything that is not code.

---

## Inter (typeface)

`packages/mgk_ui/assets/fonts/Inter-*.ttf` — the Inter typeface by Rasmus
Andersson, under the SIL Open Font License 1.1. Licence text is committed
alongside the fonts at `packages/mgk_ui/assets/fonts/OFL.txt`.

---

## Exercise illustrations — **licensing unresolved**

> **This repository must stay private until this section is settled.**
> Nothing below asserts a licence for these files, deliberately: the honest
> answer is not yet known, and publishing a claim in either direction would be
> worse than publishing none.

`apps/mgk_lift/assets/exercises/` holds 522 WebP files — a start/end pair for
each of 261 movements, plus four generic equipment icons.

### What is established

These files are byte-identical to `assets/exercises/ai-generated/` in the
Liftio repository. They were produced there by `scripts/generate-exercise-
images.js`, which calls Replicate's FLUX **img2img** model
(`bxclib2/flux_img2img`) at `denoising: 0.45`, and which seeds every call with
an existing image:

```js
// Uses existing everkinetic images as pose references and redraws them in a
// consistent style.
const EVERKINETIC_DIR = path.join(ASSETS_DIR, 'everkinetic');
```

An image with no Everkinetic source is skipped rather than generated, so every
output has a one-to-one input. Liftio's commit `bc5c788` (2026-04-09) describes
the change in those terms and removes the Everkinetic credit in the same commit.

The source dataset is [everkinetic/data](https://github.com/everkinetic/data),
by Greg Priday, based on everkinetic.com, licensed
**[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)**. (Liftio's
former in-app credit said 3.0; the dataset's own `LICENSE.md` is 4.0.)

Of the 522 files: 504 are direct one-to-one derivatives, 14 are byte-identical
copies of 14 of those renamed during a later library consolidation, and 4
(`treadmill-1/2`, `bike-1/2`) have **no determined origin** — they match no
Everkinetic filename and no record of their creation survives.

### The question

CC BY-SA 4.0 §2(a)(4) says technical modifications — a format conversion, for
instance — never produce Adapted Material. An img2img pass that retains a
substantial part of the source is a different matter, and if these are Adapted
Material then §3(b) ShareAlike applies: the derivatives would have to be offered
under CC BY-SA 4.0 or a compatible licence, with attribution retained.

That does not sit with the claim currently published in Liftio's terms of
service §8.2 and on getliftio.com:

> Exercise illustrations used in the App are AI-generated and owned by MGKCodes
> Ltd. All rights reserved.

Both statements cannot be right. Resolving it is a decision for a person with
the relevant expertise, not something to be settled by reading the diff.

### Consequences to weigh

- The repository README describes AGPL-3.0 distribution as safe on the grounds
  of **sole copyright holding**. That reasoning covers the code; it does not
  automatically extend to these files.
- Whatever is decided here applies to the live Liftio app and to getliftio.com,
  not only to this repository.
- The Everkinetic originals are still on disk locally
  (`Liftio/assets/exercises/everkinetic/`, gitignored), so regenerating or
  reverting remains possible.
- There is no credits surface in `mgk_lift` yet — `onOpenSettings` is an unwired
  hook. If attribution is required, it needs somewhere to live.

<!-- Remove this section only when the question above has an answer, and
     replace it with whatever that answer requires. -->
