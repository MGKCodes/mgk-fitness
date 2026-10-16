import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/settings/presentation/settings_screen.dart';

/// The version Settings shows, and *Report a problem* writes into every
/// report, is a constant that has to be moved by hand when the pubspec moves.
/// It was left at 1.0.0 when develop went to 1.0.1, and nothing noticed.
/// Lift's suite holds its own constant the same way.
void main() {
  test('the version shown in Settings matches pubspec.yaml', () {
    final String line = File(
      'pubspec.yaml',
    ).readAsLinesSync().firstWhere((String l) => l.startsWith('version:'));
    final String name = line
        .substring('version:'.length)
        .trim()
        .split('+')
        .first;
    expect(kAppVersion, name);
  });
}
