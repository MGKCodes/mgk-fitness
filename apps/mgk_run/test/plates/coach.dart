/// **The coach's doors, as build 26 has them.**
///
/// Build 26 put a question in front of every way into the coach — whether the
/// runner's training may go to the AI provider at all — and then the medical
/// disclaimer, then the price. It also made a reply reportable and taught the
/// paywall to say what actually happened to a purchase. None of it had been on
/// a board, and each of it only exists as a *sequence*: a consent sheet drawn
/// on its own proves nothing about whether it comes before the price.
///
/// So everything here is walked from the coach mark or from the card that
/// offers the coach, through the real `HomeShell` ([plateApp]). What is faked
/// is only what a phone would answer: the store's reply to a purchase, and — in
/// one plate, `coach-report-sent` — where a report goes, because the shell has
/// no seam for it and the real destination needs a server.
///
/// Regenerate with:
///
///     flutter test test/plates/coach.dart
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_coach_service.dart';
import 'package:mgk_run/preview/fake_purchases.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_offer.dart';
import 'package:mgk_run/src/features/coaching/domain/ai_consent.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_report.dart';
import 'package:mgk_run/src/features/coaching/presentation/chat_controller.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_conversation.dart';
import 'package:mgk_run/src/features/legal/domain/disclaimer_store.dart';
import 'package:mgk_ui/mgk_ui.dart';

import 'fixture.dart';
import 'plate.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<DriftPlanStore> seeded() async {
    final store = DriftPlanStore(db);
    await seedPlan(store);
    return store;
  }

  /// The mark, tapped where it is drawn. See `flows.dart` for why the glyph.
  Future<void> tapCoach(WidgetTester tester) async {
    await tester.tap(find.byType(CoachMarkGlyph));
    await settle(tester);
    await settle(tester);
  }

  /// A runner who has never been asked: an account, no subscription, and
  /// neither the permission nor the disclaimer on record.
  Widget unasked(DriftPlanStore store) => plateApp(
    db,
    store,
    plateLog(),
    access: CoachAccess.free,
    aiConsent: InMemoryAiConsentStore(),
    disclaimer: InMemoryDisclaimerStore(),
  );

  // --- Asking first ----------------------------------------------------------

  testWidgets('the question before the coach answers', (tester) async {
    final store = await seeded();
    await plate(
      tester,
      'coach-consent',
      unasked(store),
      pixelRatio: 2,
      drive: (tester) async {
        await rest(tester);
        await tapCoach(tester);
      },
    );
  });

  testWidgets('the same question on the smallest phone', (tester) async {
    // On a 6.1-inch phone the sheet all but fits. On a 320pt one it scrolls,
    // and the buttons are pinned below the scroll so they are never what gets
    // cut off — which is the thing to check here, along with how much of the
    // question survives above the fold.
    final store = await seeded();
    await plate(
      tester,
      'coach-consent-small',
      unasked(store),
      size: kSmallPhone,
      drive: (tester) async {
        await rest(tester);
        await tapCoach(tester);
      },
    );
  });

  testWidgets('then the disclaimer, and only then a price', (tester) async {
    final store = await seeded();
    await plate(
      tester,
      'coach-disclaimer',
      unasked(store),
      pixelRatio: 2,
      drive: (tester) async {
        await rest(tester);
        await tapCoach(tester);
        await tester.tap(find.text('Agree'));
        await settle(tester);
        await settle(tester);
      },
    );
  });

  testWidgets('and the gate, reached the whole way round', (tester) async {
    final store = await seeded();
    await plate(
      tester,
      'coach-gate-after-consent',
      unasked(store),
      pixelRatio: 2,
      drive: (tester) async {
        await rest(tester);
        await tapCoach(tester);
        await tester.tap(find.text('Agree'));
        await settle(tester);
        await settle(tester);
        await tester.tap(find.text('I understand'));
        await settle(tester);
        await settle(tester);
      },
    );
  });

  testWidgets('signed out, the mark asks for an account first', (tester) async {
    final store = DriftPlanStore(db);
    await plate(
      tester,
      'coach-signed-out',
      plateApp(
        db,
        store,
        plateLog(),
        access: CoachAccess.free,
        auth: FakeAuthRepository(),
        aiConsent: InMemoryAiConsentStore(),
        disclaimer: InMemoryDisclaimerStore(),
      ),
      pixelRatio: 2,
      drive: (tester) async {
        await rest(tester);
        await tapCoach(tester);
      },
    );
  });

  // --- Reporting a reply -----------------------------------------------------

  /// Opens the conversation and gets one reply to report.
  Future<void> aReply(WidgetTester tester) async {
    await rest(tester);
    await tapCoach(tester);
    await tester.tap(find.textContaining('half marathon').last);
    await settle(tester);
    await settle(tester);
  }

  testWidgets('a reply, held down', (tester) async {
    final store = await seeded();
    await plate(
      tester,
      'coach-report',
      plateApp(db, store, plateLog()),
      pixelRatio: 2,
      drive: (tester) async {
        await aReply(tester);
        await tester.longPress(find.textContaining('Off your recent 5k'));
        await settle(tester);
      },
    );
  });

  testWidgets('and a report that could not be sent', (tester) async {
    // Driven through the shell, whose conversation sends reports to the real
    // backend. There is none here, so this is exactly what a runner with no
    // connection (or before the reports table exists) is shown — R4 on the
    // test sheet.
    final store = await seeded();
    await plate(
      tester,
      'coach-report-failed',
      plateApp(db, store, plateLog()),
      pixelRatio: 2,
      drive: (tester) async {
        await aReply(tester);
        await tester.longPress(find.textContaining('Off your recent 5k'));
        await settle(tester);
        await tester.tap(find.text('Wrong or misleading'));
        await tester.pump();
        await tester.enterText(
          find.byType(TextField).last,
          'It gave me a pace without asking about my calf.',
        );
        await tester.pump();
        await tester.tap(find.text('Send report'));
        await settle(tester);
        // The keyboard a phone would show is not here; drop focus so the
        // sheet sits where it does once the runner has finished typing.
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(tester);
      },
    );
  });

  testWidgets('and one that went', (tester) async {
    // **The one plate here with a seam the app does not have.** The shell
    // opens the conversation with its own reporter and offers no way to swap
    // it, so the conversation is opened directly — the same sheet, over the
    // same Home — with a reporter that accepts. What it proves is what the
    // runner is told afterwards, which is the only part a phone would add.
    final store = await seeded();
    await plate(
      tester,
      'coach-report-sent',
      plateApp(db, store, plateLog()),
      pixelRatio: 2,
      drive: (tester) async {
        await rest(tester);
        final chat = ChatController(
          client: FakeCoachService(),
          brief: (_) async => '',
        );
        final context = tester.element(find.byType(Scaffold).first);
        unawaited(
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (_) =>
                CoachConversationSheet(controller: chat, reporter: _Accepts()),
          ),
        );
        await settle(tester);
        // Not awaited: the fake coach thinks on a timer, and a timer in a
        // widget test only moves when the test pumps.
        unawaited(chat.ask('What could I run a half marathon in?'));
        await settle(tester);
        await settle(tester);
        await tester.longPress(find.textContaining('Off your recent 5k'));
        await settle(tester);
        await tester.tap(find.text('Wrong or misleading'));
        await tester.pump();
        await tester.tap(find.text('Send report'));
        await settle(tester);
      },
    );
  });

  // --- Paying ----------------------------------------------------------------

  /// A runner who has agreed and not paid, at the paywall, with the store set
  /// to answer [buy] and [restore] the way a phone might.
  Widget atThePaywall(
    DriftPlanStore store, {
    PurchaseOutcome buy = PurchaseOutcome.purchased,
    PurchaseOutcome restore = PurchaseOutcome.nothingToRestore,
  }) => plateApp(
    db,
    store,
    plateLog(),
    access: CoachAccess.free,
    purchases: FakePurchases(
      offers: plateOffers,
      buyOutcome: buy,
      restoreOutcome: restore,
    ),
  );

  Future<void> toPaywall(WidgetTester tester) async {
    await rest(tester);
    await tapCoach(tester);
    await tester.tap(find.text('See the plans'));
    await settle(tester);
    await settle(tester);
  }

  testWidgets('the paywall on Android', (tester) async {
    final store = await seeded();
    await plate(
      tester,
      'paywall-android',
      atThePaywall(store),
      pixelRatio: 2,
      platform: TargetPlatform.android,
      drive: toPaywall,
    );
  });

  for (final (String name, PurchaseOutcome outcome)
      in <(String, PurchaseOutcome)>[
        ('paywall-pending', PurchaseOutcome.pending),
        ('paywall-offline', PurchaseOutcome.offline),
        ('paywall-already-owned', PurchaseOutcome.alreadyOwned),
      ]) {
    testWidgets('the paywall, when a purchase comes back ${outcome.name}', (
      tester,
    ) async {
      final store = await seeded();
      await plate(
        tester,
        name,
        atThePaywall(store, buy: outcome),
        pixelRatio: 2,
        drive: (tester) async {
          await toPaywall(tester);
          await tester.tap(find.text('Subscribe').first);
          await settle(tester);
        },
      );
    });
  }

  testWidgets('restore, when there is nothing to restore', (tester) async {
    final store = await seeded();
    await plate(
      tester,
      'paywall-restore-none',
      atThePaywall(store),
      pixelRatio: 2,
      drive: (tester) async {
        await toPaywall(tester);
        await tester.tap(find.text('Restore purchases'));
        await settle(tester);
      },
    );
  });

  testWidgets('restore, when the store found one', (tester) async {
    // The store says restored and the server has not caught up: the screen
    // asks for about eleven seconds and then says the true thing.
    final store = await seeded();
    await plate(
      tester,
      'paywall-restored',
      atThePaywall(store, restore: PurchaseOutcome.purchased),
      pixelRatio: 2,
      drive: (tester) async {
        await toPaywall(tester);
        await tester.tap(find.text('Restore purchases'));
        for (var i = 0; i < 14; i++) {
          await tester.pump(const Duration(seconds: 1));
        }
        await settle(tester);
      },
    );
  });

  /// Signed out, with a plan still on the phone, which is how the test sheet's
  /// G3a reaches the paywall: the last-run card's offer asks for no account.
  Widget signedOutWithAPlan(
    DriftPlanStore store, {
    required PurchaseOutcome buy,
    required PurchaseOutcome restore,
  }) => plateApp(
    db,
    store,
    plateLog(),
    access: CoachAccess.free,
    auth: FakeAuthRepository(),
    purchases: FakePurchases(
      offers: plateOffers,
      buyOutcome: buy,
      restoreOutcome: restore,
    ),
  );

  Future<void> signedOutToPaywall(WidgetTester tester) async {
    await rest(tester);
    await tester.scrollUntilVisible(
      find.text('See what a coach adds'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    await tester.tap(find.text('See what a coach adds'));
    await settle(tester);
    await tester.tap(find.text('See the plans'));
    await settle(tester);
    await settle(tester);
  }

  testWidgets('subscribing signed out, refused before the store', (
    tester,
  ) async {
    final store = await seeded();
    await plate(
      tester,
      'paywall-sign-in-first',
      signedOutWithAPlan(
        store,
        buy: PurchaseOutcome.notIdentified,
        restore: PurchaseOutcome.notIdentified,
      ),
      pixelRatio: 2,
      drive: (tester) async {
        await signedOutToPaywall(tester);
        await tester.tap(find.text('Subscribe').first);
        await settle(tester);
      },
    );
  });

  testWidgets('and restoring signed out', (tester) async {
    final store = await seeded();
    await plate(
      tester,
      'paywall-restore-sign-in-first',
      signedOutWithAPlan(
        store,
        buy: PurchaseOutcome.notIdentified,
        restore: PurchaseOutcome.notIdentified,
      ),
      pixelRatio: 2,
      drive: (tester) async {
        await signedOutToPaywall(tester);
        await tester.tap(find.text('Restore purchases'));
        await settle(tester);
      },
    );
  });
}

/// Takes every report, as `coach.reports` would once it exists.
class _Accepts implements CoachReporter {
  @override
  Future<void> report(CoachReport report) async {}
}
