import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/session_status.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_calendar.dart';

void main() {
  // Monday the 20th, so the seven cells are the 20th to the 26th.
  final weekStart = DateTime(2026, 7, 20);

  final profile = RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 1),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );
  final slot = buildSkeleton(profile, now: weekStart).weeks[0];
  final week = buildFallbackWeek(slot, profile);

  Future<void> pumpCalendar(
    WidgetTester tester, {
    SessionStatus? Function(int weekday)? statusFor,
    DateTime? today,
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekCalendar(
            week: week,
            weekStart: weekStart,
            today: today,
            statusFor: statusFor,
          ),
        ),
      ),
    );
  }

  // A skipped session used to be a line-through on an 11px number and a dimmer
  // bar. Beside a completed day, which gets a tick, and a day nothing has
  // happened to yet, that is a difference you have to go looking for — and a
  // skipped session is a real event in someone's training.
  testWidgets('skipped and completed each get a mark, in the same slot', (
    tester,
  ) async {
    await pumpCalendar(
      tester,
      statusFor: (weekday) => switch (weekday) {
        1 => SessionStatus.completed,
        2 => SessionStatus.skipped,
        _ => null,
      },
    );

    final done = tester.getRect(find.byIcon(Icons.check));
    final skipped = tester.getRect(find.byIcon(Icons.close));
    expect(
      skipped.top,
      closeTo(done.top, 0.5),
      reason: 'the status of a week should read along one line',
    );
    expect(skipped.left, greaterThan(done.left)); // Tuesday is right of Monday
  });

  testWidgets('a day nothing has happened to carries no mark', (tester) async {
    await pumpCalendar(tester, statusFor: (_) => null);

    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  // ADR-0009: `danger` signals a genuine error or an over-limit state. Missing
  // a session is neither — it is a normal thing that happens in a block, and
  // the only red mark on an otherwise greyscale screen would read as a
  // telling-off rather than as information.
  testWidgets('a skipped session stays greyscale', (tester) async {
    await pumpCalendar(
      tester,
      statusFor: (w) => w == 2 ? SessionStatus.skipped : null,
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.close));
    expect(icon.color, isNot(AppColors.danger));
    expect(icon.color, isNot(AppColors.success));
  });

  testWidgets('a skipped session says so to a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCalendar(
      tester,
      statusFor: (w) => w == 2 ? SessionStatus.skipped : null,
    );

    expect(find.bySemanticsLabel(RegExp('skipped')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('today still owns the one emphasis the calendar has', (
    tester,
  ) async {
    // A status mark must not turn a day into a second "today": marking the
    // skipped day is a mark in a slot, not a change of fill.
    await pumpCalendar(
      tester,
      today: DateTime(2026, 7, 22), // Wednesday
      statusFor: (w) => w == 2 ? SessionStatus.skipped : null,
    );

    final filled = tester.widgetList<Material>(
      find.descendant(
        of: find.byType(WeekCalendar),
        matching: find.byType(Material),
      ),
    );
    expect(
      filled.where((m) => m.color == AppColors.primary),
      hasLength(1),
      reason: 'exactly one cell is silver, and it is today',
    );
  });
}
