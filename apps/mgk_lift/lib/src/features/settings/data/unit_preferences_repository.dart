import 'dart:async';

import '../domain/unit_preferences.dart';

/// The lifter's units, from wherever the best answer is.
///
/// Two stores with different strengths, composed rather than chosen between.
/// The device always has an answer and never needs a network; the account is
/// **shared with Run**, so a lifter who switches to pounds while running should
/// find pounds here too. Neither alone is right.
///
/// ## Who wins
///
/// The account, whenever it can speak. It is the only store that can carry a
/// choice made on another device or in the other app, so a cloud answer is by
/// definition at least as current as the local one, and adopting it writes it
/// back to the device so the next launch is instant.
///
/// The device wins only when the account says nothing — signed out, no row,
/// offline, or timed out. That is the case [UnitPreferencesStore] already
/// promised in writing ("a read that cannot reach the server falls back to the
/// last known choice") and which could not be kept while there was nowhere
/// local to fall back to.
///
/// ## Why the order is not the other way round
///
/// Reading local first and only consulting the cloud on a mismatch would be
/// faster and is wrong: with no local value — a fresh install by an existing
/// lifter, which is exactly the 2.0.0 upgrade path — it would show the default
/// and then have to correct itself visibly. [load] is not awaited by the shell,
/// so the cost of asking the account first is a late correction in the rare
/// offline case rather than a guaranteed flicker in the common one.
class UnitPreferencesRepository implements UnitPreferencesStore {
  UnitPreferencesRepository({required this.local, this.remote});

  /// The device. Always present, because the app runs without an account.
  final UnitPreferencesSource local;

  /// The account. Null when Supabase is unconfigured or unreachable at launch,
  /// which the whole app treats as "this device only" rather than as an error.
  final UnitPreferencesSource? remote;

  @override
  Future<UnitPreferences> load() async {
    final cloud = await remote?.fetch();
    if (cloud != null) {
      // Cache it, so the next launch answers from disk. Awaited rather than
      // fired off, because a caller that reads straight after loading should
      // not race the write that made the read correct.
      await local.save(cloud);
      return cloud;
    }
    return await local.fetch() ?? const UnitPreferences();
  }

  /// Writes both, device first.
  ///
  /// The device write is awaited and the account write is not. A unit that
  /// reached the phone but not the server is invisible to the lifter and
  /// reconciles on the next save or launch; the reverse — a spinner on a
  /// settings toggle because the network is slow — is not something anybody
  /// should wait for. [SupabaseUnitPreferences.save] already swallows its own
  /// failures for the same reason.
  @override
  Future<void> save(UnitPreferences prefs) async {
    await local.save(prefs);
    unawaited(remote?.save(prefs) ?? Future<void>.value());
  }
}
