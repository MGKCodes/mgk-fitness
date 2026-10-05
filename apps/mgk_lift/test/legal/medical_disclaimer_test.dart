import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/auth/data/fake_auth.dart';
import 'package:mgk_lift/src/features/auth/domain/account.dart';
import 'package:mgk_lift/src/features/coaching/data/supabase_coach.dart';
import 'package:mgk_lift/src/features/coaching/presentation/coach_sheet.dart';
import 'package:mgk_lift/src/features/entitlement/domain/entitlement.dart';
import 'package:mgk_lift/src/features/home/presentation/lift_shell.dart';
import 'package:mgk_lift/src/features/legal/domain/disclaimer_store.dart';
import 'package:mgk_lift/src/features/legal/domain/legal_copy.dart';
import 'package:mgk_lift/src/features/legal/presentation/legal_screen.dart';
import 'package:mgk_lift/src/features/legal/presentation/medical_disclaimer_screen.dart';
import 'package:mgk_lift/src/features/purchases/domain/purchases.dart';
import 'package:mgk_lift/src/features/purchases/presentation/sales_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **The coach asks for the medical disclaimer first** (5 October 2026, as
/// Run's always has). The coach answers questions about sore shoulders and
/// builds plans around injuries; the terms said "not medical advice", and
/// nothing said it where the asking happens.
void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    required DisclaimerStore store,
    bool subscribed = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LiftShell(
          coach: FakeCoach(),
          auth: FakeAuth(
            account: const Account(id: 'u', email: 'a@b.com'),
          ),
          isEntitled: subscribed,
          entitlements: subscribed
              ? null
              : EntitlementGate(source: FakeEntitlements(Entitlement.none)),
          purchases: subscribed ? null : FakePurchases(),
          disclaimers: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapTheMark(WidgetTester tester) async {
    await tester.tap(find.byType(CoachButton));
    await tester.pumpAndSettle();
  }

  testWidgets('the mark asks for it before the coach opens', (tester) async {
    final store = InMemoryDisclaimerStore();
    await pumpShell(tester, store: store);

    await tapTheMark(tester);
    expect(find.byType(MedicalDisclaimerScreen), findsOneWidget);
    expect(find.byType(CoachSheet), findsNothing);

    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();
    expect(find.byType(CoachSheet), findsOneWidget);
    expect(store.acknowledgeCount, 1);
  });

  testWidgets('and once it is accepted, never again on this phone', (
    tester,
  ) async {
    await pumpShell(tester, store: InMemoryDisclaimerStore(acknowledged: true));

    await tapTheMark(tester);
    expect(find.byType(MedicalDisclaimerScreen), findsNothing);
    expect(find.byType(CoachSheet), findsOneWidget);
  });

  testWidgets('Not now opens nothing, records nothing, and asks again', (
    tester,
  ) async {
    final store = InMemoryDisclaimerStore();
    await pumpShell(tester, store: store);

    await tapTheMark(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.byType(CoachSheet), findsNothing);
    expect(store.acknowledgeCount, 0);

    await tapTheMark(tester);
    expect(find.byType(MedicalDisclaimerScreen), findsOneWidget);
  });

  testWidgets('the disclaimer, and only then a price', (tester) async {
    // Run's order: what somebody is about to be able to ask is the reason the
    // disclaimer is said, so it comes before the offer, not after a purchase.
    await pumpShell(
      tester,
      store: InMemoryDisclaimerStore(),
      subscribed: false,
    );

    await tapTheMark(tester);
    expect(find.byType(MedicalDisclaimerScreen), findsOneWidget);
    expect(find.byType(SalesScreen), findsNothing);

    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();
    expect(find.byType(SalesScreen), findsOneWidget);
  });

  testWidgets('Privacy & legal shows it to read, with nothing to accept', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LegalScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Medical disclaimer'));
    await tester.pumpAndSettle();
    expect(find.byType(MedicalDisclaimerScreen), findsOneWidget);
    expect(find.text('I understand'), findsNothing);
  });

  test('it says what the terms say, word for word', () {
    // No new legal wording: the disclaimer is the terms' "Not medical
    // advice", put where the coach is asked.
    final terms = termsOfUse.sections.firstWhere(
      (s) => s.heading == 'Not medical advice',
    );
    expect(medicalDisclaimer.lead, terms.paragraphs.single);
    for (final caution in terms.bullets) {
      expect(medicalDisclaimer.sections.single.bullets, contains(caution));
    }
  });
}
