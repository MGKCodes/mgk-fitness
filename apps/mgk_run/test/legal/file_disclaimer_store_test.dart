import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/legal/data/file_disclaimer_store.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('runio_disclaimer_test');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  FileDisclaimerStore storeIn(Directory d) =>
      FileDisclaimerStore(directory: () async => d);

  test('starts unacknowledged', () async {
    expect(await storeIn(dir).isAcknowledged(), isFalse);
  });

  test(
    'acknowledgement survives a new store over the same directory',
    () async {
      await storeIn(dir).acknowledge();

      // A fresh instance is what the next app launch constructs.
      expect(await storeIn(dir).isAcknowledged(), isTrue);
    },
  );

  test('acknowledging twice is harmless', () async {
    final store = storeIn(dir);
    await store.acknowledge();
    await store.acknowledge();

    expect(await store.isAcknowledged(), isTrue);
  });

  test('creates the directory if it is missing', () async {
    final nested = Directory('${dir.path}/does/not/exist/yet');
    final store = storeIn(nested);

    await store.acknowledge();

    expect(await store.isAcknowledged(), isTrue);
  });

  test('a directory that cannot be resolved reads as unacknowledged', () async {
    // The fail-safe direction: an unusable store shows the disclaimer again
    // rather than silently treating it as accepted.
    final broken = FileDisclaimerStore(
      directory: () async => throw const FileSystemException('no directory'),
    );

    expect(await broken.isAcknowledged(), isFalse);
    // And a failed write does not throw at the caller.
    await expectLater(broken.acknowledge(), completes);
    expect(await broken.isAcknowledged(), isFalse);
  });
}
