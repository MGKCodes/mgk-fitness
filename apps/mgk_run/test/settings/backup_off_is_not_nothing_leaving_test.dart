import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_screen.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';
import 'package:mgk_run/src/features/settings/domain/backup_health.dart';
import 'package:mgk_run/src/features/settings/presentation/backup_screen.dart';

/// **The backup switch decides our servers, not whether anything leaves.**
///
/// Two screens said otherwise. The empty Plan tab: "None of it leaves the
/// phone unless you turn backup on". The backup screen: "Off, everything
/// stays on this phone". Both were false the moment the coach was used,
/// because it sends a summary of the runner's training to the AI provider
/// whatever the switch says -- and the second was false again because the
/// phone's own backup can hold a copy.
void main() {
  testWidgets('the backup screen says the coach is separate', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: BackupScreen(
          consent: BackupConsent.declined,
          health: const BackupHealth(),
          busy: false,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('everything stays on this phone'), findsNothing);
    expect(find.textContaining('kept on our servers'), findsOneWidget);
    expect(find.textContaining("phone's own backup"), findsOneWidget);
    expect(find.textContaining('Using the coach is separate'), findsOneWidget);
  });

  testWidgets('the empty Plan tab does not promise nothing leaves', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: PlanScreen(onBuildPlan: () {})));
    await tester.pumpAndSettle();

    expect(find.textContaining('None of it leaves the phone'), findsNothing);
    expect(
      find.textContaining('the coach asks before it sends anything'),
      findsOneWidget,
    );
  });
}
