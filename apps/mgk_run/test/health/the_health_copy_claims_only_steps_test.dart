import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/auth/presentation/sign_in_screen.dart';
import 'package:mgk_run/src/features/health/domain/health_workout.dart';
import 'package:mgk_run/src/features/health/domain/workout_source.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_permission.dart';
import 'package:mgk_run/src/features/settings/presentation/permissions_screen.dart';

/// A Health source that counts what was asked of it.
class _Health implements WorkoutSource {
  int requests = 0;
  int reads = 0;
  bool asked = true;

  @override
  Future<bool> requestAccess() async {
    requests++;
    return asked;
  }

  @override
  Future<List<HealthWorkout>> since(DateTime from) async {
    reads++;
    return const <HealthWorkout>[];
  }
}

/// **Every sentence about Health now says what the app does with it: steps
/// over a run recorded here, and nothing else.**
///
/// The purpose string promised runs from a watch "appear in your training log
/// and your coach sees the whole picture". The intro promised "runs you have
/// already done and anything you record on a watch". Settings offered to "bring
/// in runs from your watch". Nothing ever imported a workout, and steps never
/// reach the coach. App Review reads these strings against the app (2.3.1,
/// 5.1.1(ii)), and each described a feature that does not exist.
void main() {
  String plistString(String key) {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final match = RegExp(
      '<key>$key</key>\\s*<string>([^<]*)</string>',
    ).firstMatch(plist);
    expect(match, isNotNull, reason: '$key is missing from Info.plist');
    return match!.group(1)!;
  }

  group('the purpose strings', () {
    test('the read names steps, and nothing imported or shared', () {
      final read = plistString('NSHealthShareUsageDescription').toLowerCase();

      expect(read, contains('step count'));
      for (final claim in <String>['workout', 'training log', 'coach']) {
        expect(read, isNot(contains(claim)), reason: 'still claims "$claim"');
      }
    });

    test('the write says the app never writes', () {
      // The key has to stay: Apple's upload scan wants it because the Health
      // library links write APIs (error 90683). What it says is ours.
      final write = plistString('NSHealthUpdateUsageDescription');

      expect(write, isNot(startsWith('Save')));
      expect(write, contains('does not save anything to Health'));
    });
  });

  group('the intro', () {
    test('no button in front of a system prompt says "Allow"', () {
      for (final permission in introPermissions) {
        expect(
          permission.cta.toLowerCase(),
          isNot(contains('allow')),
          reason:
              'the system dialog is where a permission is allowed; a button '
              'saying so in front of it reads as the answer (5.1.1(iv))',
        );
      }
    });

    test('Health is explained as steps on the runs recorded here', () {
      final health = introPermissions.firstWhere(
        (p) => p.kind == IntroPermissionKind.healthKit,
      );
      final said = '${health.explain} ${health.granted} ${health.denied}'
          .toLowerCase();

      expect(said, contains('step'));
      for (final promise in <String>['watch', 'already done', 'pick it up']) {
        expect(said, isNot(contains(promise)), reason: 'promises "$promise"');
      }
    });
  });

  group('the Settings row', () {
    testWidgets(
      'asks for steps, says what follows, and reads nothing to say it',
      (tester) async {
        final health = _Health();
        await tester.pumpWidget(
          MaterialApp(home: PermissionsScreen(health: health)),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Steps and cadence for the runs you record here'),
          findsOneWidget,
        );
        expect(find.textContaining('watch'), findsNothing);

        await tester.tap(find.text('Apple Health'));
        await tester.pumpAndSettle();

        expect(health.requests, 1);
        expect(
          health.reads,
          0,
          reason: 'workouts were read only to print how many there were',
        );
        expect(find.textContaining('steps show on the runs'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  });

  testWidgets('signing up does not list the coach as free', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(auth: FakeAuthRepository(), initialSignUp: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('A coach that answers questions about your running'),
      findsNothing,
    );
    expect(find.textContaining('With a subscription, a coach'), findsOneWidget);
  });
}
