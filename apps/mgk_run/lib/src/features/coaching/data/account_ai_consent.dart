import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/ai_consent.dart';

/// Where an account keeps its answer: auth user metadata, under
/// [kAiConsentMetadataKey].
///
/// A seam so [AccountAiConsent] can be tested without a gotrue session. The
/// real one is [SupabaseAiConsentAccount].
abstract interface class AiConsentAccount {
  /// Who is signed in, or null.
  String? get userId;

  /// The raw value stored on the signed-in account, or null.
  Object? get stored;

  /// Writes [value] to the signed-in account; null removes the key. Throws
  /// when it did not land.
  Future<void> store(Map<String, Object?>? value);
}

/// This phone's answers that the account has not received yet, by user id.
///
/// Implementations may throw; [AccountAiConsent] treats a failure as "nothing
/// here", which falls back to what the account says.
abstract interface class AiConsentCache {
  /// The entry kept for [userId], or null.
  Future<Map<String, Object?>?> read(String userId);

  /// Replaces the entry for [userId]; null removes it.
  Future<void> write(String userId, Map<String, Object?>? entry);
}

/// An [AiConsentCache] that lasts the session. The web build's default, and
/// the one tests use.
class InMemoryAiConsentCache implements AiConsentCache {
  final Map<String, Map<String, Object?>> _entries =
      <String, Map<String, Object?>>{};

  /// Set to make every call throw, as a full disk or a locked file would.
  Object? failure;

  @override
  Future<Map<String, Object?>?> read(String userId) async {
    final error = failure;
    if (error != null) throw error;
    return _entries[userId];
  }

  @override
  Future<void> write(String userId, Map<String, Object?>? entry) async {
    final error = failure;
    if (error != null) throw error;
    if (entry == null) {
      _entries.remove(userId);
    } else {
      _entries[userId] = entry;
    }
  }
}

/// The account side, read and written the way `run_intro_seen` is: off the
/// session's user for the read, `updateUser` for the write.
///
/// **The read costs no round trip.** gotrue keeps the user, metadata included,
/// in the persisted session, so the answer is there offline and at launch.
/// The price is that a withdrawal made on another phone arrives here with the
/// next session refresh rather than at once.
class SupabaseAiConsentAccount implements AiConsentAccount {
  const SupabaseAiConsentAccount({
    SupabaseClient? client,
    this.timeout = const Duration(seconds: 10),
  }) : _explicitClient = client;

  final SupabaseClient? _explicitClient;

  /// Bounds the write, as every other call on the auth path is bounded.
  final Duration timeout;

  /// Resolved per call, so building this does not need Supabase initialised.
  /// Null where it is not, which reads as nobody signed in.
  SupabaseClient? get _client {
    if (_explicitClient != null) return _explicitClient;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  String? get userId => _client?.auth.currentUser?.id;

  @override
  Object? get stored =>
      _client?.auth.currentUser?.userMetadata?[kAiConsentMetadataKey];

  @override
  Future<void> store(Map<String, Object?>? value) async {
    final client = _client;
    if (client == null) throw StateError('Supabase is not initialised');
    // Merged into the metadata by gotrue: only this key changes, and null
    // removes it, which is how `updateName` clears a name.
    await client.auth
        .updateUser(
          UserAttributes(data: <String, dynamic>{kAiConsentMetadataKey: value}),
        )
        .timeout(timeout);
  }
}

/// The real [AiConsentStore]: the account holds the answer, and the phone
/// holds any answer the account has not received yet.
///
/// ## Why the cache holds only what is pending
///
/// The obvious version keeps a full local copy and reads "account or phone".
/// It gets both directions of a withdrawal wrong. Withdraw offline and the
/// account still says yes, so the coach keeps sending; withdraw on another
/// phone and this one's copy still says yes, forever.
///
/// So every decision goes to the phone first, which makes it true on this
/// phone at once, online or not, and then to the account. When the account has
/// it, the phone's entry is removed and the account is the answer again,
/// which is what lets a withdrawal made elsewhere arrive here. Until then the
/// phone's entry wins, and each read tries the account again.
///
/// Keyed by user id throughout, so an answer never carries to another
/// account on the same phone.
class AccountAiConsent implements AiConsentStore {
  AccountAiConsent({
    required AiConsentAccount account,
    required AiConsentCache cache,
    DateTime Function()? now,
  }) : _account = account,
       _cache = cache,
       _now = now ?? DateTime.now;

  final AiConsentAccount _account;
  final AiConsentCache _cache;
  final DateTime Function() _now;

  @override
  Future<bool> isGranted() async {
    try {
      final id = _account.userId;
      if (id == null) return false;
      final pending = AiConsent.fromJson(await _readCache(id));
      if (pending != null) {
        // Not awaited: the answer is already known, and a coach request should
        // not wait on a metadata write to find it out.
        unawaited(_sync(id, pending));
        return pending.isCurrent;
      }
      return AiConsent.fromJson(_account.stored)?.isCurrent ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> grant() => _decide(AiConsent.now(_now()));

  @override
  Future<void> withdraw() => _decide(AiConsent.withdrawn(_now()));

  /// Writes [answer] to the phone, then the account.
  ///
  /// Throws [AiConsentNotSaved] only when it landed in neither, which is the
  /// one outcome where the runner has to be told their answer did not count.
  Future<void> _decide(AiConsent answer) async {
    final id = _account.userId;
    if (id == null) return;
    var kept = false;
    try {
      await _cache.write(id, answer.toJson());
      kept = true;
    } catch (_) {
      // The account may still take it.
    }
    final synced = await _sync(id, answer);
    if (!kept && !synced) throw const AiConsentNotSaved();
  }

  /// Puts [answer] on the account and, once it is there, drops the phone's
  /// copy. Returns whether the account has it.
  Future<bool> _sync(String id, AiConsent answer) async {
    try {
      // Somebody else signed in while this was queued: their account is not
      // the one this answer belongs to.
      if (_account.userId != id) return false;
      await _account.store(answer.isWithdrawal ? null : answer.toJson());
    } catch (_) {
      // Stays on the phone, and the next read tries again.
      return false;
    }
    try {
      // Only if nothing newer was decided while the write was in flight.
      final current = AiConsent.fromJson(await _cache.read(id));
      if (current == answer) await _cache.write(id, null);
    } catch (_) {
      // A stale entry is re-sent and then dropped at the next read.
    }
    return true;
  }

  Future<Map<String, Object?>?> _readCache(String id) async {
    try {
      return await _cache.read(id);
    } catch (_) {
      return null;
    }
  }
}

/// An answer that reached neither the phone nor the account.
class AiConsentNotSaved implements Exception {
  const AiConsentNotSaved();

  @override
  String toString() => 'AiConsentNotSaved';
}
