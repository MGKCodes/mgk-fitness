import 'package:flutter/foundation.dart';

/// A runner the **debug build** can enter the app as, so every state worth
/// looking at can be reached by tapping rather than by living through it.
///
/// These exist because the interesting states of a coaching app are all
/// *earned*: a mid-block week takes three weeks of running to reach, and a
/// second plan takes a season. Reviewing those screens meant either waiting or
/// hand-editing a database, so in practice they were reviewed by imagining
/// them.
///
/// **Not shipped.** Every entry point is behind [kDebugMode] and the seeded data
/// is built in memory — see `dev_seed.dart`. A release build has no persona, no
/// switcher, and reads the real Supabase-backed sources exactly as before.
///
/// They are deliberately **not** [PlanShape]s. A shape decides what is *in* a
/// week; a persona is a whole runner — a plan, a log behind it, and what the
/// coach remembers of them.
enum DevPersona {
  /// Signed up, never run. The empty states, which are the ones a real first
  /// user actually meets and the ones easiest to leave unlooked-at.
  fresh(label: 'New', blurb: 'Just signed up. No plan, no runs.'),

  /// Three weeks into a 16-week marathon build, so the arc has a past and a
  /// future either side of today.
  midBlock(label: 'Mid-block', blurb: 'Week 4 of a 16-week marathon build.'),

  /// A block started last week on top of a season of running. The plan is new;
  /// the runner is not.
  secondBlock(
    label: '2nd plan',
    blurb: 'A new block after a season of running.',
  ),

  /// One run a week, every week, going nowhere in particular — the runner
  /// ADR-0011 exists for. No race, no end date, nothing to taper into.
  rhythm(label: 'Rhythm', blurb: 'One run a week. No race, no end date.'),

  /// A block with a few days of nothing behind it, and a session due today.
  ///
  /// Every other persona runs on every past day of the current week, which made
  /// two states unreachable on a device: a prescribed run **still to do**, and
  /// the card that raises a missed one. Those are the states ADR-0017 is mostly
  /// about, so the app had no way to look at them.
  behind(
    label: 'Behind',
    blurb: 'Missed a few days. A run due today, not done.',
  );

  const DevPersona({required this.label, required this.blurb});

  /// Short name for a button.
  final String label;

  /// One line describing who this is, for the switcher.
  final String blurb;
}

/// The persona currently in force, or null for **real data** — the shipped
/// behaviour.
///
/// A top-level notifier rather than an inherited scope on purpose: it is read
/// at the root of the app (`lib/main.dart`) and written from two leaves (the
/// sign-in screen and Settings), and threading a controller through the widget
/// tree to serve a debug tool would put dev plumbing in the signature of every
/// screen between them.
///
/// Always null in a release build — see [setDevPersona].
final ValueNotifier<DevPersona?> devPersona = ValueNotifier<DevPersona?>(null);

/// Switches persona, or back to real data with null.
///
/// A **no-op in release**, so no call site can put the shipped app onto seeded
/// data even by mistake. The `kDebugMode` guard also lets the tree-shaker drop
/// the seeding code from a release bundle.
void setDevPersona(DevPersona? persona) {
  if (!kDebugMode) return;
  devPersona.value = persona;
}
