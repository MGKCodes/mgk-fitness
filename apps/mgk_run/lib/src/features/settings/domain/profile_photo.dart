import 'dart:io';

import 'package:flutter/widgets.dart';

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
/// ## A new phone gets no photo
///
/// The cost of the rule: sign in on a new phone and the avatar is the initials
/// again. That is the right trade — a face is the most identifying thing the
/// app could hold, and holding it on one device that its owner controls is
/// worth more than the convenience of it following them.
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

/// What to draw when there is no photo.
///
/// Initials where a name was given, and the generic mark where none was. The
/// intro accepts any name and accepts none, so both are ordinary states rather
/// than one being a failure of the other.
///
/// **At most two characters, from at most two words.** A long name reduced to
/// four initials is unreadable in a 40px circle, and a single character is
/// enough for most people. Non-Latin scripts fall through the same path: the
/// first character of each of the first two words, whatever those characters
/// are.
String? initialsFor(String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return null;
  final picked = words.take(2).map((w) => w.characters).toList();
  return picked.map((c) => c.first).join().toUpperCase();
}
