import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../copy/store_wording.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import 'account_deletion.dart';
import 'app_buttons.dart';
import 'coach_mark.dart';
import 'glass_surface.dart';
import 'photo_backdrop.dart';
import 'primary_button.dart';
import 'sheet_handle.dart';

/// One thing the subscription adds: a few words to scan, and the sentence
/// behind them for whoever taps.
@immutable
class PaywallBenefit {
  const PaywallBenefit({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;

  /// Read in a glance, noun first: "Your own training plan".
  final String title;

  /// The full sentence, shown in a sheet when the row is tapped. Never the
  /// price or the renewal terms, which are always on the screen.
  final String detail;
}

/// One tier, as the store prices it.
@immutable
class PaywallTier {
  const PaywallTier({
    required this.id,
    required this.name,
    required this.price,
    required this.period,
    required this.line,
    this.recommended = false,
  });

  /// The app's own key for the tier, handed back when it is bought.
  final String id;

  final String name;

  /// Localised and formatted by the store: printed, never parsed.
  final String price;

  /// `month`.
  final String period;

  /// What this tier is, in a line: what sets it apart from the other.
  final String line;

  /// Labelled "Recommended" on its card (Matthew, 5 October 2026).
  ///
  /// Recommended, not "Most popular": the paywall research of 4 October
  /// advised against a popularity badge until there is data to back it, and
  /// a claim about what other people buy, made without that data, is one a
  /// store or a regulator can ask to see. A recommendation is the studio's
  /// own advice, and needs no evidence but the reason for it.
  final bool recommended;
}

/// **The coach's paywall, the same screen in both apps** (4 October 2026).
///
/// Built to the paywall research of that day: one screen that does not
/// scroll on a phone, the app's own icon and name where the decision is made
/// (the two apps look alike on purpose, so the paywall says which one is
/// charging), three or four benefits short enough to scan with the sentence
/// behind each a tap away, the two tiers side by side with the price as the
/// largest figure in each, one button that buys whichever is chosen, and the
/// store's terms under it rather than over it.
///
/// **It decides nothing about money.** Each app runs its own purchase, restore
/// and sign-in, and tells this what to show: which tier is busy, whether a
/// restore is running, and a note when something needs saying.
///
/// Scrolls only when it must: a large text size, or a very short phone. The
/// photograph is the space that gives way first.
class CoachPaywall extends StatefulWidget {
  const CoachPaywall({
    super.key,
    required this.appIcon,
    required this.appName,
    required this.photo,
    required this.headline,
    required this.benefits,
    required this.tiers,
    required this.onSubscribe,
    required this.onRestore,
    required this.onClose,
    required this.onTerms,
    required this.onPrivacy,
    this.loading = false,
    this.busyTierId,
    this.restoring = false,
    this.note,
    this.noteAction,
    this.signedOut = false,
    this.platform,
    this.nothingToSell =
        'Everything you log stays free and stays yours in the meantime.',
  });

  final ImageProvider appIcon;

  /// `MGKFitness: Lift`.
  final String appName;

  /// The app's own photograph, behind the top of the screen.
  final String photo;

  final String headline;
  final List<PaywallBenefit> benefits;

  /// The tiers on sale, cheapest first. The first is chosen to begin with.
  /// Empty when the store has nothing to offer.
  final List<PaywallTier> tiers;

  /// Buys the tier chosen. Null while something is in flight.
  final ValueChanged<PaywallTier>? onSubscribe;

  /// Restores an earlier purchase. Null while something is in flight.
  final VoidCallback? onRestore;

  /// Leaves. Null while something is in flight.
  final VoidCallback? onClose;

  final VoidCallback onTerms;
  final VoidCallback onPrivacy;

  /// Still asking the store what it sells.
  final bool loading;

  /// The tier being bought, by [PaywallTier.id].
  final String? busyTierId;

  final bool restoring;

  /// Something that needs saying: a payment pending, no connection, nothing
  /// to restore.
  final String? note;

  /// What to do about [note], when there is one thing: signing in.
  final Widget? noteAction;

  /// Whether choosing a tier will ask for an account first.
  final bool signedOut;

  /// Which store's words to use. The device's when null.
  final TargetPlatform? platform;

  /// Said when there is nothing to buy.
  final String nothingToSell;

  @override
  State<CoachPaywall> createState() => _CoachPaywallState();
}

class _CoachPaywallState extends State<CoachPaywall> {
  String? _chosen;

  PaywallTier? get _tier {
    final tiers = widget.tiers;
    if (tiers.isEmpty) return null;
    for (final tier in tiers) {
      if (tier.id == _chosen) return tier;
    }
    return tiers.first;
  }

  Future<void> _explain(PaywallBenefit benefit) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: false,
    builder: (sheet) => _BenefitSheet(benefit: benefit),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platform = widget.platform ?? defaultTargetPlatform;
    final tier = _tier;
    final busy = widget.busyTierId != null || widget.restoring;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textTertiary,
      height: 1.35,
    );

    return PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: PhotoBackdrop.hero(
          image: widget.photo,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.sm,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (box.maxHeight - AppSpacing.sm).clamp(
                      0.0,
                      double.infinity,
                    ),
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: AppIconButton(
                              icon: Icons.close,
                              tooltip: 'Close',
                              onPressed: busy ? null : widget.onClose,
                            ),
                          ),
                        ),
                        // The photograph's room, and the first to give way.
                        const Spacer(),
                        _OnCharcoal(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              const SizedBox(height: AppSpacing.xl),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: AppIdentityRow(
                                      icon: widget.appIcon,
                                      name: widget.appName,
                                      size: 44,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  // The coach's own mark, the C that sits at
                                  // the foot of every tab, so what is for sale
                                  // is plainly the thing that button opens
                                  // (Matthew, 5 October 2026). At the right,
                                  // where it sits on those screens. Drawn, not
                                  // a button: here it would have nowhere to go.
                                  const ExcludeSemantics(
                                    child: IgnorePointer(
                                      child: CoachMarkSurface(
                                        width: kCoachMarkSize,
                                        child: CoachMarkGlyph(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                widget.headline,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              for (final benefit in widget.benefits)
                                _BenefitRow(
                                  benefit: benefit,
                                  onTap: () => _explain(benefit),
                                ),
                              const SizedBox(height: AppSpacing.md),
                              if (widget.loading && widget.tiers.isEmpty)
                                const SizedBox(
                                  height: 112,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else if (tier == null)
                                _NothingToSell(line: widget.nothingToSell)
                              else
                                IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      for (final (i, option)
                                          in widget.tiers.indexed) ...<Widget>[
                                        if (i > 0)
                                          const SizedBox(width: AppSpacing.md),
                                        Expanded(
                                          child: _TierCard(
                                            tier: option,
                                            chosen: identical(option, tier),
                                            onTap: busy
                                                ? null
                                                : () => setState(
                                                    () => _chosen = option.id,
                                                  ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              if (widget.note case final note?) ...<Widget>[
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  note,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                    height: 1.35,
                                  ),
                                ),
                                if (widget.noteAction case final action?)
                                  Center(child: action),
                              ],
                              const SizedBox(height: AppSpacing.md),
                              PrimaryButton(
                                // The price again, on the thing that charges it.
                                label: tier == null
                                    ? 'Subscribe'
                                    : 'Subscribe · ${tier.price}/${tier.period}',
                                busy:
                                    tier != null &&
                                    widget.busyTierId == tier.id,
                                onPressed:
                                    tier == null ||
                                        busy ||
                                        widget.onSubscribe == null
                                    ? null
                                    : () => widget.onSubscribe!(tier),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                <String>[
                                  'Tracking stays free.',
                                  if (widget.signedOut)
                                    "You'll sign in first, so it reaches your coach.",
                                  renewalShort(platform),
                                ].join(' '),
                                textAlign: TextAlign.center,
                                style: small,
                              ),
                              // Wrap, not Row: these are the links Guideline 3.1.2
                              // requires present and working, so a layout that
                              // clips one at a large text size is a rejection.
                              Wrap(
                                alignment: WrapAlignment.center,
                                children: <Widget>[
                                  AppTextButton(
                                    label: 'Restore',
                                    busy: widget.restoring,
                                    onPressed: busy ? null : widget.onRestore,
                                  ),
                                  AppTextButton(
                                    label: 'Terms',
                                    onPressed: widget.onTerms,
                                  ),
                                  AppTextButton(
                                    label: 'Privacy',
                                    onPressed: widget.onPrivacy,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Everything a person reads to decide sits on charcoal, however pale the
/// photograph behind it (5 October 2026).
///
/// The hero scrim is drawn for a headline over the photograph's top third and
/// content below two-thirds of the way down. The paywall's content starts far
/// higher, and on Run's fog at dawn its white headline and benefit lines were
/// grey on grey. So the content carries its own ground: charcoal from its top
/// edge down, feathered into the photograph over [_feather] points above it.
/// Anchored to the content rather than to the screen, so the photograph keeps
/// the room above it on any phone's height.
class _OnCharcoal extends StatelessWidget {
  const _OnCharcoal({required this.child});

  final Widget child;

  static const double _feather = 96;
  static const Color _ground = Color(0xE61A1A1A);

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: <Widget>[
      const Positioned(
        // Out past the page's side padding and below its foot, so the ground
        // has no edges of its own.
        left: -AppSpacing.xl,
        right: -AppSpacing.xl,
        top: -_feather,
        bottom: -AppSpacing.xxl,
        child: IgnorePointer(
          child: Column(
            children: <Widget>[
              SizedBox(
                height: _feather,
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Color(0x001A1A1A), _ground],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: ColoredBox(color: _ground),
                ),
              ),
            ],
          ),
        ),
      ),
      child,
    ],
  );
}

/// One benefit: its icon, its few words, and the way to the sentence behind
/// them. The whole row is the target.
class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.benefit, required this.onTap});

  final PaywallBenefit benefit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      hint: 'More about this',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: <Widget>[
              Icon(benefit.icon, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  benefit.title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.info_outline,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sentence behind a benefit.
class _BenefitSheet extends StatelessWidget {
  const _BenefitSheet({required this.benefit});

  final PaywallBenefit benefit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Center(child: SheetHandle()),
            Row(
              children: <Widget>[
                Icon(benefit.icon, size: 22, color: AppColors.textSecondary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    benefit.title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              benefit.detail,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerRight,
              child: AppTextButton(
                label: 'Close',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One tier as a card that can be chosen: its name, its price as the largest
/// figure on it, and the line that sets it apart. Chosen, it carries a white
/// edge and a tick.
class _TierCard extends StatelessWidget {
  const _TierCard({required this.tier, required this.chosen, this.onTap});

  final PaywallTier tier;
  final bool chosen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = _card(theme);
    if (!tier.recommended) return card;
    // On the card's top edge rather than inside it, so a recommended card is
    // no taller than the other and the screen still fits without scrolling.
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        card,
        Positioned(
          top: -9,
          left: AppSpacing.md,
          child: ExcludeSemantics(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.textPrimary,
                borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                child: Text(
                  'Recommended',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.bg,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(ThemeData theme) {
    final radius = BorderRadius.circular(AppRadius.card);
    return Semantics(
      button: true,
      selected: chosen,
      label:
          '${tier.name}, ${tier.price} a ${tier.period}'
          '${tier.recommended ? ', recommended' : ''}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: chosen ? AppColors.textPrimary : const Color(0x2EFFFFFF),
              width: chosen ? 2 : 1,
            ),
          ),
          child: GlassSurface(
            borderRadius: radius,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        tier.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      chosen ? Icons.check_circle : Icons.circle_outlined,
                      size: 18,
                      color: chosen
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                // The billed amount, and the largest price on the screen
                // (Apple: "the most prominent pricing element").
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: tier.price,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                      TextSpan(
                        text: ' /${tier.period}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  tier.line,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.3,
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

/// The build cannot sell, or the store had nothing to offer: one state for
/// both, because they are the same fact to the person and neither is theirs.
class _NothingToSell extends StatelessWidget {
  const _NothingToSell({required this.line});

  final String line;

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
            line,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
