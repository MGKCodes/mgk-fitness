# History — none of this describes how the app behaves now

**Every document in this directory is out of date, deliberately, and none of
them is maintained.** They are kept because they record how something came to
be, which is a different job from saying how it is.

If you want to know what the app does today, none of these will tell you. Go to
[`../decisions/`](../decisions/) for why it is the way it is,
[`../architecture/`](../architecture/) for how the pieces fit, and
[`../app-store-1.0.0.md`](../app-store-1.0.0.md) for what is left to do.

## Why a directory and not a heading

These sat in `docs/` alongside the live documents, under a heading in the README
that said they were stale. That was not enough, and the argument against it is
the one this repository keeps making about everything else: **a warning that
depends on somebody reading a paragraph holds until the next person.**

`product-spec.md` is the case in point. It is titled *Runio*, marked
*Pre-alpha (design)*, and its decisions table promises HealthKit writes the app
has never performed — and for months it was named as the product's source of
truth. The listing copy was written against the code specifically to avoid it.
A document that misleading, sitting one line away from the live plan in the same
directory listing, is a trap with a note attached rather than a trap removed.

The path is now the warning. `docs/history/product-spec.md` cannot be mistaken
for current in a way `docs/product-spec.md` could.

## What is here

- **[release-1.0.0.md](release-1.0.0.md)** — the build that took Run from
  "records a run" to "somebody can hold it". Roughly twelve commits stale by the
  time it stopped being updated: its phases are ticked, but the account-removal
  work and everything after it is missing. It misleads about *history* rather
  than about how the system behaves, which is why it is the least dangerous of
  the three.
- **[app-store-1.0.0-record.md](app-store-1.0.0-record.md)** — the release
  plan as it stood on 1 October 2026, at 1,168 lines: the six gates and their
  reasoning, what builds 13, 25 and 26 each added, and the production audit of
  29 September. Frozen when the live plan was cut down to one table and one
  checklist. Its tick boxes carry no state, and its own header lists what was
  already wrong on the day.
- **[product-spec.md](product-spec.md)** — **the most misleading document this
  repository has ever had.** Read it for how the product was conceived, never
  for what it does.
- **[design-system.md](design-system.md)** — superseded by
  `packages/mgk_ui`, which is the design system now rather than a description of
  one. Kept because it argues for the greyscale language in a way the package
  cannot; the reasoning outlived the file.

## What is not here, and why

**[`../roadmap.md`](../roadmap.md) stayed put.** It reads like history and is
partly reconciled against the release plan, but it is still cited as the source
for pending work — the OpenRouter move is item 1, Lift's template design is item
3, and Knowledge entries point at both. A document other documents treat as live
is live, whatever its tone.

**`../../CHANGELOG.md` stayed put** as well. "What shipped, when" is a record
that keeps being added to, and a changelog belongs at the root of the thing it
describes.

## The rule

Nothing in here gets edited. If one of these turns out to be wrong about the
past, that is worth knowing and worth writing down — but it is fixed by a note
in the document that supersedes it, not by rewriting the record. A history
document that is kept current is not a history document; it is a second live
document, and this repository has already paid twice for having one of those.
