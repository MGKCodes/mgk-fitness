import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/intro_store.dart';

/// The real [IntroStore]: a marker file in the app support directory.
///
/// A file, not a new dependency and not a database table — the same call
/// `FileDisclaimerStore` makes, for the same reasons. The state is a single bit
/// that must survive relaunch, is never queried in bulk, and belongs to the
/// install rather than the account.
///
/// Imports `dart:io`, so this file must stay out of any import graph that is
/// compiled for web (the preview harness). Reach it through `createIntroStore()`
/// in `intro_store_factory.dart`, never directly.
class FileIntroStore implements IntroStore {
  FileIntroStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  /// Resolves the directory the marker lives in. Injectable so tests can point
  /// it at a temporary directory instead of a real platform path.
  final Future<Directory> Function() _directory;

  static const _fileName = 'intro_completed';

  Future<File> _markerFile() async =>
      File(p.join((await _directory()).path, _fileName));

  /// True only if the marker file is present. Any failure (no permission, no
  /// such directory, platform without a filesystem) reads as *not* done, so the
  /// intro runs again rather than being skipped.
  @override
  Future<bool> isDone() async {
    try {
      return (await _markerFile()).exists();
    } on Object {
      return false;
    }
  }

  /// What the runner said to call them, read back out of the marker.
  ///
  /// Any failure - no file, a file written by an older build that held only a
  /// timestamp, malformed JSON - reads as no name rather than throwing. The
  /// coach simply does not use one, which is exactly what it does for somebody
  /// who skipped the question.
  @override
  Future<String?> readName() async {
    final name = (await _read())['name'];
    return name is String && name.isNotEmpty ? name : null;
  }

  /// The marker's contents, or an empty map when there is nothing readable
  /// there — no file, a file written by an older build that held only a
  /// timestamp, malformed JSON. Never throws; an unreadable marker means no
  /// name, which is exactly what somebody who skipped the question has.
  Future<Map<String, dynamic>> _read() async {
    try {
      final file = await _markerFile();
      if (!await file.exists()) return <String, dynamic>{};
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on Object {
      return <String, dynamic>{};
    }
  }

  /// Writes the marker whole. JSON rather than the bare timestamp this used to
  /// hold, because it has a second thing to carry now.
  Future<void> _write(Map<String, dynamic> contents) async {
    try {
      final file = await _markerFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(contents));
    } on Object {
      // Nothing to recover: the intro is shown once more next launch, which is
      // the safe direction, and a lost name costs one edit in Settings.
    }
  }

  @override
  Future<void> markDone({String? name}) async {
    final existing = await _read();
    await _write(<String, dynamic>{
      'at': DateTime.now().toUtc().toIso8601String(),
      // A markDone that passes no name must not wipe one already recorded —
      // the intro is finished once per install, but `IntroScreen` calls this
      // with whatever it gathered, and skipping the name question is not the
      // same as asking for the stored one to be forgotten.
      if (name != null && name.isNotEmpty)
        'name': name
      else if (existing['name'] is String)
        'name': existing['name'],
    });
  }

  /// Rewrites just the name, leaving the marker itself alone.
  ///
  /// The `at` stamp is carried over rather than refreshed: it records when the
  /// intro happened, and renaming yourself in Settings two months later is not
  /// that. Where there is no marker to carry — Settings reached on an install
  /// whose file never wrote — one is stamped now, which is honest enough: they
  /// are demonstrably past the intro to be standing on this screen.
  @override
  Future<void> writeName(String? name) async {
    final existing = await _read();
    final trimmed = name?.trim();
    await _write(<String, dynamic>{
      'at': existing['at'] ?? DateTime.now().toUtc().toIso8601String(),
      if (trimmed != null && trimmed.isNotEmpty) 'name': trimmed,
    });
  }
}
