import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Retired names must not come back in copy a runner reads.**
///
/// `docs/naming.md` retired Runio and Liftio as user-facing names on
/// 2026-08-21. The rename swept the strings that existed then — and two new
/// ones appeared afterwards anyway, written months later by people (and agents)
/// working from surrounding code that still said `RunioApp` and from docs that
/// keep the old name on purpose. One of them sat on the busiest screen in the
/// app: *"Press start and Runio tracks the route."*
///
/// Neither was caught by 1,186 tests, because nothing asserts on prose. They
/// were caught by looking at a rendered screen, which is not a thing that
/// happens on a schedule. So this is the schedule.
///
/// **What is deliberately allowed**, per that document's own "What keeps the
/// old names on purpose" section: Dart identifiers such as `RunioApp`, package
/// names, and every comment and doc — the ADRs and the changelog are dated
/// records of what was decided when, and rewriting them would falsify the
/// history they exist to preserve.
///
/// So this looks only at **string literals in `lib/`**, which is the only place
/// a name can reach a runner from.
void main() {
  test('no retired product name appears in a user-facing string', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // The preview harness is a developer tool that never ships, and it names
      // the products it is a harness for.
      if (entity.path.contains('preview')) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trimLeft();
        // Comments are exempt — see the class doc. This is a line-level check
        // rather than a parse, which is enough: a retired name inside a
        // *trailing* comment on a code line is not copy either, and the cost of
        // being wrong here is a false positive somebody reads and dismisses.
        if (trimmed.startsWith('//')) continue;

        // Only inside quotes. `RunioApp` as an identifier is allowed and is the
        // exact thing that made the two real offenders look normal in context.
        final inString = RegExp(
          r"""(['"])[^'"]*\b(Runio|Liftio)\b[^'"]*\1""",
        ).hasMatch(line);
        if (!inString) continue;

        offenders.add('${entity.path}:${i + 1}  ${trimmed.trim()}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Retired product names in user-facing strings. docs/naming.md says '
          'first mention gets the full name ("MGKFitness: Run") and everything '
          'after it says "the app" — never a bare "Run", because "your Run '
          'data" and "your run data" are the same sentence.\n'
          '${offenders.join('\n')}',
    );
  });
}
