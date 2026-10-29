# 0006 — Lift opens as Run does: a welcome, then the coach's lines, once

**Status:** Accepted (2026-10-29), for 2.0.1

## Context

Lift 2.0.0 had no first open. `main.dart` went straight to the shell, which
opens on Track, so a new lifter's first screen was the front page of an app
nobody had explained: three tabs, a round C in the corner, and nothing to say
what any of it was for, which half was paid, or where a session went once it
was logged. Track's empty state even promised a backup ("backs up when you are
back") that a new install, signed out, does not make.

Run solved the same problem in August (Run's
[ADR-0018](../../../mgk_run/docs/decisions/0018-onboarding-opens-as-a-conversation.md)
and [ADR-0019](../../../mgk_run/docs/decisions/0019-onboarding-is-two-moments.md)):
a welcome screen, then the coach's lines arriving one at a time as a
conversation, then a button, ending on a working app with nothing signed in.
The two apps are one product, and they arrived differently.

## Decision

**Lift opens the way Run does, in Lift's words.** Chosen by the owner on 29
October 2026 over two alternatives: three swipe pages, and hints laid on the
screens themselves.

- **A welcome.** *Every session, logged.* and *Set by set, with no signal, and
  a coach when you want one.*, then *Get started* and *I already have an
  account*.
- **The coach's lines**, one after another with the coach composing between
  them, then *Start training*. One line per tab in the bar's order, then the C,
  then that coaching and plans are a subscription and logging never is, then
  that the sessions stay on this phone until they sign in
  (`intro_script.dart`).
- **Both ways in end on the lines.** *I already have an account* goes through
  Lift's sign-in first: somebody arriving with an account made in Run has
  still never opened Lift.

What it does not take from Run's, and why:

- **No questions.** Run's asks a name and the permissions a run tracker needs.
  Lift needs no permission, and the name is the account's, asked once after an
  account is made (Run's
  [ADR-0047](../../../mgk_run/docs/decisions/0047-email-first-a-code-to-confirm-a-name-on-the-account.md)).
- **No tour.** Nothing points at a control. The lines say what each tab is
  for, and the app is learned by using it.

**Shown once per install**, recorded on the phone (`LocalIntroStore`,
`intro.seen` in SharedPreferences) when *Start training* is pressed.

**Never to somebody who used 2.0.0.** The first launch after the update finds
no record, which would read every existing lifter as new. So the gate in front
of the shell (`FirstRunGate`) lets through, and marks seen without a word,
anybody the phone already knows: a session restored at launch, or any training
on the phone. The welcome is shown only on positive evidence of a new install.

**It fails towards the app.** A record that cannot be read, a check that
throws, or either taking longer than three seconds opens the app rather than
the welcome. This is the opposite of Run's, whose intro carries the
permissions a tracker needs, so skipping it wrongly costs a run with no route.
Lift's carries nothing, so skipping it wrongly costs six lines, while a gate
that guessed the other way could stand a welcome in front of somebody's
training on every launch.

## Alternatives

- **Three swipe pages**, one per tab. The common pattern, and the one people
  have learned to swipe past without reading. A page describing a screen the
  reader has never seen explains nothing, and it is a different arrival from
  Run's for no reason the two apps have.
- **Hints in place**, a callout on each tab the first time it opens. Teaches
  at the moment of use, which is its strength, but it lays something over
  Track at the moment somebody is trying to start a session, and it never
  says the two things a first open most needs to: which half is paid, and that
  nothing is backed up until they sign in.

## Consequences

- The shell is not built until the lines are over, so nothing it starts at
  launch (a backup checkpoint, the plan, the store) runs for somebody still on
  the welcome. The launch curtain plays over whichever opens.
- A lifter who signs in on a second phone meets the lines again on that phone.
  They are the phone's, as in Run, and six lines read twice cost nothing.
- Track's first-session line promises a backup only to somebody signed in.
- `ScriptedLine` and `CoachAvatar` in `mgk_ui` draw the lines, matching Run's
  own `Said`. Run still draws its own; pointing it at the shared one is left
  for a change that redraws Run's arrival plates.
- If the record cannot be written, the welcome comes back on the next launch,
  until there is training on the phone or an account, which then let the lifter
  through for good.

## Cost function

Run's, for Run's reason: judge this by **whether lifters use the coach
unprompted afterwards.** The case for meeting the coach as a conversation,
rather than reading about it on a page, is that it teaches what the C is. If a
week later the coach is still something people have to be pointed at, the
lines did not teach it and were decoration.

## Disconfirming condition

Reverse it if new lifters who see it use the coach no more than lifters who
arrived on 2.0.0 with no first open at all. Then the lines are a delay in
front of Track, and the in-place hints this was chosen over are worth trying
in its place.
