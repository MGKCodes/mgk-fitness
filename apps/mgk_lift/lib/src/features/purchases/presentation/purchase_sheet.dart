import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../entitlement/domain/entitlement.dart';
import '../../legal/domain/legal_copy.dart';
import '../../legal/presentation/legal_document_screen.dart';
import '../domain/purchases.dart';
import 'restore_button.dart';

/// Where money actually moves: both tiers, priced by the store, each one
/// buyable.
///
/// **Guideline 3.1.2 decides most of what is on this sheet**, so the
/// requirements are named here rather than discovered in a rejection: the
/// title, length and price of each subscription; a functional link to the
/// Terms of Use and to the privacy policy; the auto-renew terms in the store's
/// own words; and a way to restore without buying anything first.
/// `purchase_sheet_test.dart` asserts each one.
///
/// It replaced a single "Start coaching" button that could only ever buy Coach
/// while the paywall above it advertised Premium Coach — a tier the app showed
/// and could not sell. Both paywalls (Plan and Photos) open this, so the rules
/// live in one place.
///
/// Returns the [PurchaseResult] when the sheet closes because something
/// changed — bought, restored, or paid-and-waiting — and null when it was
/// dismissed. Failures stay on the sheet, beside the button that caused them.
class PurchaseSheet extends StatefulWidget {
  const PurchaseSheet({
    super.key,
    required this.flow,
    this.offers = const <PurchaseOffer>[],
    this.signedIn = true,
    this.onSignIn,
    this.platform,
  });

  final PurchaseFlow flow;

  /// What the shell already knows the store sells, so the sheet opens priced
  /// rather than on a spinner. Asked again on open either way.
  final List<PurchaseOffer> offers;

  /// A purchase must belong to an account — the webhook keys the entitlement
  /// on the Supabase user and refuses an anonymous one. Signed out, the sheet
  /// says so and offers [onSignIn] instead of a button that would refuse.
  final bool signedIn;
  final VoidCallback? onSignIn;

  /// Which store's words to use. Injected for tests; the device's otherwise.
  final TargetPlatform? platform;

  static Future<PurchaseResult?> show(
    BuildContext context, {
    required PurchaseFlow flow,
    List<PurchaseOffer> offers = const <PurchaseOffer>[],
    bool signedIn = true,
    VoidCallback? onSignIn,
  }) => showGlassSheet<PurchaseResult>(
    context: context,
    builder: (_) => PurchaseSheet(
      flow: flow,
      offers: offers,
      signedIn: signedIn,
      onSignIn: onSignIn,
    ),
  );

  @override
  State<PurchaseSheet> createState() => _PurchaseSheetState();
}

class _PurchaseSheetState extends State<PurchaseSheet> {
  late List<PurchaseOffer> _offers = widget.offers;
  late bool _loading = widget.offers.isEmpty;
  EntitlementTier _selected = EntitlementTier.paid;
  bool _buying = false;
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
      if (_offerFor(_selected) == null && _offers.isNotEmpty) {
        _selected = _offers.first.tier;
      }
    });
  }

  PurchaseOffer? _offerFor(EntitlementTier tier) {
    for (final offer in _offers) {
      if (offer.tier == tier) return offer;
    }
    return null;
  }

  Future<void> _buy() async {
    final offer = _offerFor(_selected);
    if (offer == null || _buying) return;
    setState(() {
      _buying = true;
      _note = null;
    });
    final result = await widget.flow.buy(offer);
    if (!mounted) return;
    _settle(result, restoring: false);
  }

  Future<void> _restore() async {
    setState(() => _note = null);
    final result = await widget.flow.restore();
    if (!mounted) return;
    _settle(result, restoring: true);
  }

  void _settle(PurchaseResult result, {required bool restoring}) {
    switch (result.status) {
      case PurchaseStatus.entitled:
      case PurchaseStatus.pending:
        // Something changed. The shell says what, and refreshes the screen
        // under the sheet to match.
        Navigator.of(context).pop(result);
      case PurchaseStatus.cancelled:
        // Backing out of the store's sheet is a decision, not an error.
        setState(() => _buying = false);
      case PurchaseStatus.notSignedIn:
        setState(() {
          _buying = false;
          _note =
              'Sign in first, then try again. A subscription belongs to your '
              'account, which is how it reaches your coach and follows you to '
              'a new phone. Nothing has been charged.';
        });
      case PurchaseStatus.nothingToRestore:
        setState(() {
          _buying = false;
          _note =
              'There is no Lift subscription on this '
              '${storeAccountName(_platform)} to restore.';
        });
      case PurchaseStatus.failed:
        setState(() {
          _buying = false;
          _note = restoring
              ? 'Could not reach ${storeName(_platform)}. Try again in a '
                    'moment.'
              : result.message ??
                    'That did not go through. Nothing has been charged.';
        });
    }
  }

  void _open(BuildContext context, Widget screen) => unawaited(
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen)),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = _offerFor(_selected);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SheetHandle(),
          Text('Choose a tier', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Both unlock your coach, your plan and progress photos. Premium '
            'Coach gives the coach far more room to talk.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_loading && _offers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_offers.isEmpty)
            const _NothingToSell()
          else
            for (final offer in _offers) ...<Widget>[
              _TierOption(
                offer: offer,
                selected: offer.tier == _selected,
                onTap: _buying
                    ? null
                    : () {
                        unawaited(AppHaptics.selection());
                        setState(() {
                          _selected = offer.tier;
                          _note = null;
                        });
                      },
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          const SizedBox(height: AppSpacing.md),
          if (!widget.signedIn) ...<Widget>[
            PrimaryButton(
              label: 'Sign in to subscribe',
              onPressed: widget.onSignIn,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'A subscription belongs to your account, so it reaches your '
              'coach and follows you to a new phone.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ] else
            PrimaryButton(
              label: chosen == null
                  ? 'Subscribe'
                  : 'Subscribe to ${chosen.tier.label}',
              busy: _buying,
              onPressed: chosen == null ? null : _buy,
            ),
          if (_note case final note?) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Center(child: RestorePurchasesButton(onRestore: _restore)),
          const SizedBox(height: AppSpacing.md),
          Text(
            renewalWording(_platform),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Wrap, not Row: these are the two links Guideline 3.1.2 requires
          // to be present and working, so a layout that clips one at large
          // text is a rejection rather than a cosmetic complaint.
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.md,
            children: <Widget>[
              AppTextButton(
                label: 'Terms of use',
                onPressed: () => _open(
                  context,
                  const LegalDocumentScreen(document: termsOfUse),
                ),
              ),
              AppTextButton(
                label: 'Privacy policy',
                onPressed: () => _open(
                  context,
                  const LegalDocumentScreen(document: privacyPolicy),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One tier, as a choice rather than a button: picking is free, and the single
/// primary button below is where money moves.
class _TierOption extends StatelessWidget {
  const _TierOption({
    required this.offer,
    required this.selected,
    required this.onTap,
  });

  final PurchaseOffer offer;
  final bool selected;
  final VoidCallback? onTap;

  /// App copy, the same words as the tier table on the paywall and the terms:
  /// the two paid tiers hold the same features and differ only in how much
  /// the coach will talk.
  static String _detail(EntitlementTier tier) => switch (tier) {
    EntitlementTier.premium =>
      'Everything in Coach, feature for feature. Far more room to talk to '
          'the coach.',
    _ => 'A plan built for you, a coach that adapts it, and progress photos.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '${offer.tier.label}, ${offer.price} a ${offer.period}',
      excludeSemantics: true,
      child: PressScale(
        enabled: onTap != null,
        scale: 0.98,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.standard,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: selected ? AppColors.elevated : AppColors.surface,
              borderRadius: AppRadius.cardAll,
              // Marked by weight rather than colour: there is no accent to
              // reach for, which is the constraint the palette is built on.
              border: Border.all(
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textTertiary.withValues(alpha: 0.3),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        children: <Widget>[
                          Text(
                            offer.tier.label,
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            // Straight from the storefront, already formatted
                            // in the lifter's currency.
                            '${offer.price} / ${offer.period}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontFeatures: const <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _detail(offer.tier),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The build cannot sell, or the store had nothing to offer.
///
/// One state for both, because they are the same fact to a lifter and neither
/// is their problem.
class _NothingToSell extends StatelessWidget {
  const _NothingToSell();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      color: AppColors.elevated,
      padding: const EdgeInsets.all(AppSpacing.md),
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

/// What the shop is called on [platform].
///
/// Run named the App Store on both platforms until a Play customer was told
/// their Apple ID would be charged (2026-09-11). Two names rather than one,
/// because a person has an Apple ID or a Google Play account, and the shop is
/// the App Store or Google Play.
String storeName(TargetPlatform platform) =>
    platform == TargetPlatform.android ? 'Google Play' : 'the App Store';

/// What the person's account with that shop is called.
String storeAccountName(TargetPlatform platform) =>
    platform == TargetPlatform.android ? 'Google Play account' : 'Apple ID';

/// The auto-renew disclosure, in the words each store expects.
///
/// Apple prescribes the facts and, in practice, the phrasing; Play prescribes
/// the facts. Both say the same four things about the same subscription —
/// that it renews, when it is charged, how much notice cancelling needs, and
/// where to do it — and both match `docs/terms-of-use.md`.
String renewalWording(TargetPlatform platform) =>
    platform == TargetPlatform.android ? _googleRenewal : _appleRenewal;

const String _appleRenewal =
    'Subscriptions renew every month until cancelled. Payment is charged to '
    'your Apple ID at confirmation of purchase, and renews within 24 hours '
    'before the period ends unless auto-renew is turned off at least 24 hours '
    'before then. Manage or cancel it in your Apple ID settings.';

const String _googleRenewal =
    'Subscriptions renew every month until cancelled. Payment is charged to '
    'your Google Play account at confirmation of purchase, and renews within '
    '24 hours before the period ends unless auto-renew is turned off at least '
    '24 hours before then. Manage or cancel it in the Play Store under '
    'Payments and subscriptions.';
