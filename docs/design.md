# Design principles

What holds a screen together in Lift and Run, and why.

Written 2026-08-07, after looking at six screens that had been built without
anyone seeing them render. Every rule below is here because it was broken, and
each one names where — a principle with no failure behind it is decoration.

The design language itself (greyscale, Inter, the photography, the motion
vocabulary) lives in `packages/mgk_ui` and in ADR-0009. This is the layer above:
how a screen is put together once it has those.

---

## 1. A container sizes to its content

Fixed heights and centred columns produce a void when the content is short and
a clip when it is long. Neither failure is visible while you are writing the
widget with one item in it.

**Broken in two places.** Plan's live block put its session list in a centred
column, which marooned two sessions in the middle of the screen with seven
hundred pixels of nothing beneath them — and would have pushed a fifth off the
bottom. The coach sheets fix themselves at 70% of screen height, so two
suggestions leave the same void above the input.

Centring is right for a fixed lump of copy: the paywall offer, an empty state, a
message. It is wrong for anything whose length depends on data.

> A list is top-aligned and scrolls. A sheet is as tall as what is in it, up to
> a ceiling. If you cannot say how tall the content is, do not name a height.

## 2. One slot, one shape

Two states that occupy the same position render at the same width, with the same
anatomy, in the same order.

**Broken on Track.** `Next up` spanned the full width and `Where you were`
stopped three-quarters across, because `GlassSurface` sizes to its content and
one had more text than the other. Same screen, same slot, two shapes — which
reads as a layout bug even though each card is individually fine.

> If two widgets can appear in one place, they are one component with two
> states, or they are wrong.

## 3. Say a thing once, at the level that says it best

When two elements carry the same fact, the more specific one wins and the other
goes.

**Broken on Track, twice.** "Session in progress / You have a session open, pick
up where you left off" sat directly above a card saying **Push · 2 sets in ·
started yesterday**. The vague version was larger and on top. In the planned
state it was worse: the headline said "Start a session and log it set by set",
which is free-tier copy, above a card naming that day's prescribed session.

The headline now reads the same state the card does, and its supporting line is
dropped whenever the card already carries it.

> A headline that could be printed on any screen is not a headline.

## 4. The same data renders the same way everywhere

One rendering per kind of thing, defined once.

**Broken across three surfaces.** A planned movement appeared as
`Name — 3 × 5 @ 85 kg` on the review screen, and as a middle-dot run-on
(`Name 3 × 5 @ 85 kg · Name 3 × 8 @ 27.5 kg · …`) on Track and Plan, where it
wrapped into a dense block nobody reads standing up holding a phone. The better
rendering already existed; it just had not been reused.

`PlannedMovement.render(unit)` is the single definition. If a surface needs a
different one, that is a signal the data is different, not the presentation.

> Two renderings of one thing is a bug with a delay on it.

## 5. Repetition is a signal to collapse

If a list produces near-identical rows, the unit is wrong.

**Broken on the review screen.** An eight-week block rendered eight week cards,
six of which carried only a phase and an intent — and therefore read as the same
card printed six times, each repeating that it would be written closer to the
time. It made a plan look machine-made on the one screen that has to look
considered.

They collapsed into a single row: `Weeks 3 to 8 — written a week at a time…
Weeks 4 and 8 back off`. The information worth having in advance (where the
deloads fall) survives; the repetition does not.

> Six identical cards is one card with a range in it.

## 6. Absent beats zero

Nothing to show shows nothing, not noughts.

**Held on Track.** Its one number — sessions this week, since the 2026-09-30
redesign — is omitted entirely on an empty log rather than rendering `0`, and the
three starting points take the space instead. A nought on day one reads as a
scoreboard somebody is already losing, which is the opposite of what the screen
is for. (It was a strip of three — this week, week streak, last session — and
the rule held for all three.) Once there is any history, none this week is a
fact, and is shown.

> An empty state is a sentence, not a zeroed instance of the full state.

## 7. Null is a value, not a gap

A missing number is often a real answer and should render as one.

**Held throughout the plan.** A movement the coach could not derive a weight for
shows `3 × 12`, not `3 × 12 @ 0 kg` and not a blank where a number should be.
That is how most accessory work is actually programmed, and the plan says so
plainly — "8 of 12 movements have a weight. The rest are ones your coach has not
seen you lift, so it is not guessing at a number."

This one matters more than it looks: the whole load rule (see
[architecture.md](architecture.md#planning)) produces nulls by design, and a UI
that treated them as missing data would have made the honest behaviour look
broken.

> If the absence is meaningful, say what it means. Do not draw a hole.

## 8. The photograph is the brand

With no accent colour, the photography carries the identity (ADR-0009). Content
sits **on** it with a scrim, never in a panel floating above it, and the scrim is
chosen per screen: light where a headline sits, heavy under a price. A screen
that leads with its photograph — Lift's Sign in — may carry it at strength
over the top of the screen; everywhere else it is the faint texture. Lift's
Track was the other such screen until 1 October 2026, when it was rebuilt as a
front page with the photograph as texture
([ADR-0042](../apps/mgk_run/docs/decisions/0042-a-screen-that-leads-with-its-photograph.md)).

> A flat dark screen where a photograph should be is throwing away the only
> colour decision this product makes.

## 9. A rule that lives in one screen is a rule the next screen will miss

Every principle above is a claim about how something should look. This one is
about where the claim has to live, and it is the only reason the rest hold.

**Broken three times in one afternoon, all the same way: the better version was
already in the repo and the newer code did not use it.** The coach screen had
worked out that a conversation must grow upward from the composer, and said so
in a comment explaining that a plain `ListView` top-anchors and `Spacer` cannot
help inside one. The plan intake, written afterwards, used a plain `ListView`
and put a two-line opener above fourteen hundred pixels of nothing — principle
1, in a screen whose fix was already written down ten files away. The same day,
one bubble widget existed twice, and the two coach sheets had drifted to two max
heights and two label conventions within a day of each other.

None of that was carelessness. Prose in a comment is advice, and advice is
followed by whoever reads it. So the anchoring behaviour became
`ConversationView`, the bubble became `ConversationBubble`, and the sheet shell
became `CoachSheet` — and the first two are pinned by tests that fail if a lone
turn drifts back to the top or a bubble reaches both margins.

The test matters as much as the extraction. Both faults still compile, still
pass `analyze`, and still look correct on a full screen of content; they are
only visible on the first turn, which is the state nobody re-checks.

> If a principle can only be obeyed by remembering it, it is not a principle
> yet. Make it a component, and pin the part of it that a screenshot would
> catch but a compiler would not.

## 10. The loudest thing on a screen is what the screen is for

There is no accent colour (ADR-0009), so emphasis is a fixed budget: a silver
fill, and one status red reserved for danger. Spending either is a claim about
what somebody should do next.

**Broken on the coach-memory screen**, which exists so a lifter can read what
the coach has written about their body — and drew `Forget everything` as a
full-width silver `PrimaryButton`, making the destructive action the brightest
thing on the page and the memory itself second. Every other `PrimaryButton` in
the suite is the action you came for: *Start a session*, *Build a plan*,
*Continue*. This was the one that was not.

The first fix overcorrected: an outlined button with a red border and red text
pulled the eye *harder* than the silver fill it replaced, because on a grey
screen a saturated ring is the strongest mark available. `DestructiveButton`
settled on danger for the label and a neutral border — enough to say "this one
is different", not enough to say "do this".

Related: Run's delete-account screen had reached the same conclusion months
earlier and expressed it as six inline style properties, because the theme had
no `outlinedButtonTheme` to inherit from. Principle 9 again — it is now a
component, and both apps use it.

> Before reaching for the primary button, ask what the screen is for. If the
> answer is "reading this", nothing on it should be shouting.

---

## How to check

The preview harness enumerates every screen and is the checklist:

    flutter run -d emulator-5554 --dart-define=screen=plan-active \
      -t lib/preview/main.dart
    adb exec-out screencap -p > shot.png

**Run it on the device, not the browser.** The web build renders blur, fonts,
safe areas and scroll physics differently, and the harness only became
device-addressable on 2026-08-07 — before that `--dart-define` did not exist and
the screen name came from the URL, so Android always fell back to the index.

**A screen missing from the harness is a screen nobody has looked at.** The two
coach sheets and the plan intake conversation were absent from it, which is
exactly why they went unreviewed longest.

**And a harness can lie about what it shows.** Two faults in the tool itself,
both found on 2026-08-08 by someone asking why a screen had no back arrow:

- It mounted a named screen as `home`, so `Navigator.canPop()` was false and
  `AppBar` never drew its back button. Every screen addressed by name looked
  like a dead end. Run's harness had solved this months earlier and said so in
  a comment; Lift's, written later, had not — and the audit in
  [navigation.md](navigation.md) was run through Lift's. Both now push by
  default.
- The index was fixed at one screenful with `NeverScrollableScrollPhysics`, to
  keep tap coordinates stable for `tool/capture_screens.ps1`. It listed 35
  screens and could open 24. The eleven below the fold — the coach, coach memory
  in three states, sign-in, credits — were unreachable by hand.

The pattern is the same one principle 9 describes, one level up: **the thing you
audit with needs auditing too.** A tool that cannot show a class of fault will
report that class as absent, and it will be believed, because it is the tool.

**Check which app is actually on screen before believing a screenshot.**
`flutter run` does not reliably foreground its app after a rebuild, and a
screenshot carries no label. Reviewing Run began with a capture that was still
showing Lift, and the capture after that was an ANR dialog — `mgk_lift isn't
responding` — drawn over the top of everything.

Guard on the focused *window*, not the resumed activity:

    adb shell dumpsys window | grep mCurrentFocus

`topResumedActivity` names the app beneath a system dialog, so it happily
reports the right package while a crash box fills the screen. `mCurrentFocus`
names the dialog. And leaving several `flutter run` sessions attached across a
session is what produced the ANR in the first place — stop the previous one
before starting the next.

And the thing worth saying plainly: `flutter analyze` and widget tests prove a
tree builds and the right strings are in it. They proved all six of these
screens "correct" while five of them had layout faults. **They cannot see a
screen.** Look at it.
