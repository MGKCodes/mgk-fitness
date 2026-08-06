import '../domain/disclaimer_store.dart';
import 'file_disclaimer_store.dart';

/// Native (iOS) default: the acknowledgement persists to the filesystem.
DisclaimerStore createDisclaimerStore() => FileDisclaimerStore();
