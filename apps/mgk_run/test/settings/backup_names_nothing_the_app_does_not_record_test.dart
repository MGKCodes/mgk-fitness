import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';
import 'package:mgk_run/src/features/settings/domain/backup_health.dart';
import 'package:mgk_run/src/features/settings/presentation/backup_consent_prompt.dart';
import 'package:mgk_run/src/features/settings/presentation/backup_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// The backup prompt and the Back up my data screen listed "heart rate" among
/// what is backed up (screen board K1 and T16). The app records no heart rate
/// (ADR-0024): there is no sensor read, and one typed into a run by hand is
/// part of that run. Consent asked with a false item in the list is not
/// informed consent, which is the whole reason the list is there.
void main() {
  /// Every string on screen, as one.
  String everything(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .join('\n');

  testWidgets('Back up my data', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: BackupScreen(
          consent: BackupConsent.declined,
          health: const BackupHealth(),
          busy: false,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Runs, routes, your plan'), findsOneWidget);
    expect(everything(tester).toLowerCase(), isNot(contains('heart')));
  });

  for (final (name, ask)
      in <(String, Future<BackupConsent?> Function(BuildContext))>[
        ('the first ask', askBackupConsent),
        ('keep these safe', (context) => askKeepRunsSafe(context, runs: 2)),
      ]) {
    testWidgets('the backup prompt, $name', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => ask(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('runs, routes, your plan'), findsOneWidget);
      expect(everything(tester).toLowerCase(), isNot(contains('heart')));
    });
  }
}
