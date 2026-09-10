import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_reveal.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// A coach that is present but never asked anything.
///
/// Required rather than incidental: the reveal is mounted behind
/// `if (_chat != null)`, so a shell with no coach seam draws no mark at all —
/// which is correct (a build that cannot coach must not advertise coaching) and
/// would make every assertion below pass for the wrong reason. Production wires
/// `CoachService`, which implements this, for free and paying runners alike;
/// the tier is enforced at the Edge Function and drawn from `_access`.
class _SilentChat implements CoachChatClient {
  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async => const ChatTurn(reply: '');
}

/// The two surfaces that gave the coach's reading away for free.
///
/// Both are computed in Dart, so both cost nothing to produce and neither was
/// gated: the coach mark sat silent on Home with no way to learn what it was,
/// and Profile's standing card told a free runner where their training stood —
/// which is the *reading* `coach_access.dart` says the subscription buys.
///
/// Asserted through the real [HomeShell] rather than against the two widgets,
/// for the reason this release has now paid for four times: a widget cannot
/// test the argument its caller declined to pass, and every one of those four
/// defects was a correct widget wired to nothing. So the tier is pinned on the
/// shell and the assertions are made on what a runner would actually see.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// A shell with one run behind it, at a pinned tier.
  ///
  /// One run rather than none: `TrainingStanding` needs something to read, and
  /// an empty log produces the "nothing yet" standing, which would let the
  /// locked assertions pass for the wrong reason.
  Widget shellAt(CoachAccess access) => MaterialApp(
    theme: AppTheme.dark,
    home: HomeShell(
      auth: FakeAuthRepository(signedIn: true, email: 'dev@mgkcodes.com'),
      access: access,
      chatClient: _SilentChat(),
      historySource: () async => <RunSummary>[
        RunSummary(
          startedAt: DateTime.now().subtract(const Duration(days: 2)),
          duration: const Duration(minutes: 41, seconds: 8),
          distanceMeters: 7400,
        ),
      ],
    ),
  );

  final lockedLine = CoachReveal.lockedNote.headline;

  /// Pumps to the middle of the reveal, and deliberately **not** to settle.
  ///
  /// The bar arrives, holds and retracts into the mark, and on retracting it
  /// reports itself delivered — so at `pumpAndSettle` the line is correctly
  /// gone and an assertion there tests the wrong instant. The first pumps let
  /// the run log land (it is read asynchronously and the reveal is mounted
  /// behind it); the last lands inside the hold, well after the 272ms arrival
  /// and well before the retraction.
  Future<void> pumpToMidReveal(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(kCoachRevealDuration ~/ 3);
  }

  group('the coach mark says what it is', () {
    testWidgets('a free runner is told the coach costs money', (tester) async {
      await tester.pumpWidget(shellAt(CoachAccess.free));
      await pumpToMidReveal(tester);

      expect(
        find.text(lockedLine),
        findsOneWidget,
        reason:
            'the mark is the door to the gate sheet and nothing said so — a '
            'runner could only find out by pressing an unlabelled C',
      );

      // And it does not outstay: the bar is a sign, not a banner.
      await tester.pumpAndSettle();
      expect(find.text(lockedLine), findsNothing);
    });

    testWidgets('a subscriber is not sold what they already bought', (
      tester,
    ) async {
      await tester.pumpWidget(shellAt(CoachAccess.subscribed));
      await pumpToMidReveal(tester);

      expect(
        find.text(lockedLine),
        findsNothing,
        reason: 'the locked line must never reach somebody who has paid',
      );
      await tester.pumpAndSettle();
    });
  });

  group("Profile's standing is the paid reading", () {
    /// The locked copy, from the screen that owns it. Matched on the headline
    /// rather than the whole card so a wording change is one edit.
    const locked = 'Your coach reads your training.';

    testWidgets('a free runner gets the door, not the reading', (tester) async {
      await tester.pumpWidget(shellAt(CoachAccess.free));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      expect(
        find.text(locked),
        findsOneWidget,
        reason: 'the card stays as a door — removing it hides the paywall',
      );
      // The card's own heading survives, because the card does.
      expect(find.text('YOUR COACH'), findsOneWidget);
    });

    testWidgets('a subscriber gets the reading', (tester) async {
      await tester.pumpWidget(shellAt(CoachAccess.subscribed));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      expect(
        find.text(locked),
        findsNothing,
        reason: 'a paying runner must get their standing, not an offer',
      );
      expect(find.text('YOUR COACH'), findsOneWidget);
    });
  });
}
