import '../../onboarding/domain/intro_store.dart';
import '../domain/backup_consent.dart';
import '../domain/backup_health.dart';
import '../domain/local_data.dart';

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
  });

  final BackupConsentStore consent;
  final BackupHealthStore backupHealth;
  final IntroStore intro;

  /// Whose training is on the phone, and the only way to erase it.
  final LocalDataGuard localData;
}
