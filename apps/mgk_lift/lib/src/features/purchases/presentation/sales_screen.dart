import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../../core/brand.dart';
import '../../auth/domain/account.dart';
import '../../auth/presentation/sign_in_screen.dart';
import '../../entitlement/domain/entitlement.dart';
import '../../legal/domain/legal_copy.dart';
import '../../legal/presentation/legal_document_screen.dart';
import '../domain/purchases.dart';

/// Where the coach is sold: one screen, reached from every door (R6).
///
/// **It replaced a sheet, and the three places that each sold differently.**
/// The C sent a signed-out lifter to sign in and an unsubscribed one to the
/// Plan tab; Plan's empty state was a pitch with a price table; Photos had its
/// own. Now the C wherever it is, Plan's button and Photos' button all open
/// this, and it returns what happened so the door can open onto what was just
/// bought.
///
/// **Drawn by the suite's [CoachPaywall]** (4 October 2026), the same screen
/// Run sells through: Lift's icon and name where the decision is made, four
/// benefits to scan, the two tiers side by side, and one button that buys the
/// one chosen, on one screen that does not scroll. This file keeps what is
/// Lift's: the words, and the purchase itself.
///
/// **It promises only what ships.** Each benefit below is one thing the coach
/// function or the app actually does, and names it in a comment. The plan's
/// pitch once promised to move Thursday's session when a shoulder was sore,
/// which nothing in the app can do, and that the coach saw your running, which
/// it does not; neither is repeated here.
///
/// **Signed out, the offer shows in full.** Choosing a tier asks for the
/// account — Apple, Google or email — and then goes on to the store, because a
/// purchase must belong to an account: the webhook keys the entitlement on it.
///
/// **Guideline 3.1.2 decides the foot of it**: each tier's title, length and
/// price; the renewal terms in the store's own words; working links to the
/// terms of use and the privacy policy; and Restore, without buying anything
/// first.
///
/// Returns the [PurchaseResult] when something changed — bought, restored, or
/// paid and waiting — and null when it was closed.
class SalesScreen extends StatefulWidget {
  const SalesScreen({
    super.key,
    required this.flow,
    this.offers = const <PurchaseOffer>[],
    this.auth,
    this.platform,
  });

  final PurchaseFlow flow;

  /// What the shell already knows the store sells, so the screen opens priced
  /// rather than on a spinner. Asked again on open either way.
  final List<PurchaseOffer> offers;

  /// Where to sign in when a tier is chosen signed out. Null is a build with
  /// no account system, which treats everybody as able to buy.
  final AuthService? auth;

  /// Which store's words to use. Injected for tests; the device's otherwise.
  final TargetPlatform? platform;

  static Future<PurchaseResult?> open(
    BuildContext context, {
    required PurchaseFlow flow,
    List<PurchaseOffer> offers = const <PurchaseOffer>[],
    AuthService? auth,
  }) => Navigator.of(context).push<PurchaseResult>(
    MaterialPageRoute<PurchaseResult>(
      builder: (_) => SalesScreen(flow: flow, offers: offers, auth: auth),
    ),
  );

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  late List<PurchaseOffer> _offers = widget.offers;
  late bool _loading = widget.offers.isEmpty;
  EntitlementTier? _buying;
  bool _restoring = false;
  String? _note;

  TargetPlatform get _platform => widget.platform ?? defaultTargetPlatform;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    List<PurchaseOffer> offers;
    try {
      offers = await widget.flow.purchases.offers();
    } on Object {
      offers = const <PurchaseOffer>[];
    }
    if (!mounted) return;
    setState(() {
      // A store that answered with nothing does not erase what was already
      // known: the shell's copy came from the same store a moment ago.
      if (offers.isNotEmpty) _offers = offers;
      _loading = false;
    });
  }

  bool get _busy => _buying != null || _restoring;

  Future<void> _choose(PurchaseOffer offer) async {
    if (_busy) return;
    setState(() {
      _buying = offer.tier;
      _note = null;
    });
    // Signed out, the account comes first: Apple, Google or email, on the
    // screen built for it. Nothing is charged until it exists. The email
    // form starts on making one: somebody subscribing is more likely new than
    // returning, and it is one tap to sign in instead.
    final auth = widget.auth;
    if (auth != null && auth.current == null) {
      final signedIn = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => SignInScreen(auth: auth, initialSignUp: true),
        ),
      );
      if (!mounted) return;
      final account = auth.current;
      if (signedIn != true || account == null) {
        setState(() => _buying = null);
        return;
      }
      // Told here rather than left to the shell's listener: the purchase is
      // the next thing that happens, and it must find the account attached.
      await widget.flow.purchases.identify(account.id);
      if (!mounted) return;
    }
    final result = await widget.flow.buy(offer);
    if (!mounted) return;
    _settle(result, restoring: false);
  }

  Future<void> _restore() async {
    setState(() {
      _restoring = true;
      _note = null;
    });
    final result = await widget.flow.restore();
    if (!mounted) return;
    _settle(result, restoring: true);
  }

  void _settle(PurchaseResult result, {required bool restoring}) {
    switch (result.status) {
      case PurchaseStatus.entitled:
      case PurchaseStatus.pending:
        // Something changed. The door says what, and opens onto it.
        Navigator.of(context).pop(result);
      case PurchaseStatus.cancelled:
        // Backing out of the store's sheet is a decision, not an error.
        setState(() {
          _buying = null;
          _restoring = false;
        });
      case PurchaseStatus.notSignedIn:
        setState(() {
          _buying = null;
          _restoring = false;
          _note =
              'Sign in first, then try again. A subscription belongs to your '
              'account, which is how it reaches your coach and follows you to '
              'a new phone. Nothing has been charged.';
        });
      case PurchaseStatus.nothingToRestore:
        setState(() {
          _buying = null;
          _restoring = false;
          _note =
              'There is no Lift subscription on this '
              '${storeAccountName(_platform)} to restore.';
        });
      case PurchaseStatus.failed:
        setState(() {
          _buying = null;
          _restoring = false;
          _note = restoring
              ? 'Could not reach ${storeName(_platform)}. Try again in a '
                    'moment.'
              : result.message ??
                    'That did not go through. Nothing has been charged.';
        });
    }
  }

  void _open(Widget screen) => unawaited(
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)),
  );

  /// What the subscription adds, **one row per thing that ships**, each with
  /// the code it rests on. A few words to scan, and the sentence behind them a
  /// tap away (the paywall research of 4 October 2026). Nothing here moves a
  /// planned session or reads Run, because nothing in the app does.
  static const List<PaywallBenefit> _benefits = <PaywallBenefit>[
    // lift_intake and lift_plan, which read the log as the caller.
    PaywallBenefit(
      icon: Icons.event_note_outlined,
      title: 'Your own training plan',
      detail:
          'A training plan built from your goal, the days you can train and '
          'what you have actually lifted. It adjusts as you go.',
    ),
    // lift_chat, given the last ten sessions (lift_log.ts).
    PaywallBenefit(
      icon: Icons.forum_outlined,
      title: 'A coach on call',
      detail:
          'Ask about your training at any time. The coach reads your recent '
          'sessions before it answers.',
    ),
    // Photos: taking one needs the entitlement.
    PaywallBenefit(
      icon: Icons.photo_camera_outlined,
      title: 'Weekly progress photos',
      detail:
          'One photo a week for each pose, kept privately on your account and '
          'played back in order.',
    ),
    // lift_swap, from the session screen.
    PaywallBenefit(
      icon: Icons.swap_horiz,
      title: 'Smart exercise swaps',
      detail:
          'When a machine is taken, the coach picks a swap that trains the '
          'same thing.',
    ),
  ];

  /// What sets a tier apart, in a line. The two hold the same features;
  /// Premium has a better model behind the replies (surfaces.ts `modelFor`)
  /// and three times the monthly coaching allowance (limits.ts:
  /// `monthly_spend` 1.92 against 0.64), which Guideline 3.1.2(c) wants said
  /// as an amount rather than as "more" (ADR-0041).
  static String _line(EntitlementTier tier) => switch (tier) {
    EntitlementTier.premium => '3× the coaching, sharper model',
    _ => 'Everything above',
  };

  @override
  Widget build(BuildContext context) {
    final signedOut = widget.auth != null && widget.auth!.current == null;
    final tiers = <PaywallTier>[
      for (final offer in _offers)
        PaywallTier(
          id: offer.id,
          name: offer.tier.label,
          // Straight from the storefront, already in the lifter's own
          // currency. The app names tiers; it never prices them.
          price: offer.price,
          period: offer.period,
          line: _line(offer.tier),
          // The tier the screen opens on, and the one to start with: the
          // cheap first step, which upgrades on the day it is outgrown.
          recommended: offer.tier == EntitlementTier.paid,
        ),
    ];
    PurchaseOffer? offerFor(String id) {
      for (final offer in _offers) {
        if (offer.id == id) return offer;
      }
      return null;
    }

    String? busyId;
    for (final offer in _offers) {
      if (offer.tier == _buying) busyId = offer.id;
    }

    return CoachPaywall(
      appIcon: const AssetImage('assets/images/brand/app_icon.png'),
      appName: kProductName,
      photo: 'assets/images/backgrounds/hero_paywall.webp',
      headline: 'A plan built for you, and a coach to ask',
      benefits: _benefits,
      tiers: tiers,
      loading: _loading,
      busyTierId: busyId,
      restoring: _restoring,
      note: _note,
      signedOut: signedOut && _offers.isNotEmpty,
      platform: _platform,
      onSubscribe: _busy
          ? null
          : (tier) {
              final offer = offerFor(tier.id);
              if (offer != null) unawaited(_choose(offer));
            },
      onRestore: _busy ? null : () => unawaited(_restore()),
      onClose: _busy ? null : () => Navigator.of(context).maybePop(),
      onTerms: () => _open(const LegalDocumentScreen(document: termsOfUse)),
      onPrivacy: () =>
          _open(const LegalDocumentScreen(document: privacyPolicy)),
    );
  }
}
