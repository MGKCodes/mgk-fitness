import 'package:flutter/painting.dart';

import '../../../core/database/app_database.dart';
import '../../onboarding/domain/intro_store.dart';
import '../domain/backup_consent.dart';
import '../domain/backup_health.dart';
import '../domain/local_data.dart';
import '../domain/profile_photo.dart';

/// Everything on this phone that belongs to a runner, in one place, so it can
/// be asked about and erased as one thing.
///
/// **Every table, not a list of them.** The database holds nothing but one
/// runner's training -- runs and their points, splits and records, plans and
/// the profile inside them, the coach's conversations and summary -- so this
/// reads and clears [AppDatabase.allTables] rather than naming them. A table
/// added next week is covered the day it lands, where a list would have to be
/// remembered, and forgetting it would leave one runner's data on a phone
/// handed to another.
///
/// Beside the database: the profile photo, the name the coach uses, the backup
/// answer and the record of the last push. The medical-disclaimer marker, the
/// intro marker and the distance unit stay -- they describe the install and a
/// display preference, not the person who used it.
class PhoneRunnerData implements LocalRunnerData {
  PhoneRunnerData({
    required AppDatabase db,
    required ProfilePhotoStore photo,
    required IntroStore intro,
    required BackupConsentStore consent,
    required BackupHealthStore backupHealth,
  }) : _db = db,
       _photo = photo,
       _intro = intro,
       _consent = consent,
       _backupHealth = backupHealth;

  final AppDatabase _db;
  final ProfilePhotoStore _photo;
  final IntroStore _intro;
  final BackupConsentStore _consent;
  final BackupHealthStore _backupHealth;

  @override
  Future<bool> isEmpty() async {
    try {
      for (final table in _db.allTables) {
        final row = await (_db.select(table)..limit(1)).get();
        if (row.isNotEmpty) return false;
      }
      if (await _photo.read() != null) return false;
      if (await _intro.readName() != null) return false;
      return true;
    } on Object {
      // A phone that cannot be read counts as holding something: the cost is a
      // question, where the other answer would hand somebody's training over.
      return false;
    }
  }

  @override
  Future<void> eraseAll() async {
    // One transaction, so a failure leaves the training as it was rather than
    // half of it. Children first -- the tables are declared parents first --
    // which matters only if foreign keys are ever switched on, and costs
    // nothing until then.
    await _db.transaction(() async {
      for (final table in _db.allTables.toList().reversed) {
        await _db.delete(table).go();
      }
    });

    // The photo keeps one path for the life of the install and Flutter caches
    // images by path, so the next photo anybody picks would draw as this one.
    final photo = await _photo.read();
    if (photo != null) {
      try {
        await FileImage(photo).evict();
      } on Object {
        // No image cache to hold it, which is the outcome being asked for.
      }
    }
    await _photo.clear();
    await _intro.writeName(null);
    await _consent.write(BackupConsent.unknown);
    await _backupHealth.write(const BackupHealth());
  }
}
