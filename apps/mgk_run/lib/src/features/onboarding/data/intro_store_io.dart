import '../domain/intro_store.dart';
import 'file_intro_store.dart';

/// Native (iOS) default: the marker persists to the filesystem.
IntroStore createIntroStore() => FileIntroStore();
