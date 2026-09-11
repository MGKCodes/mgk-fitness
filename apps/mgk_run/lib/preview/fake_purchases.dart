import '../src/features/coaching/data/entitlement_repository.dart';
import '../src/features/coaching/data/purchase_client.dart';
import '../src/features/coaching/domain/coach_access.dart';
import '../src/features/coaching/domain/coach_subscription.dart';
import '../src/features/coaching/domain/coach_offer.dart';

/// A shop with no store behind it.
///
/// The paywall is the one screen in the app that cannot be exercised on the
/// machine it is written on: it needs App Store Connect products, a sandbox
/// Apple ID and a device. This stands in for all three, so the *screen* can be
/// driven end to end in a widget test and drawn on the plate board, and the
/// only thing left for a device to prove is the payment itself.
///
/// The prices below are strings for the same reason the real ones are: the
/// store formats them, and a fake that returned numbers would let a bug through
/// that the real path would then hit in a currency nobody tested.
class FakePurchases implements PurchaseClient {
  FakePurchases({
    List<CoachOffer>? offers,
    this.buyOutcome = PurchaseOutcome.purchased,
    this.restoreOutcome = PurchaseOutcome.nothingToRestore,
  }) : _offers = offers ?? demoOffers;

  final List<CoachOffer> _offers;

  /// What [buy] answers. Set it to [PurchaseOutcome.cancelled] to draw the
  /// state a runner reaches most often after opening a paywall.
  final PurchaseOutcome buyOutcome;

  /// What [restore] answers.
  final PurchaseOutcome restoreOutcome;

  /// The user id [identify] was last given, or null. Tests assert on this
  /// because a purchase attached to the wrong id is a purchase the webhook
  /// refuses, and nothing about the payment itself looks wrong when it happens.
  String? identifiedAs;

  /// Every offer [buy] was called with, in order.
  final List<CoachOffer> bought = <CoachOffer>[];

  /// How many times [restore] was called.
  int restores = 0;

  /// The two tiers, priced as ADR-0029 settled them. **A fixture, not a
  /// source of truth** — the shipping app reads both figures off the
  /// storefront, and these exist so a plate has something to draw.
  static const List<CoachOffer> demoOffers = <CoachOffer>[
    CoachOffer(
      id: 'run.coach.monthly',
      title: 'Coach',
      description:
          'A training plan built around your running, and a coach that '
          'adjusts it every week.',
      price: '£0.99',
    ),
    CoachOffer(
      id: 'run.coach.premium.monthly',
      title: 'Premium Coach',
      description:
          'The same coach, thinking harder about your week. A better model '
          'behind every plan and every answer.',
      price: '£2.99',
    ),
  ];

  @override
  Future<void> identify(String userId) async => identifiedAs = userId;

  @override
  Future<List<CoachOffer>> offers() async => _offers;

  @override
  Future<PurchaseOutcome> buy(CoachOffer offer) async {
    bought.add(offer);
    return buyOutcome;
  }

  @override
  Future<PurchaseOutcome> restore() async {
    restores++;
    return restoreOutcome;
  }
}

/// A tier, answered without a network.
///
/// `SupabaseEntitlements` resolves to [CoachAccess.free] with no client, which
/// is right and is also indistinguishable from a bug. This says what it means,
/// so a plate of the paid product is evidence rather than coincidence.
class FakeEntitlements implements EntitlementRepository {
  /// The common case: say whether the coach is unlocked and let the tier
  /// follow from it.
  FakeEntitlements([CoachAccess answer = CoachAccess.free])
    : subscribed = answer.isSubscribed
          ? const CoachSubscription(
              tier: CoachTier.coach,
              standing: SubscriptionStanding.active,
            )
          : CoachSubscription.none;

  /// The case a boolean cannot express.
  ///
  /// Premium, and `grace`, are states the settings row draws differently and
  /// [CoachAccess] flattens — `grace` in particular is a locked coach that is
  /// **not** the free app, which is the whole reason [CoachSubscription]
  /// exists. A plate that wants to show one has to be able to say so.
  const FakeEntitlements.of(this.subscribed);

  final CoachSubscription subscribed;

  /// Derived, so a plate cannot draw an unlocked coach beside a row that says
  /// the payment failed.
  @override
  Future<CoachAccess> access() async =>
      subscribed.isSubscribed ? CoachAccess.subscribed : CoachAccess.free;

  @override
  Future<CoachSubscription> subscription() async => subscribed;
}
