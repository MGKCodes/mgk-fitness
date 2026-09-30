/// **Settings, the account, and every way of leaving.**
///
/// Settings became an index with a profile at the top on 2026-09-11, the
/// account moved behind that profile, and build 26 rewrote most of what sits
/// behind it: signing out can take the phone's copy with it, deleting the
/// account erases the phone by default and says the subscription keeps
/// renewing, the done screen says what happened to the login, a second account
/// signing in is asked what to do about the first one's training, and the
/// coach's permission can be withdrawn under Privacy & legal.
///
/// **Built from Settings, then driven.** The shell hands Settings no
/// entitlement source of its own, so a Settings reached by tapping through the
/// shell always reads the subscription as "Free" — a picture of a subscriber's
/// account that says they are not one. So each plate here constructs Settings
/// (or the screen a row opens) with the account it is about, and from there
/// taps the way a runner would. What is faked is only what the phone or the
/// server would answer: whether location is on, what the store says was
/// bought, and what the deletion endpoint replied.
///
/// Regenerate with:
///
///     flutter test test/plates/account.dart
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_purchases.dart';
import 'package:mgk_run/src/features/auth/presentation/auth_gate.dart';
import 'package:mgk_run/src/features/coaching/domain/ai_consent.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_subscription.dart';
import 'package:mgk_run/src/features/health/domain/health_workout.dart';
import 'package:mgk_run/src/features/health/domain/workout_source.dart';
import 'package:mgk_run/src/features/legal/domain/account_deleter.dart';
import 'package:mgk_run/src/features/legal/presentation/delete_account_screen.dart';
import 'package:mgk_run/src/features/legal/presentation/legal_screen.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_store.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';
import 'package:mgk_run/src/features/settings/domain/backup_health.dart';
import 'package:mgk_run/src/features/settings/domain/local_data.dart';
import 'package:mgk_run/src/features/settings/domain/profile_photo.dart';
import 'package:mgk_run/src/features/settings/domain/unit_settings.dart';
import 'package:mgk_run/src/features/settings/presentation/settings_screen.dart';
import 'package:mgk_units/mgk_units.dart';

import 'fixture.dart';
import 'plate.dart';

void main() {
  /// **Location on, as the phone would say.** Settings and Permissions ask
  /// the platform, and a test has no platform: every plate before this one
  /// read "Not set" beside Permissions, which on a phone that has recorded
  /// twenty runs is a claim nobody could make.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          (call) async => switch (call.method) {
            'checkPermission' => 2, // while in use
            _ => null,
          },
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          null,
        );
  });

  FakeAuthRepository signedIn() =>
      FakeAuthRepository(signedIn: true, email: 'sam@example.com', name: 'Sam');

  const CoachSubscription coachOnApple = CoachSubscription(
    tier: CoachTier.coach,
    standing: SubscriptionStanding.active,
    store: BillingStore.appStore,
  );

  /// Settings as a runner three months in has it.
  Widget settings({
    FakeAuthRepository? auth,
    CoachSubscription subscription = coachOnApple,
    AccountDeleter? deleter,
  }) => pushed(
    SettingsScreen(
      unit: UnitSystem.metric,
      settings: InMemoryUnitSettings(),
      auth: auth ?? signedIn(),
      deleter: deleter ?? const _Deletes(),
      memberSince: DateTime(2026, 6, 14),
      introStore: InMemoryIntroStore(done: true, name: 'Sam'),
      consentStore: InMemoryBackupConsent(BackupConsent.granted),
      backupHealthStore: InMemoryBackupHealth(
        BackupHealth(
          lastSucceededAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      ),
      // Present, so signing out offers to take the phone's copy too.
      eraseThisPhone: () async {},
      entitlements: FakeEntitlements.of(subscription),
      photoStore: const _NoPhoto(),
      health: _Health(),
    ),
  );

  /// Scrolls [target] into view. The screens here are lazy lists, so a row
  /// below the fold is not built until the list is scrolled towards it and
  /// `ensureVisible` has nothing to find.
  Future<void> into(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await settle(tester);
  }

  Future<void> openAccount(WidgetTester tester) async {
    await settle(tester);
    await tester.tap(find.text('Sam').first);
    await settle(tester);
  }

  // --- The index -------------------------------------------------------------

  testWidgets('settings, for a subscriber', (tester) async {
    await plate(tester, 'settings', settings(), pixelRatio: 2, drive: settle);
  });

  testWidgets('what backing up says, and the switch', (tester) async {
    await plate(
      tester,
      'settings-backup',
      settings(),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        await tester.tap(find.text('Back up my data'));
        await settle(tester);
      },
    );
  });

  testWidgets('what the app may read off the phone', (tester) async {
    await plate(
      tester,
      'settings-permissions',
      settings(),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        await tester.tap(find.text('Permissions'));
        await settle(tester);
      },
    );
  });

  // --- The account, and where its subscription stands -------------------------

  testWidgets('the account, subscribed through the App Store', (tester) async {
    await plate(
      tester,
      'account',
      settings(),
      pixelRatio: 2,
      drive: openAccount,
    );
  });

  testWidgets('the account, subscribed through Google Play', (tester) async {
    await plate(
      tester,
      'account-google-play',
      settings(
        subscription: const CoachSubscription(
          tier: CoachTier.coach,
          standing: SubscriptionStanding.active,
          store: BillingStore.googlePlay,
        ),
      ),
      pixelRatio: 2,
      platform: TargetPlatform.android,
      // Scrolled: the sentence that names the store is the subject.
      drive: (tester) async {
        await openAccount(tester);
        await into(tester, find.text('Status'));
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -120));
        await settle(tester);
      },
    );
  });

  for (final (String name, CoachSubscription subscription)
      in <(String, CoachSubscription)>[
        ('account-free', CoachSubscription.none),
        (
          'account-premium',
          const CoachSubscription(
            tier: CoachTier.premiumCoach,
            standing: SubscriptionStanding.active,
            store: BillingStore.appStore,
          ),
        ),
        (
          'account-payment-failed',
          const CoachSubscription(
            tier: CoachTier.coach,
            standing: SubscriptionStanding.billingRetry,
            store: BillingStore.appStore,
          ),
        ),
        (
          'account-ended',
          const CoachSubscription(
            tier: CoachTier.coach,
            standing: SubscriptionStanding.ended,
            store: BillingStore.appStore,
          ),
        ),
      ]) {
    testWidgets('the account, $name', (tester) async {
      await plate(
        tester,
        name,
        settings(subscription: subscription),
        pixelRatio: 2,
        drive: (tester) async {
          await openAccount(tester);
          // Scrolled to the subscription block, which is the subject.
          await into(tester, find.text('Status'));
          await tester.drag(
            find.byType(Scrollable).last,
            const Offset(0, -120),
          );
          await settle(tester);
        },
      );
    });
  }

  testWidgets('the profile, with no account behind it', (tester) async {
    await plate(
      tester,
      'account-signed-out',
      settings(
        auth: FakeAuthRepository(name: 'Sam'),
        subscription: CoachSubscription.none,
      ),
      pixelRatio: 2,
      // Scrolled to the invitation, which is what this state is about.
      drive: (tester) async {
        await openAccount(tester);
        await into(tester, find.text('Create an account'));
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -120));
        await settle(tester);
      },
    );
  });

  // --- Signing out -----------------------------------------------------------

  Future<void> toSignOut(WidgetTester tester) async {
    await openAccount(tester);
    await into(tester, find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await settle(tester);
  }

  testWidgets('signing out keeps the phone copy by default', (tester) async {
    await plate(
      tester,
      'sign-out',
      settings(),
      pixelRatio: 2,
      drive: toSignOut,
    );
  });

  testWidgets('and says what goes when it does not', (tester) async {
    await plate(
      tester,
      'sign-out-erase',
      settings(),
      pixelRatio: 2,
      drive: (tester) async {
        await toSignOut(tester);
        await tester.tap(find.byType(Switch));
        await settle(tester);
      },
    );
  });

  // --- Privacy & legal, and the coach's permission ---------------------------

  Widget legal(AiConsentStore consent) => pushed(
    LegalScreen(
      auth: signedIn(),
      deleter: const _Deletes(),
      aiConsent: consent,
    ),
  );

  testWidgets('privacy & legal, with the coach agreed to', (tester) async {
    await plate(
      tester,
      'legal',
      legal(InMemoryAiConsentStore.granted()),
      pixelRatio: 2,
      drive: settle,
    );
  });

  testWidgets('taking the permission back asks once', (tester) async {
    await plate(
      tester,
      'legal-withdraw',
      legal(InMemoryAiConsentStore.granted()),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        await tester.tap(find.text('Coach and AI'));
        await settle(tester);
      },
    );
  });

  testWidgets('and says it is done', (tester) async {
    await plate(
      tester,
      'legal-withdrawn',
      legal(InMemoryAiConsentStore.granted()),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        await tester.tap(find.text('Coach and AI'));
        await settle(tester);
        await tester.tap(find.text('Withdraw'));
        await settle(tester);
      },
    );
  });

  testWidgets('the medical disclaimer, to read', (tester) async {
    await plate(
      tester,
      'legal-disclaimer',
      legal(InMemoryAiConsentStore.granted()),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        await tester.tap(find.text('Medical disclaimer'));
        await settle(tester);
      },
    );
  });

  testWidgets('the privacy policy, in the app', (tester) async {
    await plate(
      tester,
      'legal-privacy',
      legal(InMemoryAiConsentStore.granted()),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        await tester.tap(find.text('Privacy policy'));
        await settle(tester);
      },
    );
  });

  // --- Deleting the account --------------------------------------------------

  const CoachSubscription coachOnPlay = CoachSubscription(
    tier: CoachTier.coach,
    standing: SubscriptionStanding.active,
    store: BillingStore.googlePlay,
  );

  /// The deletion screen for the test sheet's Test 3: an account with a Play
  /// subscription and training on the phone.
  Widget deleting({
    AccountDeleter deleter = const _Deletes(),
    CoachSubscription subscription = coachOnPlay,
    FakeAuthRepository? auth,
  }) => pushed(
    DeleteAccountScreen(
      auth:
          auth ??
          FakeAuthRepository(signedIn: true, email: 'test3@example.com'),
      deleter: deleter,
      entitlements: FakeEntitlements.of(subscription),
      consentStore: InMemoryBackupConsent(BackupConsent.granted),
      localData: LocalDataGuard(
        owner: InMemoryLocalDataOwner('fake-user'),
        data: _Training(),
      ),
      purchases: FakePurchases(),
      openUrl: (_) async => true,
    ),
  );

  Future<void> armed(WidgetTester tester, {bool keepPhone = false}) async {
    await settle(tester);
    if (keepPhone) {
      await into(tester, find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await settle(tester);
    }
    await into(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'DELETE');
    await settle(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
  }

  Future<void> deleteIt(WidgetTester tester, {bool keepPhone = false}) async {
    await armed(tester, keepPhone: keepPhone);
    await into(tester, find.text('Delete my data'));
    await tester.tap(find.text('Delete my data'));
    await settle(tester);
  }

  testWidgets('delete account, as it opens', (tester) async {
    await plate(
      tester,
      'delete-account',
      deleting(),
      pixelRatio: 2,
      drive: settle,
    );
  });

  testWidgets('delete account, armed', (tester) async {
    await plate(
      tester,
      'delete-account-armed',
      deleting(),
      pixelRatio: 2,
      drive: (tester) async {
        await armed(tester);
        await into(tester, find.text('Keep my account'));
      },
    );
  });

  testWidgets('delete account, keeping the phone copy', (tester) async {
    await plate(
      tester,
      'delete-account-keep-phone',
      deleting(),
      pixelRatio: 2,
      drive: (tester) async {
        await armed(tester, keepPhone: true);
        await into(tester, find.text('Keep my account'));
      },
    );
  });

  testWidgets('done: the login went too', (tester) async {
    await plate(
      tester,
      'delete-done',
      deleting(
        subscription: CoachSubscription.none,
        deleter: const _Deletes(AccountDeletionResult(accountDeleted: true)),
      ),
      pixelRatio: 2,
      drive: deleteIt,
    );
  });

  testWidgets('done: the login kept because Lift uses it', (tester) async {
    await plate(
      tester,
      'delete-done-lift',
      deleting(
        deleter: const _Deletes(
          AccountDeletionResult(
            accountDeleted: false,
            retainedReason: 'other_app_data',
          ),
        ),
      ),
      pixelRatio: 2,
      drive: deleteIt,
    );
  });

  testWidgets('done: the login could not be removed, phone kept', (
    tester,
  ) async {
    await plate(
      tester,
      'delete-done-login-stuck',
      deleting(
        subscription: CoachSubscription.none,
        deleter: const _Deletes(AccountDeletionResult(accountDeleted: false)),
      ),
      pixelRatio: 2,
      drive: (tester) => deleteIt(tester, keepPhone: true),
    );
  });

  testWidgets('deleting with no account signed in', (tester) async {
    // The test sheet's E7a. The row is listed signed out, and the server
    // refuses a request with no session; this is its own answer, word for
    // word from `AccountDeletionService`.
    await plate(
      tester,
      'delete-signed-out',
      deleting(
        auth: FakeAuthRepository(),
        subscription: CoachSubscription.none,
        deleter: const _Refuses(
          'Please sign in again, then retry the deletion.',
        ),
      ),
      pixelRatio: 2,
      drive: deleteIt,
    );
  });

  // --- A second account on the same phone -------------------------------------

  testWidgets("this phone has another account's training on it", (
    tester,
  ) async {
    await plate(
      tester,
      'another-account',
      AuthGate(
        auth: FakeAuthRepository(signedIn: true, email: 'test3@example.com'),
        introStore: InMemoryIntroStore(done: true, name: 'Sam'),
        localData: LocalDataGuard(
          // Recorded under Test 2; Test 3 has just signed in.
          owner: InMemoryLocalDataOwner('test-2'),
          data: _Training(),
        ),
        requestPermission: (_) async => true,
      ),
      pixelRatio: 2,
      drive: settle,
    );
  });
}

/// The deletion endpoint, answering [result].
class _Deletes implements AccountDeleter {
  const _Deletes([
    this.result = const AccountDeletionResult(accountDeleted: true),
  ]);

  final AccountDeletionResult result;

  @override
  Future<AccountDeletionResult> deleteAccount() async => result;
}

/// The deletion endpoint, refusing with [message].
class _Refuses implements AccountDeleter {
  const _Refuses(this.message);

  final String message;

  @override
  Future<AccountDeletionResult> deleteAccount() async =>
      throw AccountDeletionException(message);
}

/// Training on the phone, which [LocalDataGuard] asks about.
class _Training implements LocalRunnerData {
  bool _has = true;

  @override
  Future<bool> isEmpty() async => !_has;

  @override
  Future<void> eraseAll() async => _has = false;
}

/// No profile photo, without reaching for a file system path.
class _NoPhoto implements ProfilePhotoStore {
  const _NoPhoto();

  @override
  Future<File?> read() async => null;

  @override
  Future<File?> write(File source) async => null;

  @override
  Future<void> clear() async {}
}

/// Health, answered without HealthKit.
class _Health implements WorkoutSource {
  @override
  Future<bool> requestAccess() async => true;

  @override
  Future<List<HealthWorkout>> since(DateTime from) async =>
      const <HealthWorkout>[];
}
