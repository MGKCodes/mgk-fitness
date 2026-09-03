# Notices

Third-party material in this repository, and one unresolved question about it.

The code is [AGPL-3.0](LICENSE), **except `web/`**. This file covers the
exceptions: one directory of our own code, one typeface, and 522 illustrations.

---

## The website - `web/`

**`web/` is not covered by this repository's AGPL licence.** It is proprietary,
all rights reserved, under its own [`web/LICENSE`](web/LICENSE). The source is
visible because the repository is; it is not offered for reuse.

Two reasons, and the second is the one people miss.

**Copyleft protects the app, not the brand.**
[ADR-0005](apps/mgk_run/docs/decisions/0005-license-agpl.md) chose AGPL so that
nobody can reskin the apps and ship a closed competitor. That argument is about
the software a runner uses. Marketing copy, brand assets and the pages that
carry them are the opposite case: strong copyleft on those would let a
competitor lawfully take the presentation of the product wholesale, which is
what AGPL was picked to prevent, applied to the wrong layer.

**AGPL section 13 is the network clause.** It requires that anyone who
interacts with the software *over a network* be offered its source. A website
is the literal case that clause was written for, so an AGPL `web/` would owe a
source offer to every visitor. That is a real obligation attached to no benefit.

The same split already exists across the studio: `getliftio.com` is a public
repository serving a live site under an all-rights-reserved licence. Visible,
not reusable. `web/` matches it.

**The generated legal pages under `web/public/` are a special case.** They are
rendered from `apps/mgk_run/docs/`, which is AGPL, and their text is a published
legal document rather than a creative work anybody would want to copy. Nothing
turns on their licence; they inherit `web/`'s because they live there.

---

## Inter (typeface)

`packages/mgk_ui/assets/fonts/Inter-*.ttf` — the Inter typeface by Rasmus
Andersson, under the SIL Open Font License 1.1. Licence text is committed
alongside the fonts at `packages/mgk_ui/assets/fonts/OFL.txt`.

---

## Exercise illustrations — CC BY-SA 4.0

**`apps/mgk_lift/assets/exercises/` is not covered by this repository's AGPL
licence.** Those 522 files are adaptations of CC BY-SA 4.0 material and are
offered under **[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)**
in turn, as ShareAlike requires.

> Original images © Everkinetic, by Greg Priday, licensed CC BY-SA 4.0.
> Adapted by redrawing in a consistent line style with an image model.
> Source: <https://github.com/everkinetic/data>
> Provided as-is, without warranties of any kind.

The same notice is carried in-app, on the credits screen reachable from
Settings → About. That screen is a licence condition rather than a courtesy;
`credits_screen.dart` says so at the top, and four tests assert its contents,
because the previous version of this app removed its attribution in a single
commit and nothing caught it.

`apps/mgk_lift/assets/exercises/LICENCE.md` restates this next to the files, so
anyone who copies the directory out of the repository takes the terms with it.

The reasoning behind all of this — what was weighed, what was rejected, and what
is still outstanding outside this repository — is
[ADR-0002](apps/mgk_lift/docs/decisions/0002-exercise-illustrations-are-cc-by-sa.md).

### Why, in short

522 WebP files — a start/end pair for each of 261 movements, plus four generic
equipment icons — of which 518 are one-to-one img2img derivatives of Everkinetic
originals. At 0.45 denoising the outputs keep the source pose and composition
essentially intact; comparing any pair makes that obvious at a glance. That is
Adapted Material, not an independent work, so §3(b) ShareAlike applies and the
adaptations carry the same licence forward.

The alternative — treating them as first-party and all-rights-reserved — was
what the predecessor app published, and it could not be reconciled with how the
files were actually made.

**Four files have no determined origin:** `treadmill-1/2` and `bike-1/2` match
no Everkinetic filename and no record of their creation survives. They are
covered by the same licence here, which is the conservative choice rather than
an established fact.

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

### Still outstanding elsewhere

This repository is settled. Two things outside it are not, and both still say
otherwise:

- **Liftio's terms of service §8.2**, and the same clause on **getliftio.com** —
  *"Exercise illustrations used in the App are AI-generated and owned by MGKCodes
  Ltd. All rights reserved."* That sentence describes the same files and needs
  to match this notice.
- **The Liftio app itself** has no credits surface; the Everkinetic block was
  removed from its Settings and About screens in `bc5c788` and never replaced.

Note also that this repository's README justifies AGPL-3.0 distribution on the
grounds of sole copyright holding. That reasoning is about the code and is
unaffected — these files are licensed separately and always were.
