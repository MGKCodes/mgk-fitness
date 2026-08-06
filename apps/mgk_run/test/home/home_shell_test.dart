import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';

void main() {
  testWidgets('opens on Home, with Home/Plan/Profile navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
        ),
      ),
    );
    await tester.pump();

    // Bottom navigation destinations.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    // Home leads with today and the way into a run.
    expect(find.text('Record a run'), findsOneWidget);
    expect(find.textContaining('TODAY'), findsWidgets);

    // Home is not an account screen: identity and sign-out belong on Profile
    // and in the settings behind it. `hitTestable` because the tabs live in an
    // IndexedStack — the Profile tab is built while Home is showing, and a
    // plain finder would count text the runner cannot see.
    expect(find.text('dev@runio.app').hitTestable(), findsNothing);
    expect(find.byTooltip('Sign out'), findsNothing);
  });

  /// The run log is *context* on the Coach tab — it supplies the count in a
  /// rhythm's headline and nothing else. It used to be read outside the tab's
  /// try, so a log that threw took the whole load with it and left the tab
  /// spinning for good, with a perfectly readable plan sitting on disk.
  testWidgets('the Plan tab still loads when the run log throws', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
          historySource: () async => throw Exception('history is offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Home survives it too: the same bare read ran from `initState`, so a
    // throwing log stopped the refresh before it ever loaded the plan.
    expect(find.text('Record a run'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();

    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: 'a failed run log must not leave the tab loading',
    );
    // No plan was injected, so the tab settles on its empty state rather than
    // on a spinner or an error.
    expect(find.textContaining('Plan'), findsWidgets);
  });
}
