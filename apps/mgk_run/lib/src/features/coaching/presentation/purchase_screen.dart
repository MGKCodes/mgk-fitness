import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/brand.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/sign_in_screen.dart';
import '../../legal/domain/legal_urls.dart';
import '../../legal/presentation/privacy_policy_screen.dart';
import '../data/entitlement_repository.dart';
import '../data/purchase_client.dart';
import '../domain/coach_access.dart';
import '../domain/coach_offer.dart';

/// Re-exported so that importing this screen still yields [kTermsOfUseUrl].
/// The constant moved to `legal/domain/legal_urls.dart` when Settings gained
/// the same link: a legal document should not live inside the paywall.
export '../../legal/domain/legal_urls.dart' show kTermsOfUseUrl;

/// The store's names and the renewal disclosure moved into mgk_ui, which both
/// apps sell through; re-exported so everything that read them from here still
/// does.
export 'package:mgk_ui/mgk_ui.dart'
    show storeName, storeAccountName, renewalWording;

/// Where the coach is actually bought.
///
/// **Guideline 3.1.2 decides most of this screen's contents**, and it is worth
/// naming the requirements rather than discovering them in a rejection: an
/// auto-renewing subscription's purchase surface must carry the price and
/// duration, a functional link to the **Terms of Use** and to the **privacy
/// policy**, and a way to **restore** a purchase without buying anything first.
/// All four are below, and `purchase_screen_test.dart` asserts each one.
///
/// **No price is compiled in.** Every figure on screen arrives from the
/// storefront through [CoachOffer.price], already formatted in the runner's own
/// currency. The two numbers ADR-0029 settled live in `plan_gate_copy.dart` as
/// the record `limits.ts` is sized against, and are shown to nobody.
class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({
    super.key,
    required this.purchases,
    required this.entitlements,
    this.auth = const AuthRepository(),
  });

  /// Presents and performs. It is never asked what the runner owns.
  final PurchaseClient purchases;

  /// Where signing in happens when a purchase is refused for want of an
  /// account. The screen is reachable signed out -- the coach mark opens the
  /// gate for anybody -- and "sign in first" with no way to do it was a dead
  /// end at the moment somebody had decided to pay.
  final AuthRepository auth;

  /// The server's answer, which is the only one that counts
  /// ([ADR-0030](../../../../docs/decisions/0030-the-coach-is-the-paid-half.md)).
  final EntitlementRepository entitlements;

  /// Opens the screen. Answers true when the coach actually came unlocked, so
  /// the caller can refresh rather than guess.
  static Future<bool> show(
    BuildContext context, {
    required PurchaseClient purchases,
    required EntitlementRepository entitlements,
    AuthRepository auth = const AuthRepository(),
  }) async {
    final bool? unlocked = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PurchaseScreen(
          purchases: purchases,
          entitlements: entitlements,
          auth: auth,
        ),
      ),
    );
    return unlocked ?? false;
  }

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  /// How long to keep asking the server whether the purchase has landed.
  ///
  /// **The app and the webhook race, and the app usually wins.** RevenueCat
  /// tells our Edge Function server-to-server while the store's sheet is
  /// already dismissing, so reading `core.entitlements` once and reporting the
  /// result would report a failure that is really a timing difference. Roughly
  /// eleven seconds of asking, then a sentence that says the payment worked and
  /// the unlock is on its way, because that is what is true.
  static const List<Duration> _waits = <Duration>[
    Duration.zero,
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
  ];

  /// What to call the store this runner is actually buying from.
  ///
  /// Every sentence on this screen named Apple until 2026-09-11, when it was
  /// opened on Android and told a Play customer their **Apple ID** would be
  /// charged, that no subscription was found on their **Apple ID**, and that we
  /// could not reach the **App Store**. All three were false and all three sat
  /// within a tap of a payment.
  ///
  /// Two names rather than one, because they are not interchangeable: a person
  /// has an Apple ID or a Google Play account, and the shop is the App Store or
  /// Google Play.
  static String get _account => storeAccountName(defaultTargetPlatform);

  static String get _store => storeName(defaultTargetPlatform);

  /// What the store sells, once it has said. Empty until then, and empty for
  /// good when it had nothing to offer or could not be asked.
  List<CoachOffer> _offers = const <CoachOffer>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    List<CoachOffer> offers;
    try {
      offers = await widget.purchases.offers();
    } on Object {
      offers = const <CoachOffer>[];
    }
    if (!mounted) return;
    setState(() {
      _offers = offers;
      _loading = false;
    });
  }

  String? _busyId;
  bool _restoring = false;
  String? _note;

  /// Whether the last refusal was for want of an account, which is what puts
  /// a way to sign in under the note.
  bool _needsAccount = false;

  Future<void> _buy(CoachOffer offer) async {
    setState(() {
      _busyId = offer.id;
      _note = null;
      _needsAccount = false;
    });
    final PurchaseOutcome outcome = await widget.purchases.buy(offer);
    if (!mounted) return;
    switch (outcome) {
      case PurchaseOutcome.purchased:
        await _settle();
      case PurchaseOutcome.cancelled:
        // Not an error. Somebody decided not to buy, and they know they did.
        setState(() => _busyId = null);
      case PurchaseOutcome.notIdentified:
        // Refused before the store was reached, so this is not a failed
        // payment and must not read as one. Signing in is the actual fix, and
        // saying so beats a retry that would refuse again.
        setState(() {
          _busyId = null;
          _needsAccount = true;
          _note =
              'Sign in first, then try again. A subscription has to be '
              'attached to an account or it cannot reach your coach. '
              'Nothing has been charged.';
        });
      // **Each of these used to read "That did not go through. Nothing has
      // been charged."** Two of them were claims about money the app cannot
      // make: a pending payment may well be charged, and a connection that
      // dropped mid-purchase does not say where the purchase got to. And a
      // runner who already owns the subscription was sent to buy it again.
      case PurchaseOutcome.pending:
        setState(() {
          _busyId = null;
          _note =
              'Your payment is pending with $_store. The coach unlocks when '
              'it completes.';
        });
      case PurchaseOutcome.offline:
        setState(() {
          _busyId = null;
          _note = _offline;
        });
      case PurchaseOutcome.alreadyOwned:
        setState(() {
          _busyId = null;
          _note =
              'This $_account already has a subscription. Tap Restore '
              'purchases.';
        });
      case PurchaseOutcome.nothingToRestore:
      case PurchaseOutcome.failed:
        setState(() {
          _busyId = null;
          _note = 'That did not go through. Try again in a moment.';
        });
    }
  }

  static const String _offline =
      "No connection — try again when you're online.";

  Future<void> _restore() async {
    setState(() {
      _restoring = true;
      _note = null;
      _needsAccount = false;
    });
    final PurchaseOutcome outcome = await widget.purchases.restore();
    if (!mounted) return;
    switch (outcome) {
      case PurchaseOutcome.purchased:
        await _settle(restored: true);
      case PurchaseOutcome.nothingToRestore:
        setState(() {
          _restoring = false;
          _note = 'No previous subscription found on this $_account.';
        });
      case PurchaseOutcome.notIdentified:
        // Refused before the store, like a purchase: a subscription restored
        // to nobody -- or to whoever signed in last -- reaches no coach.
        setState(() {
          _restoring = false;
          _needsAccount = true;
          _note =
              'Sign in first, then restore. A subscription belongs to an '
              'account, so it has to be restored to one.';
        });
      case PurchaseOutcome.offline:
        setState(() {
          _restoring = false;
          _note = _offline;
        });
      case PurchaseOutcome.pending:
        setState(() {
          _restoring = false;
          _note =
              'Your payment is pending with $_store. The coach unlocks when '
              'it completes.';
        });
      // "Could not reach the store" was said of every one of these, most of
      // which reached it.
      case PurchaseOutcome.cancelled:
      case PurchaseOutcome.alreadyOwned:
      case PurchaseOutcome.failed:
        setState(() {
          _restoring = false;
          _note = 'Restoring did not work. Try again in a moment.';
        });
    }
  }

  /// Signs in from here, so a refusal for want of an account has a way
  /// forward on the same screen.
  ///
  /// Identifies the store straight away rather than waiting for the shell to
  /// hear the sign-in: the runner's next tap is Subscribe again, and it should
  /// find the account already attached.
  Future<void> _signIn() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => SignInScreen(
          auth: widget.auth,
          onBack: () => Navigator.of(routeContext).maybePop(),
          onAuthenticated: () => Navigator.of(routeContext).maybePop(),
        ),
      ),
    );
    if (!mounted) return;
    final String? id = widget.auth.currentUserId;
    if (id == null) return;
    await widget.purchases.identify(id);
    if (!mounted) return;
    setState(() {
      _needsAccount = false;
      _note = null;
    });
  }

  /// Waits for the server to agree, then leaves.
  ///
  /// [restored] is whether this follows a restore rather than a payment, which
  /// changes the one sentence it may end on: a restore moved no money, and
  /// "Payment went through" after one reads as a second charge.
  Future<void> _settle({bool restored = false}) async {
    for (final Duration wait in _waits) {
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      if (!mounted) return;
      final CoachAccess access = await widget.entitlements.access();
      if (!mounted) return;
      if (access.isSubscribed) {
        Navigator.of(context).pop(true);
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _busyId = null;
      _restoring = false;
      // True, and deliberately not an apology. The money moved; the row has
      // not arrived yet. Saying "something went wrong" here would invite a
      // second purchase.
      _note = restored
          ? 'Restored. The coach can take a minute to unlock.'
          : 'Payment went through. The coach can take a minute to unlock, and '
                'will be there next time you open the app.';
    });
  }

  Future<void> _openTerms() async {
    final Uri uri = Uri.parse(kTermsOfUseUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      setState(() => _note = 'Could not open the terms. They are at $uri');
    }
  }

  /// What the subscription adds, one row per thing that ships: a few words to
  /// scan, and the sentence behind them a tap away (the paywall research of 4
  /// October 2026). Lift's paywall says the same of its own coach.
  static const List<PaywallBenefit> _benefits = <PaywallBenefit>[
    // The plan generator, from the coach's questions (ADR-0011, ADR-0027).
    PaywallBenefit(
      icon: Icons.event_note_outlined,
      title: 'Your own training plan',
      detail:
          'A plan built around your goal or race and the days you can run, '
          'from the week you start to the day it ends.',
    ),
    // The conversation, which reads the plan and the recent runs.
    PaywallBenefit(
      icon: Icons.forum_outlined,
      title: 'A coach on call',
      detail:
          'Ask about any run, any time. The coach reads your plan and your '
          'recent runs before it answers.',
    ),
    // The weekly check against what was run, and Adjust this week.
    PaywallBenefit(
      icon: Icons.trending_up,
      title: 'Plan adjusts weekly',
      detail:
          'Each week is checked against what you actually ran, and the plan '
          'adjusts to match.',
    ),
  ];

  /// What sets a tier apart, in a line. Premium has a better model and three
  /// times the monthly coaching allowance (limits.ts: `monthly_spend` 1.92
  /// against 0.64), said as an amount for Guideline 3.1.2(c) (ADR-0041).
  static String _line(CoachOffer offer) => offer.id.contains('premium')
      ? '3× the coaching, sharper model'
      : 'Everything above';

  @override
  Widget build(BuildContext context) {
    final bool busy = _busyId != null || _restoring;
    CoachOffer? offerFor(String id) {
      for (final CoachOffer offer in _offers) {
        if (offer.id == id) return offer;
      }
      return null;
    }

    return CoachPaywall(
      appIcon: const AssetImage('assets/images/brand/app_icon.png'),
      appName: kProductName,
      // The night road, as the coach sheet and the sign-in show it. The
      // paywall shows only the top third of its photograph, and this one has
      // lamps and trees there where the two fog photographs have grey
      // (5 October 2026).
      photo: 'assets/images/backgrounds/summary.jpg',
      headline: 'A plan that adjusts, and a coach to ask',
      benefits: _benefits,
      tiers: <PaywallTier>[
        for (final CoachOffer offer in _offers)
          PaywallTier(
            id: offer.id,
            name: offer.title,
            // Straight from the storefront, already formatted. The month is
            // ours to say because every product is monthly; the figure never
            // is.
            price: offer.price,
            period: 'month',
            line: _line(offer),
            // The tier the screen opens on, and the one to start with: the
            // cheap first step, which upgrades on the day it is outgrown.
            recommended: !offer.id.contains('premium'),
          ),
      ],
      loading: _loading,
      busyTierId: _busyId,
      restoring: _restoring,
      note: _note,
      // A refusal for want of an account, answered on the same screen.
      noteAction: _needsAccount
          ? AppTextButton(label: 'Sign in', onPressed: busy ? null : _signIn)
          : null,
      platform: defaultTargetPlatform,
      nothingToSell:
          'Everything you record stays free and stays yours in the meantime.',
      onSubscribe: busy
          ? null
          : (PaywallTier tier) {
              final CoachOffer? offer = offerFor(tier.id);
              if (offer != null) unawaited(_buy(offer));
            },
      onRestore: busy ? null : () => unawaited(_restore()),
      onClose: busy ? null : () => Navigator.of(context).maybePop(),
      onTerms: () => unawaited(_openTerms()),
      onPrivacy: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyScreen()),
      ),
    );
  }
}
