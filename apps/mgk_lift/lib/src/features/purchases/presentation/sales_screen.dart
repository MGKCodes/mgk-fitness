import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../auth/domain/account.dart';
import '../../auth/presentation/sign_in_screen.dart';
import '../../entitlement/domain/entitlement.dart';
import '../../legal/domain/legal_copy.dart';
import '../../legal/presentation/legal_document_screen.dart';
import '../domain/purchases.dart';
import 'restore_button.dart';

/// Where the coach is sold: one screen, reached from every door (R6).
///
/// **It replaced a sheet, and the three places that each sold differently.**
/// The C sent a signed-out lifter to sign in and an unsubscribed one to the
/// Plan tab; Plan's empty state was a pitch with a price table; Photos had its
/// own. Now the C wherever it is, Plan's button and Photos' button all open
/// this, and it returns what happened so the door can open onto what was just
/// bought.
///
/// **Choosing a tier is the purchase**, as Run's screen already works: each
/// tier is a card with its own button, rather than a choice and then a second
/// button that might still be buying the first tier.
///
/// **It promises only what ships.** Each bullet below is one thing the coach
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
    // screen built for it. Nothing is charged until it exists.
    final auth = widget.auth;
    if (auth != null && auth.current == null) {
      final signedIn = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => SignInScreen(auth: auth)),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final height = MediaQuery.sizeOf(context).height;
    final signedOut = widget.auth != null && widget.auth!.current == null;

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: PhotoBackdrop.hero(
          image: 'assets/images/backgrounds/hero_paywall.webp',
          child: Stack(
            children: <Widget>[
              // Not a lazy list: the offer is short and finite, and every
              // part of it — the second tier, Restore, the renewal terms, the
              // two links — must exist whether or not it has been scrolled to.
              SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  // The photograph carries the top; the offer starts where it
                  // has faded, so nothing is read against a face or a bar.
                  (height * 0.30).clamp(160, 300),
                  AppSpacing.xl,
                  AppSpacing.xxl + MediaQuery.paddingOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SectionLabel('The coach'),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'A plan built for you, and a coach to ask',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Tracking stays free, whatever you choose. This is what a '
                      'subscription adds.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    if (_loading && _offers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_offers.isEmpty)
                      const _NothingToSell()
                    else
                      for (final offer in _offers) ...<Widget>[
                        _TierCard(
                          offer: offer,
                          busy: _buying == offer.tier,
                          onChoose: _busy ? null : () => _choose(offer),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    if (signedOut && _offers.isNotEmpty)
                      Text(
                        "You'll sign in or make an account first: a "
                        'subscription belongs to your account, which is how it '
                        'reaches your coach and follows you to a new phone.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    if (_note case final note?) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        note,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Center(
                      child: RestorePurchasesButton(
                        onRestore: _busy ? null : _restore,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      renewalWording(_platform),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    // Wrap, not Row: these are the two links Guideline 3.1.2
                    // requires to be present and working, so a layout that clips
                    // one at large text is a rejection, not a cosmetic complaint.
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: AppSpacing.md,
                      children: <Widget>[
                        AppTextButton(
                          label: 'Terms of use',
                          onPressed: () => _open(
                            const LegalDocumentScreen(document: termsOfUse),
                          ),
                        ),
                        AppTextButton(
                          label: 'Privacy policy',
                          onPressed: () => _open(
                            const LegalDocumentScreen(document: privacyPolicy),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                top: top + AppSpacing.xs,
                left: AppSpacing.sm,
                child: AppIconButton(
                  icon: Icons.close,
                  tooltip: 'Close',
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tier: what it is, what the store charges for it, what it adds, and the
/// button that buys it.
class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.offer,
    required this.busy,
    required this.onChoose,
  });

  final PurchaseOffer offer;
  final bool busy;
  final VoidCallback? onChoose;

  /// What each tier adds, **one line per thing that ships**, with where it
  /// lives. The two paid tiers hold the same features and differ only in how
  /// much the coach will talk, which the second tier says first.
  static List<String> _adds(EntitlementTier tier) => switch (tier) {
    EntitlementTier.premium => const <String>[
      'Everything in Coach, feature for feature',
      // limits.ts: the monthly allowance per tier.
      'Far more room to talk to your coach each month',
    ],
    _ => const <String>[
      // lift_intake and lift_plan, which read the log as the caller.
      'A training plan built from your goal, your days and what you have '
          'actually lifted',
      // lift_chat, given the last ten sessions (lift_log.ts).
      'A coach to ask about your training, who reads your recent sessions',
      // lift_swap, from the session screen.
      'A swap the coach picks when a machine is taken',
      // Photos: taking one needs the entitlement.
      'Progress photos, week by week',
    ],
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassSurface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            children: <Widget>[
              Text(offer.tier.label, style: theme.textTheme.titleMedium),
              Text(
                // Straight from the storefront, already in the lifter's own
                // currency. The app names tiers; it never prices them.
                '${offer.price} / ${offer.period}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (final line in _adds(offer.tier))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      line,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          PrimaryButton(
            label: 'Subscribe to ${offer.tier.label}',
            busy: busy,
            onPressed: onChoose,
          ),
        ],
      ),
    );
  }
}

/// The build cannot sell, or the store had nothing to offer. One state for
/// both, because they are the same fact to a lifter and neither is their
/// problem.
class _NothingToSell extends StatelessWidget {
  const _NothingToSell();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassSurface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Not available to buy yet', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Everything you log stays free and stays yours in the meantime.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
