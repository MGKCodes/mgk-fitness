import '../domain/disclaimer_store.dart';

/// Web default (the preview harness only — Runio ships to iOS). There is no
/// `dart:io` here, so the acknowledgement lasts for the session: the gate still
/// shows, which is the fail-safe direction.
DisclaimerStore createDisclaimerStore() => InMemoryDisclaimerStore();
