import '../domain/intro_store.dart';

/// Web default (the preview harness only — this app ships to iOS). There is no
/// `dart:io` here, so the marker lasts for the session: the intro still shows,
/// which is the fail-safe direction.
IntroStore createIntroStore() => InMemoryIntroStore();
