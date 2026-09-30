import 'package:meta/meta.dart';

/// What the account has paid for, in this app.
///
/// ## Why this exists at all
///
/// `LiftShell.isEntitled` has carried the doc comment *"Read from
/// `core.entitlements`"* since it was added, and until 2026-09-02 nothing read
/// it. `main.dart` never passed the flag, so it took its `false` default and
/// **every account in production was unentitled as far as the app was
/// concerned** — including the one holding `lift` / `paid` / `active`. The
/// server knew; the screen did not. The coach worked when probed directly and
/// the Plan surface still showed the pitch.
///
/// That is the failure this file exists to close, and it is worth naming
/// precisely: not a bug in the gate, an absence of one. A purchase flow built
/// on top of nothing would have taken money and changed no screen.
enum EntitlementTier {
  free,
  paid,
  premium;

  /// The `product` values `core.entitlements` allows. Parsing is total: an
  /// unknown string is [free] rather than an exception, because a tier this
  /// client has never heard of must not be able to crash a launch — a server
  /// that grows a tier is a deployment, not a client release.
  static EntitlementTier parse(String? value) => switch (value) {
    'paid' => EntitlementTier.paid,
    'premium' => EntitlementTier.premium,
    _ => EntitlementTier.free,
  };

  /// What the tier is called on screen, and the **only** way the app should
  /// name one.
  ///
  /// A tier is named, never priced. `£1` and `£3` were used as identity in the
  /// paywall, the button and the plan — which is wrong twice over: the store
  /// localises price and currency per territory, so a hardcoded `£` is simply
  /// incorrect for most of the world; and a price that appears in copy has to
  /// be found and changed everywhere the day it moves, which is the day nobody
  /// remembers where it all is.
  ///
  /// Prices come from [PurchaseOffer], which gets them from the store. This is
  /// the name.
  String get label => switch (this) {
    EntitlementTier.free => 'Free',
    EntitlementTier.paid => 'Coach',
    EntitlementTier.premium => 'Premium Coach',
  };
}

/// One row of `core.entitlements`, for this app and this person.
@immutable
class Entitlement {
  const Entitlement({required this.tier, required this.status, this.expiresAt});

  /// Nobody has paid. The honest answer for an account with no row, which is
  /// most of them.
  static const Entitlement none = Entitlement(
    tier: EntitlementTier.free,
    status: 'active',
  );

  final EntitlementTier tier;

  /// The store-reported state, kept as the server's own string rather than an
  /// enum. The set is `active | expired | grace | refunded | revoked`, and this
  /// client's only job is to recognise one of them — narrowing it here would
  /// mean a client release every time a new state appears.
  final String status;

  final DateTime? expiresAt;

  /// Whether the paid half should be shown.
  ///
  /// **`active` and nothing else**, which is the rule the table itself states:
  /// *"`active` is the only value that grants anything; treat every other value
  /// as no entitlement."*
  ///
  /// `grace` is the one worth revisiting when RevenueCat lands, and it is left
  /// alone deliberately rather than forgotten. Grace means "billing failed and
  /// we are retrying" — the store's intent is that access continues, so
  /// honouring the rule as written will read to that person as being cut off
  /// for a card that expired. The decision belongs with the webhook that starts
  /// producing the value, not with this file guessing ahead of it.
  bool get grantsPaid => status == 'active' && tier != EntitlementTier.free;
}

/// Where an entitlement is read from.
///
/// Deliberately mirrors `UnitPreferencesSource`: **null means "cannot say"**,
/// and covers signed out, no row, timed out and failed without distinguishing
/// them, because a caller can act on only the thing they share. It does *not*
/// mean "not entitled" — that is [Entitlement.none], which is a different
/// answer and is why this returns a nullable rather than defaulting.
abstract interface class EntitlementSource {
  Future<Entitlement?> fetch();
}

/// The last answer this device was given.
///
/// Exists so an offline paying customer is not shown a paywall. Without it,
/// "cannot say" collapses into "has not paid" the moment a train goes into a
/// tunnel, and the person who is paying is the one who sees the pitch.
///
/// Safe to keep on the device because it decides **presentation only**. The
/// coach Edge Function re-reads `core.entitlements` under `service_role` before
/// it spends anything, so a device that lies to itself gets a nicer-looking app
/// and no free inference.
abstract interface class EntitlementCache {
  /// What this device last knew, or null if it has never been told.
  Future<bool?> lastKnownPaid();

  Future<void> remember({required bool paid});

  /// **Called on sign-out.** Without it the next person to sign in on this
  /// device inherits the previous account's paid screens until the first fetch
  /// returns, which is both wrong and the kind of wrong that looks like a
  /// purchase bug.
  Future<void> forget();
}

/// Resolves what the app should show, from a source that may not answer.
///
/// The order is the whole point: a live answer beats a remembered one, a
/// remembered one beats nothing, and nothing means the free half. Fail-closed
/// at the end rather than fail-open, because the last case is a device that has
/// never once been told this account pays.
class EntitlementGate {
  const EntitlementGate({required this.source, this.cache});

  final EntitlementSource source;
  final EntitlementCache? cache;

  /// Drops what this device remembers. Called on sign-out, so the next person
  /// to sign in here does not inherit the previous account's paid screens
  /// while the first fetch is still in flight.
  Future<void> forget() async => cache?.forget();

  Future<bool> isEntitled() async {
    final live = await source.fetch();
    if (live != null) {
      final paid = live.grantsPaid;
      await cache?.remember(paid: paid);
      return paid;
    }
    return await cache?.lastKnownPaid() ?? false;
  }
}

/// A fixed answer, for tests and the preview.
class FakeEntitlements implements EntitlementSource {
  FakeEntitlements(this.entitlement);

  /// Null reproduces "cannot say", which is the case worth exercising and the
  /// one a fake that only models yes/no would hide.
  Entitlement? entitlement;

  @override
  Future<Entitlement?> fetch() async => entitlement;
}

/// Remembers for the session only.
class InMemoryEntitlementCache implements EntitlementCache {
  InMemoryEntitlementCache({bool? paid}) : _paid = paid;

  bool? _paid;

  @override
  Future<bool?> lastKnownPaid() async => _paid;

  @override
  Future<void> remember({required bool paid}) async => _paid = paid;

  @override
  Future<void> forget() async => _paid = null;
}
