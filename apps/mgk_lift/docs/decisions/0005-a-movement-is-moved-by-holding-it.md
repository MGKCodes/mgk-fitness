# 0005 — A movement is moved by holding it, where it sits

**Status:** Accepted (2026-10-29). Lift 2.0.1.

## Context

Lift 2.0.0 reordered a session's movements from a button at the foot of the
list, *Reorder movements*, which opened a sheet of one-line rows with a drag
handle on each and a Done button (board plate W20). It went in on 2026-09-29,
when the competitor research found every app it compared could reorder
mid-workout ("the bench is taken, so incline goes first") and Lift's recorder
had always been able to (`moveExercise`) with nothing on screen that reached
it.

**This reverses a decision that was taken on purpose.** The sheet's own
comment gave the reason: *"A sheet rather than drag handles on the cards: the
cards are tall, full of fields, and scroll under the lifter's thumb, which is
the wrong surface to start a long-press drag on."* It was never written down
anywhere else.

That reasoning was not wrong about the cards. An open card is a tap to focus
each number, a swipe to remove each set, a hold on each set's label for its
menu, and an icon row whose icons show their names when held. A card that
lifted from any of those would either fight them or win, and the likeliest
loser is a lifter resting a thumb on the weight while deciding what to type.

What it did not weigh is the cost of the detour. Matthew, after using it on
29 October, asked for reordering to be *"a hold drag and drop"*, not a press
to reorder and then a separate screen. Scrolling to the foot of the list,
opening a second screen, finding the movement again as a line of text and
pressing Done is four steps for a change that is one thought.

## Decision

**A movement is held and dragged where it sits, in the session's own list.**
No button, no sheet, no mode to enter first.

- **What is held is the card's picture and name**, the header strip above the
  sets, and nothing else on an open card. That strip has no hold gesture of
  its own (one tap, to the movement's stats), and it is where the name is,
  which is the thing being moved. The sets, their fields, their labels and the
  header's icons keep every gesture they had.
- **A folded movement is held anywhere on its line.** It is one line with one
  tap on it.
- **The platform's delayed start**: about half a second of stillness lifts the
  card, and a finger already moving before then scrolls the list as it always
  did. A session of one movement has nothing to hold.
- **An open card is carried folded to its header**, its sets put away until
  it lands, and then it opens where it landed. Flutter's reorderable list
  measures the dragged item once and scrolls itself while that whole
  rectangle reaches past an edge of the screen; at full height, a card held
  by its name halfway down the screen already does, and in a test the list
  scrolled on its own under a thumb that had not moved and carried the card
  to the end of the session. Folded, the list scrolls when the header reaches
  an edge, which is when a thumb means it to. `HoldToMove` folds first and
  lifts on the next frame.
- **The list never gets shorter under a held card.** Scrolled to the end, a
  fold that took 242 pixels away scrolled the list back by that much and the
  card went with it, from under the thumb. The same height is held as room
  at the foot of the list while the card is carried, and given back once it
  has opened again.
- **The lift** is the one the workout editor already had, a slight scale and a
  shadow, now shared by both screens. A light tick (`AppHaptics.tap`) when
  the hold takes; nothing on the drop.
- **The drop is written like any other change**: on screen at once, then
  `moveExercise` through the screen's write queue, so it is on disk before the
  next change and backed up with the session.
- **Screen readers** get Move up, Move down, Move to the start and Move to the
  end on every card, from Flutter's reorderable list, through the same write.

The workout editor keeps its handles, which drag at a touch, and **holding a
movement's name there lifts it too**, so the gesture learnt in a session works
in the editor.

## Consequences

- The sheet (`reorder_sheet.dart`), its button and plate W20 are gone. W20 is
  not reused; codes are pinned.
- Reordering is less discoverable than a labelled button: nothing on the card
  says it can be held. Accepted: it is what the person who asked expected to
  find, and hold-to-drag is how a phone moves things in a list.
- The cards it is carried past stay open, so passing one takes a thumb past
  half its height. Folding every card while one is carried would show the
  whole session at once, as some trackers do, but the list cannot take its
  other items changing size mid-drag without the places under the thumb
  moving; not done.
- One of the list's timings is matched rather than owned: the card opens
  300 ms after the drop, a little past the list's own 250 ms flight back. If
  Flutter lengthens that flight, the card starts to open in mid-air.
- Not tried on a device before merging. The arena logic (a set row has no hold
  listener at all, so it cannot lose a race to one), the fold and the room at
  the foot are pinned by widget tests, with the drawings checked on rendered
  plates; how the half-second feels with a sweaty thumb is not.
