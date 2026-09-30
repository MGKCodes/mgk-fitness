import 'package:flutter/widgets.dart';

import '../../coaching/data/purchase_client.dart';
import '../../onboarding/domain/intro_store.dart';
import '../domain/backup_consent.dart';
import '../domain/backup_health.dart';
import 'package:mgk_auth/mgk_auth.dart';

/// What belongs to the phone rather than to any screen: one of each, made once
/// in `main.dart` and shared by everything that reads or erases them.
///
/// **One of each is the point.** The backup answer, the push record and the
/// intro marker are files, and two stores over one file disagree silently.
/// They used to be built afresh on every rebuild of the app root, which was
/// harmless while nothing but the file held any state -- and stopped being
/// harmless when erasing the phone had to reach the same objects the app was
/// reading from.
class PhoneServices {
  const PhoneServices({
    required this.consent,
    required this.backupHealth,
    required this.intro,
    required this.localData,
    this.purchases,
  });

  final BackupConsentStore consent;
  final BackupHealthStore backupHealth;
  final IntroStore intro;

  /// Whose training is on the phone, and the only way to erase it.
  final LocalDataGuard localData;

  /// The store. Null in a build with no key, which cannot sell. One instance
  /// for the app, because it holds who it is attached to: the gate identifies
  /// and detaches it, and the account screens open its management page.
  final PurchaseClient? purchases;
}

/// Makes [PhoneServices] reachable from any route.
///
/// **Above the navigator, which is the whole reason it exists.** Deleting an
/// account is reached from two screens -- Account, and Privacy & legal -- and
/// has to reset the backup answer and offer to erase the phone from both. A
/// pushed route is not a descendant of the app root, so nothing threaded
/// through the shell can reach the second one; `main.dart` installs this in
/// `MaterialApp.builder`, where every route can find it.
///
/// Screens still take the same things as parameters, and a parameter wins.
/// This is where they look when nobody passed one.
class PhoneScope extends InheritedWidget {
  const PhoneScope({super.key, required this.phone, required super.child});

  final PhoneServices phone;

  /// The phone's services, or null in a build with no database -- the preview
  /// harness, and tests that did not install one.
  static PhoneServices? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PhoneScope>()?.phone;

  @override
  bool updateShouldNotify(PhoneScope oldWidget) =>
      !identical(phone, oldWidget.phone);
}
