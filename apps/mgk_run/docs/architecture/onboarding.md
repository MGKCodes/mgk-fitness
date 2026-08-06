# Conversational onboarding

Slot-filling, not free chat. **Dart owns the slot state; the model never holds
it.** A conversational onboarding attached to a silent app reads as a trick — so
the coach persona defined here is the same one used across every prompt.

## Slots

**Which slots are required depends on the plan's shape**
([ADR-0011](../decisions/0011-a-plan-has-a-shape.md)). The shape has to be
settled before intake knows what it still needs. An earlier version of this line
listed the event date as required for everyone, and four layers inherited it as
a type constraint — which is why a runner who only wants to run their local
parkrun could not finish onboarding.

The shape now arrives **already filled**: it is asked as chips on the screen
immediately before the conversation
([ADR-0019](../decisions/0019-onboarding-is-two-moments.md)), because five
buttons cannot be answered wrong and a model is not needed to understand one.
The model can still change it — a runner who picked "I want to reach a distance"
and then says "actually it's Berlin in November" is proposing a `block`, and
`merge` takes it. What changed is that intake opens knowing what it is for,
rather than spending its first turn finding out.

| Shape | Required |
|---|---|
| **Block** | goal, event date, weekly volume, longest run, days per week, time trial |
| **Horizon** | goal, weekly volume, longest run, days per week, time trial — *no date* |
| **Rhythm** | the rhythm (what, which days), days per week — *no goal, no date* |
| **Log** | nothing |

**Optional everywhere:** injury history, availability constraints (time-of-day
windows), known unavailable weeks. The time trial is optional for a Rhythm — it
buys pace bands, which are worth having, but a runner without one is not blocked
from finishing.

Dart owns the required set, as it owns all slot state. A runner who is never
asked for a race date is not the model being lenient; it is Dart knowing there
is no race.

## Each turn

Send `schema + filled slots + conversation history`. Receive a reply plus
extracted slots. Terminate when required slots are full.

## Requirements

- **Batch questions.** "What are you training for, and when is it?" Target 4–5
  exchanges. A twelve-turn conversation is worse than a form.
- **React, don't just collect.** Acknowledging an answer before the next
  question is the difference between a coach and an interrogation.
- **Accept overshoot.** If a user answers three things in one paragraph, extract
  all three and skip ahead.
- **Confirmation screen at the end.** Editable. The plan is built on these
  numbers and extraction will sometimes be wrong.
- **Turn cap (6–7)** to prevent loops.
- **Sanity-check extractions in Dart, not in the prompt.** Date in the future,
  volume within plausible human bounds, time trial parseable. The model will
  happily accept 200 miles a week.

## Output

The result is a validated `runner_profiles` row (see
[data-model.md](data-model.md)). The model's extraction is a proposal; Dart
validates it before it becomes the profile the plan is built on — the same
"model proposes, validator disposes" rule as [plan generation](plan-generation.md).
