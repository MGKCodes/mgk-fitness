import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/settings/data/file_backup_consent.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';
import 'package:mgk_auth/mgk_auth.dart';

/// **A yes to backing up was the phone's, not the runner's.**
///
/// The answer was one word in one file for the whole device. Sign out, let
/// somebody else sign in, and their account was backed up on the strength of a
/// yes they never gave -- with the launch backfill pushing the first runner's
/// runs and GPS traces into it. A phone restored from an iCloud or Google
/// backup brought the same word back.
///
/// Now the file records who answered, and a yes only authorises uploads for
/// that account, and only while the phone's training is theirs.
void main() {
  late Directory dir;
  String? signedIn;
  late InMemoryLocalDataOwner owner;

  FileBackupConsent store() => FileBackupConsent(
    directory: () async => dir,
    signedInUserId: () => signedIn,
    owner: owner,
  );

  File file() => File('${dir.path}${Platform.pathSeparator}backup_consent');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('consent');
    signedIn = 'alex';
    owner = InMemoryLocalDataOwner('alex');
  });

  tearDown(() => dir.delete(recursive: true));

  test('the account that said yes is backed up', () async {
    await store().write(BackupConsent.granted);
    expect(await store().read(), BackupConsent.granted);
  });

  test('a different account signing in inherits nothing', () async {
    await store().write(BackupConsent.granted);

    signedIn = 'sam';
    owner = InMemoryLocalDataOwner('sam');

    expect(
      await store().read(),
      BackupConsent.unknown,
      reason: 'sam never said yes; asked, not assumed',
    );
  });

  test('signed out, a yes authorises nothing', () async {
    await store().write(BackupConsent.granted);
    signedIn = null;
    expect(await store().read(), BackupConsent.unknown);
  });

  test('and it comes back when the account that gave it does', () async {
    await store().write(BackupConsent.granted);
    signedIn = null;
    expect(await store().read(), BackupConsent.unknown);
    signedIn = 'alex';
    expect(await store().read(), BackupConsent.granted);
  });

  test('a yes stops applying while the training belongs to someone else', () {
    // Sam said yes on this phone once. The training on it now is Alex's, and
    // Sam has just signed back in: until somebody decides whose it is, none
    // of it may go to Sam's account.
    expect(
      consentFor(
        BackupConsent.granted,
        givenBy: 'sam',
        signedIn: 'sam',
        owner: 'alex',
      ),
      BackupConsent.unknown,
    );
    // A phone nobody has claimed yet is claimed by whoever signs in, so it
    // does not block them.
    expect(
      consentFor(
        BackupConsent.granted,
        givenBy: 'sam',
        signedIn: 'sam',
        owner: null,
      ),
      BackupConsent.granted,
    );
  });

  test('the owner is read from the store the phone keeps', () async {
    await store().write(BackupConsent.granted);
    await owner.write('someone-else');
    expect(await store().read(), BackupConsent.unknown);
  });

  test('a no is a no for everybody', () async {
    // It can never send anything, so there is nobody it can hurt, and the
    // runner who declined signed out is almost always the one who signs in.
    signedIn = null;
    await store().write(BackupConsent.declined);

    for (final who in <String?>[null, 'alex', 'sam']) {
      signedIn = who;
      expect(await store().read(), BackupConsent.declined, reason: '$who');
    }
  });

  group('a file written before answers had owners', () {
    test('its yes is asked again, because nobody knows whose it was', () async {
      await file().writeAsString('granted');
      expect(await store().read(), BackupConsent.unknown);
    });

    test('its no stays a no', () async {
      await file().writeAsString('declined');
      expect(await store().read(), BackupConsent.declined);
    });
  });

  test('an unreadable file is still a refusal', () async {
    await file().writeAsString('{not json');
    expect(await store().read(), BackupConsent.unknown);
    await file().writeAsString('{"answer": 3}');
    expect(await store().read(), BackupConsent.unknown);
  });
}
