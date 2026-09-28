# 0003 — The exercise illustrations are CC BY-SA 4.0, not first-party

**Status:** Accepted (2026-08-07, in `748a80d`)

*Recorded 2026-09-03.* The decision was taken and implemented on 2026-08-07 —
the licence files, the carve-out and the credits screen all shipped that day —
but no ADR was written. The obligation was recorded in `NOTICE.md` and in
`assets/exercises/LICENCE.md`; the *reasoning* was not, which is what this
fixes. An undocumented decision is one that gets "tidied up" by somebody who
does not know it is load-bearing, and this one was tidied away once already.

## Context

`apps/mgk_lift/assets/exercises/` holds **522 WebP files** — a start/end pair
for each of 261 movements, plus four generic equipment icons. They are how the
app draws every exercise.

**The predecessor app published them as first-party work.** Liftio's terms of
service §8.2 say: *"Exercise illustrations used in the App are AI-generated and
owned by MGKCodes Ltd. All rights reserved."* That sentence was written in good
faith — "AI-generated" sounds like it settles the question of authorship.

It does not, and the repository can prove it does not, because the generator is
in version control. Liftio's `scripts/generate-exercise-images.js` calls
Replicate's `bxclib2/flux_img2img` at `denoising: 0.45`, seeding every call from
an existing image:

```js
// Uses existing everkinetic images as pose references and redraws them in a
// consistent style.
const EVERKINETIC_DIR = path.join(ASSETS_DIR, 'everkinetic');
```

An image with no Everkinetic source is **skipped rather than generated**, so
every output has a one-to-one input. This is not a model trained on a corpus and
asked for a squat; it is a specific source image, redrawn.

Three facts decide it:

1. **The source is licensed.** [everkinetic/data](https://github.com/everkinetic/data),
   by Greg Priday, based on everkinetic.com, under
   **[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)**. (Liftio's
   former in-app credit said 3.0; the dataset's own `LICENSE.md` says 4.0.)
2. **0.45 denoising preserves the work.** At that strength the outputs keep the
   source pose and composition essentially intact — comparing any pair makes it
   obvious at a glance. That is **Adapted Material** under the licence, not an
   independent work, so §3(b) ShareAlike applies.
3. **The credit was removed in the same commit that created the derivatives.**
   Liftio's `bc5c788` (2026-04-09) added the generator *and* deleted the
   Everkinetic attribution from Settings and About. Nothing malicious — the two
   changes simply were not connected to each other by anyone.

Of the 522: **504** are direct one-to-one derivatives, **14** are byte-identical
copies of 14 of those, renamed during a later library consolidation, and **4**
(`treadmill-1/2`, `bike-1/2`) match no Everkinetic filename and have **no
determined origin** — no record of their creation survives.

The repository is AGPL-3.0 ([Run ADR-0005](../../../mgk_run/docs/decisions/0005-license-agpl.md)),
justified on MGKCodes being the sole copyright holder. **That reasoning is about
the code and does not reach these files**, because on the facts above we are not
their sole author.

## Decision

**Treat the illustrations as Adapted Material and carry CC BY-SA 4.0 forward.**

1. **`apps/mgk_lift/assets/exercises/` is carved out of the repository's AGPL
   licence** and offered under CC BY-SA 4.0 in turn, as ShareAlike requires.
2. **The attribution lives in three places, each doing a different job:**
   - [`NOTICE.md`](../../../../NOTICE.md) at the repository root — the full
     account, including the four files that could not be traced.
   - [`assets/exercises/LICENCE.md`](../../assets/exercises/LICENCE.md) — sits
     beside the files, so the terms travel with the directory if anyone copies
     it out.
   - `credits_screen.dart`, reachable from Settings → About — the in-app notice.
     §3(a)(1) requires the creator, a copyright notice, a licence notice, the
     disclaimer, a URI to the material and a statement that it was modified;
     §3(a)(2) allows satisfying that "in any reasonable manner based on the
     medium", and for an app the settled convention is a credits screen.
3. **The four untraced files carry the same licence.** That is the conservative
   choice rather than an established fact, and it is written down as such.
4. **Attribution is tested, not trusted.** Four widget tests in
   `test/settings/settings_screen_test.dart` assert the screen is reachable,
   names Greg Priday and Everkinetic, carries the licence and the disclaimer and
   both URIs, says the images were **modified**, and states that the adaptations
   are offered under CC BY-SA in turn. The last is the line that contradicts
   "all rights reserved" — a credit alone would not have been enough.

### The alternative, and why not

**Keep "AI-generated and owned by MGKCodes Ltd. All rights reserved."** This is
what the predecessor published and it would have cost nothing to continue. It
was rejected because it cannot be reconciled with how the files were made, and
the evidence is in our own repository: the generator script names its input
directory in a comment. A claim that the code contradicts is not a claim worth
defending.

**Commission or draw 261 movements as genuinely first-party art** was weighed
and deferred rather than ruled out. CC BY-SA is not an onerous licence for an
app that has no interest in preventing anyone from reusing exercise diagrams,
and the cost of original art for 261 movements is real. If that is ever done,
this ADR is superseded and the carve-out goes with it.

## Consequences

- **The repository is no longer uniformly AGPL.** Anyone reusing it has to read
  `NOTICE.md` first. This is the price of the carve-out and it is worth paying.
- **ShareAlike is viral for these files.** A downstream adaptation of them must
  also be CC BY-SA 4.0 or compatible. It does not touch the rest of the code.
- **Commercial use is unaffected.** CC BY-SA permits it, so nothing here
  constrains the subscription
  ([Run ADR-0030](../../../mgk_run/docs/decisions/0030-the-coach-is-the-paid-half.md)).
- **Deleting a line from the credits screen is a licence breach**, not a tidy-up.
  The file says so at the top and four tests pin it. This is the exact failure
  that produced the situation — it happened once, in one commit, and nothing
  caught it.
- **Display filtering is not an edit.** The app inverts these images at render
  time for the dark theme; the files on disk are untouched, and nothing in the
  licence restricts how they are shown.
- **Two things outside this repository still say otherwise, and shipping 2.0.0
  fixes only one of them:**
  - **Liftio's terms of service §8.2, and the same clause on `getliftio.com`**,
    still claim sole ownership of these files. They describe the same images and
    need to be changed to match. Not blocked by anything here.
  - **The shipped Liftio app has no credits surface at all** — removed in
    `bc5c788` and never replaced. Lift 2.0.0 replaces that binary and restores
    it, so this one closes on release ([ADR-0001](0001-liftio-is-replaced-not-relaunched.md)).
- **Run is unaffected in code and bound in licensing.** `apps/mgk_run` ships
  none of these assets, but `NOTICE.md` is a repository-root document covering
  the whole suite, so the carve-out is stated once for both apps.
