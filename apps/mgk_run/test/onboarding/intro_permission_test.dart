import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_permission.dart';

/// The permissions the intro asks for, and everything the coach says round
/// them (ADR-0019).
void main() {
  test('there is at least one, or the step renders empty', () {
    // `IntroScreen` skips the step when this is empty rather than showing a
    // blank screen, but an empty list would also mean Runio shipped without
    // asking for location, which is the permission the product needs.
    expect(introPermissions, isNotEmpty);
    expect(
      introPermissions.map((p) => p.kind),
      contains(IntroPermissionKind.location),
    );
  });

  test('each is asked once', () {
    final kinds = introPermissions.map((p) => p.kind).toList();
    expect(
      kinds.toSet(),
      hasLength(kinds.length),
      reason: 'asking twice reads as an app that was not listening',
    );
  });

  group('every permission explains itself before the dialog', () {
    test('and says what it is for in the runner\'s terms', () {
      for (final permission in introPermissions) {
        expect(permission.explain, isNotEmpty);
        expect(permission.cta, isNotEmpty);
        // The explanation is the whole reason the dialog fires here rather
        // than mid-run. An empty or one-word one is the screen not doing its
        // job.
        expect(permission.explain.length, greaterThan(40));
      }
    });
  });

  group('a refusal is answered, never scolded', () {
    test('both answers get a reply', () {
      for (final permission in introPermissions) {
        expect(permission.granted, isNotEmpty);
        expect(permission.denied, isNotEmpty);
      }
    });

    test('and the refusal says what still works', () {
      // A refused permission is a shape the app is built for, not a failure it
      // recovers from (CLAUDE.md rule 6). Copy that treated it as a problem
      // would describe a broken state that does not exist.
      for (final permission in introPermissions) {
        final denied = permission.denied.toLowerCase();
        expect(
          denied,
          contains('settings'),
          reason: 'a runner who changes their mind needs to know where to go',
        );
        for (final scold in <String>[
          'sorry',
          'unfortunately',
          'error',
          'you must',
          'required',
          'cannot use',
        ]) {
          expect(
            denied,
            isNot(contains(scold)),
            reason: '"$scold" makes a choice sound like a mistake',
          );
        }
      }
    });
  });

  test('the coach never uses an em dash, scripted or not', () {
    for (final permission in introPermissions) {
      for (final line in <String>[
        permission.explain,
        permission.cta,
        permission.granted,
        permission.denied,
      ]) {
        expect(line, isNot(contains('—')), reason: 'em dash in: $line');
      }
    }
  });
}
