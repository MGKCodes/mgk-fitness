import 'dart:io';

export 'package:mgk_ui/mgk_ui.dart' show initialsFor;

/// The profile photo, which lives on this phone and nowhere else.
///
/// ## The one rule
///
/// **It is never uploaded.** Not to the backup, not to the coach, not to
/// anything. That is not squeamishness — it is what keeps the store
/// declarations true. Both Apple and Google define *collected* as transmitted
/// off the device, so a local-only avatar leaves App Privacy on "Data Not
/// Collected" and leaves Play's Data safety form untouched. The moment it syncs,
/// both of those become false and the listings need changing.
///
/// So it is deliberately not part of `BackupMirror`, not a column anywhere in
/// Drift, and not in the sweep `delete-account` runs. It is a file, and
/// [clear] is what removes it.
///
/// ## A new phone gets no photo from us
///
/// The cost of the rule: sign in on a new phone and the avatar is the initials
/// again. That is the right trade — a face is the most identifying thing the
/// app could hold, and holding it on one device that its owner controls is
/// worth more than the convenience of it following them.
///
/// **The phone's own backup is another matter, and nothing opts out of it.**
/// The file sits in the documents directory, which iCloud and Android backup
/// both carry, so a phone restored from a backup can arrive with the photo.
/// That backup is the owner's rather than a collection, and the copy that
/// promised "not included in backup" was corrected on 2026-09-29 rather than
/// the file being excluded.
abstract class ProfilePhotoStore {
  /// The stored photo, or null if there is none. The file is guaranteed to
  /// exist when non-null.
  Future<File?> read();

  /// Copies [source] into the app's own storage and returns the stored file.
  ///
  /// A copy rather than a reference: the picker hands back a path in a cache
  /// the system is free to empty, so keeping the path would give an avatar
  /// that vanishes on its own schedule.
  Future<File?> write(File source);

  /// Removes it. Safe to call when there is nothing stored.
  Future<void> clear();
}

// What to draw when there is no photo is `initialsFor`, which moved to `mgk_ui`
// with the avatar's fallback when Lift's Settings took the same profile card.
// Exported from here so the photo and its fallback are still found together.
