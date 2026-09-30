import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/backup_consent.dart';
import 'package:mgk_auth/mgk_auth.dart';

/// The real [BackupConsentStore]: a small file in the app support directory.
///
/// A file rather than a table, matching `FileUnitCache` — one short value, never
/// queried in bulk, needs only to survive relaunch. It must also be readable
/// before the database is open, because the first thing a backup asks is
/// whether it is allowed to exist.
///
/// **An unreadable file is a refusal, not a default.** Every failure path here
/// returns [BackupConsent.unknown], which behaves as no. The alternative — a
/// missing file quietly meaning yes — would upload special-category data on the
/// strength of an I/O error, and the runner would have no way to know it had
/// happened.
///
/// Stores the enum's own name rather than a boolean so that "declined" and
/// "never asked" stay distinguishable on disk. Collapsing them would make the
/// app re-ask someone who already said no.
///
/// **And who said it.** The file used to hold the bare word, which made a yes
/// the phone's rather than the runner's: the next account to sign in inherited
/// it, and so did a phone restored from an OS backup. It now records the
/// account that answered, and [read] returns the answer through [consentFor],
/// so a yes only ever authorises uploads for the account that gave it, and only
/// while that account owns the training on the phone. A file written by an
/// older build holds the bare word and no account; its yes reads as unknown
/// and is asked again, and its no stays a no.
///
/// Imports `dart:io`, so it stays out of any web import graph — reach it
/// through `createBackupConsentStore()`.
class FileBackupConsent implements BackupConsentStore {
  FileBackupConsent({
    Future<Directory> Function()? directory,
    String? Function()? signedInUserId,
    LocalDataOwnerStore? owner,
  }) : _directory = directory ?? getApplicationSupportDirectory,
       _signedIn = signedInUserId ?? _supabaseUserId,
       _owner = owner;

  final Future<Directory> Function() _directory;

  /// Who is signed in right now. Asked per read, because the answer changes
  /// underneath a store that lives as long as the app does.
  final String? Function() _signedIn;

  /// Whose training is on the phone. Null reads every phone as unclaimed,
  /// which is what a store with nobody to ask should assume.
  final LocalDataOwnerStore? _owner;

  static const _fileName = 'backup_consent';

  /// The session's user, or null — including when Supabase was never
  /// initialised, which is a build with no backend rather than an error.
  static String? _supabaseUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } on Object {
      return null;
    }
  }

  Future<File> _file() async =>
      File(p.join((await _directory()).path, _fileName));

  @override
  Future<BackupConsent> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return BackupConsent.unknown;
      final text = (await file.readAsString()).trim();
      final String word;
      final String? givenBy;
      if (text.startsWith('{')) {
        final decoded = jsonDecode(text);
        if (decoded is! Map<String, dynamic>) return BackupConsent.unknown;
        final answer = decoded['answer'];
        final by = decoded['given_by'];
        word = answer is String ? answer : '';
        givenBy = by is String && by.isNotEmpty ? by : null;
      } else {
        // An older build's file: the bare word, nobody attached.
        word = text;
        givenBy = null;
      }
      final answer = BackupConsent.values.firstWhere(
        (c) => c.name == word,
        orElse: () => BackupConsent.unknown,
      );
      return consentFor(
        answer,
        givenBy: givenBy,
        signedIn: _signedIn(),
        owner: await _owner?.read(),
      );
    } on Object {
      return BackupConsent.unknown;
    }
  }

  /// A failed write leaves the previous answer standing. That is the safe
  /// direction in both cases: a granted consent that fails to persist reads
  /// back as unknown and asks again, and a withdrawal that fails to persist is
  /// re-applied the next time the runner opens Settings and sees the switch
  /// still on.
  @override
  Future<void> write(BackupConsent consent) async {
    try {
      await (await _file()).writeAsString(
        jsonEncode(<String, String?>{
          'answer': consent.name,
          'given_by': _signedIn(),
        }),
        flush: true,
      );
    } on Object {
      // Deliberate: see above.
    }
  }
}
