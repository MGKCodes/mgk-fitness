import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_report.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_conversation.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_slots.dart';
import 'package:mgk_run/src/features/coaching/presentation/chat_controller.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_conversation.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_report_sheet.dart';
import 'package:mgk_run/src/features/coaching/presentation/onboarding_controller.dart';
import 'package:mgk_run/src/features/coaching/presentation/onboarding_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// Where reports go: kept, or refused, as the test says.
class _Reports implements CoachReporter {
  final List<CoachReport> sent = <CoachReport>[];
  Object? failure;

  @override
  Future<void> report(CoachReport report) async {
    final error = failure;
    if (error != null) throw error;
    sent.add(report);
  }
}

class _QuietChat implements CoachChatClient {
  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async => const ChatTurn(reply: 'Noted.');
}

class _Intake implements CoachClient {
  @override
  Future<IntakeTurn> intake({
    required IntakeSlots slots,
    required List<IntakeMessage> history,
  }) async => const IntakeTurn(
    reply: 'Run through the pain, it builds character.',
    extracted: IntakeSlots(),
  );
}

/// **A coach reply can be reported without leaving the app.**
///
/// Google Play's policy on AI-generated content asks for exactly this: a way
/// to flag what the model said, from where it was said. A long press on any of
/// the coach's replies opens the report; a reason is required and nothing is
/// chosen for the runner; the note is optional. It goes to `coach.reports` as
/// the signed-in runner, and a report that did not send says so and keeps
/// what they wrote.
void main() {
  const reply = 'Run through the pain, it builds character.';

  group('the row that is sent', () {
    test('carries the reply, the reason and the note, and nothing of who', () {
      final row = const CoachReport(
        reply: reply,
        reason: CoachReportReason.harmful,
        note: '  I have a stress fracture  ',
      ).toRow();

      expect(row, <String, Object?>{
        'app': 'run',
        'reply': reply,
        'reason': 'harmful',
        'note': 'I have a stress fracture',
      });
      // Defaulted on the server; the user is auth.uid(), never the client's
      // say-so.
      expect(row.containsKey('user_id'), isFalse);
      expect(row.containsKey('created_at'), isFalse);
    });

    test('the four reasons are the four codes the table takes', () {
      expect(CoachReportReason.values.map((r) => r.code), <String>[
        'harmful',
        'wrong',
        'offensive',
        'other',
      ]);
      expect(CoachReportReason.values.map((r) => r.label), <String>[
        'Harmful or unsafe',
        'Wrong or misleading',
        'Offensive',
        'Something else',
      ]);
    });

    test('a blank note is no note', () {
      final row = const CoachReport(
        reply: reply,
        reason: CoachReportReason.other,
        note: '   ',
      ).toRow();

      expect(row['note'], isNull);
    });

    test('a long reply is cut, never split mid-character', () {
      final long = '${'a' * 7999}🏃🏃';
      final stored =
          CoachReport(
                reply: long,
                reason: CoachReportReason.wrong,
                note: 'n' * 1200,
              ).toRow()['reply']!
              as String;

      expect(stored.runes.length, CoachReport.maxReply);
      expect(stored, endsWith('🏃'));
      expect(
        (CoachReport(
                  reply: reply,
                  reason: CoachReportReason.wrong,
                  note: 'n' * 1200,
                ).toRow()['note']!
                as String)
            .length,
        CoachReport.maxNote,
      );
    });

    test('it is inserted into coach.reports and never read back', () {
      // Read as source, the way mirror_round_trip_test.dart reads the backup:
      // the table's policy lets a client insert and read nothing, so a
      // `.select()` chained on here would turn every report that arrived into
      // one the runner is told failed.
      final source = File(
        'lib/src/features/coaching/data/supabase_coach_reports.dart',
      ).readAsStringSync();

      // Comments dropped first: the file explains why there is no select.
      final code = const LineSplitter()
          .convert(source)
          .where((line) => !line.trimLeft().startsWith('//'))
          .join(' ');

      expect(code, contains(".schema('coach')"));
      expect(code, contains(".from('reports')"));
      expect(code, contains('.insert('));
      expect(code, isNot(contains('.select(')));
    });
  });

  group('in the conversation', () {
    late _Reports reports;
    late ChatController controller;

    setUp(() {
      reports = _Reports();
      controller = ChatController(client: _QuietChat(), brief: (_) async => '');
    });

    Future<void> pumpSheet(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await controller.openWithNote(reply);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CoachConversationSheet(
              controller: controller,
              reporter: reports,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a long press reports the reply, with a reason and a note', (
      tester,
    ) async {
      await pumpSheet(tester);

      await tester.longPress(find.text(reply));
      await tester.pumpAndSettle();
      expect(find.byType(CoachReportSheet), findsOneWidget);

      // Nothing is chosen for them, so nothing can be sent yet.
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();
      expect(reports.sent, isEmpty);

      await tester.tap(find.text('Harmful or unsafe'));
      await tester.enterText(find.byType(TextField).last, 'I have a fracture');
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();

      expect(reports.sent, hasLength(1));
      expect(reports.sent.single.reply, reply);
      expect(reports.sent.single.reason, CoachReportReason.harmful);
      expect(reports.sent.single.note, 'I have a fracture');
      expect(find.byType(CoachReportSheet), findsNothing);
      expect(find.textContaining('Reported.'), findsOneWidget);
    });

    testWidgets('a report that did not send says so, and keeps what was '
        'written', (tester) async {
      reports.failure = const SocketException('offline');
      await pumpSheet(tester);

      await tester.longPress(find.text(reply));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Offensive'));
      await tester.enterText(find.byType(TextField).last, 'Not okay');
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();

      expect(find.byType(CoachReportSheet), findsOneWidget);
      expect(find.textContaining("That didn't send"), findsOneWidget);
      expect(find.text('Not okay'), findsOneWidget);

      reports.failure = null;
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();

      expect(reports.sent.single.reason, CoachReportReason.offensive);
      expect(reports.sent.single.note, 'Not okay');
      expect(find.byType(CoachReportSheet), findsNothing);
    });

    testWidgets('the runner\'s own messages are not reportable', (
      tester,
    ) async {
      await pumpSheet(tester);
      await controller.send('How am I doing?');
      await tester.pumpAndSettle();

      await tester.longPress(find.text('How am I doing?'));
      await tester.pumpAndSettle();

      expect(find.byType(CoachReportSheet), findsNothing);
    });
  });

  testWidgets('the intake conversation offers the same', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final reports = _Reports();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: OnboardingScreen(
          controller: OnboardingController(coach: _Intake()),
          onReview: (_) {},
          reporter: reports,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text(reply));
    await tester.pumpAndSettle();
    expect(find.byType(CoachReportSheet), findsOneWidget);

    await tester.tap(find.text('Wrong or misleading'));
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();

    expect(reports.sent.single.reason, CoachReportReason.wrong);
    expect(reports.sent.single.toRow()['note'], isNull);
    expect(find.textContaining('Reported.'), findsOneWidget);
  });
}
