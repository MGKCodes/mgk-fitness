import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:mgk_auth/mgk_auth.dart';

import '../../../core/database/app_database.dart';
import '../../planning/data/cached_standing_plan_store.dart';

/// Everything on this phone that belongs to one lifter, so it can be asked
/// about and erased as one thing: the sessions and their sets, the saved
/// workouts, the progress photographs and the files they point at, and where
/// the last pull got to.
///
/// **Every table, not a list of them** — Run's rule, for Run's reason. The
/// database holds nothing but one lifter's training, so this reads and clears
/// [AppDatabase.allTables]; a table added later is covered the day it lands,
/// where a list would have to be remembered.
///
/// **What stays:** the units, the coach switch, the rest timer's settings and
/// the entitlement cache. They describe the install and its preferences, not
/// the person who used it, and the cache is corrected by the next account's
/// own answer.
///
/// Imports `dart:io`, so only `main.dart` constructs it.
class PhoneTrainingData implements LocalTrainingData {
  PhoneTrainingData(this._db, {PlanCache? plan}) : _plan = plan;

  final AppDatabase _db;

  /// The phone's copy of the account's live plan. Not training — it is only
  /// ever the server's last answer — but it is the account's, so it goes with
  /// the rest.
  final PlanCache? _plan;

  @override
  Future<bool> isEmpty() async {
    try {
      for (final table in _db.allTables) {
        // Where the last pull got to is bookkeeping about an account, not
        // training: it is erased with the rest, but on its own it is nobody's
        // sessions to protect.
        if (table is $SyncMetaTable) continue;
        final row = await (_db.select(table)..limit(1)).get();
        if (row.isNotEmpty) return false;
      }
      return true;
    } on Object {
      // A phone that cannot be read counts as holding something: the cost is a
      // question, where the other answer would hand somebody's training over.
      return false;
    }
  }

  @override
  Future<void> eraseAll() async {
    // Read before the rows go: they are the only record of where the files
    // are.
    final photos = await _db.select(_db.progressPhotos).get();

    // One transaction, so a failure leaves the training as it was rather than
    // half of it. Children first, which matters only if foreign keys are ever
    // switched on and costs nothing until then.
    await _db.transaction(() async {
      for (final table in _db.allTables.toList().reversed) {
        await _db.delete(table).go();
      }
    });

    await _plan?.clear();

    // The photographs themselves. A file left behind is a photograph of
    // somebody's body on a phone now signed in as somebody else, reachable by
    // nothing in the app but still there — so each is removed, and evicted
    // from the image cache, which holds decoded pictures by path.
    for (final photo in photos) {
      final file = File(photo.path);
      try {
        await FileImage(file).evict();
      } on Object {
        // Nothing cached, which is the outcome being asked for.
      }
      try {
        if (await file.exists()) await file.delete();
      } on Object {
        // The rows are gone and nothing can reach the file without them. Not
        // worth failing an erase the lifter is waiting on.
      }
    }
  }
}
