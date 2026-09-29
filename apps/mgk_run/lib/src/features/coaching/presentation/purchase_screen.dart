import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/sign_in_screen.dart';
import '../../legal/domain/legal_urls.dart';
import '../../legal/presentation/privacy_policy_screen.dart';
import '../data/entitlement_repository.dart';
import '../data/purchase_client.dart';
import '../domain/coach_access.dart';
import '../domain/coach_offer.dart';
import '../domain/plan_gate_copy.dart';

/// Re-exported so that importing this screen still yields [kTermsOfUseUrl].
/// The constant moved to `legal/domain/legal_urls.dart` when Settings gained
/// the same link: a legal document should not live inside the paywall.
export '../../legal/domain/legal_urls.dart' show kTermsOfUseUrl;

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

  late final Future<List<CoachOffer>> _offers = widget.purchases.offers();
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
      case PurchaseOutcome.nothingToRestore:
      case PurchaseOutcome.failed:
        setState(() {
          _busyId = null;
          _note = 'That did not go through. Nothing has been charged.';
        });
    }
  }

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
        await _settle();
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
      case PurchaseOutcome.cancelled:
      case PurchaseOutcome.failed:
        setState(() {
          _restoring = false;
          _note = 'Could not reach $_store. Try again in a moment.';
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
  Future<void> _settle() async {
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
      _note =
          'Payment went through. The coach can take a minute to unlock, and '
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool busy = _busyId != null || _restoring;

    return Scaffold(
      appBar: AppBar(title: const Text('The coach')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: <Widget>[
            Text(
              'What a subscription buys',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              planGateCostsCopy,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FutureBuilder<List<CoachOffer>>(
              future: _offers,
              builder:
                  (BuildContext context, AsyncSnapshot<List<CoachOffer>> snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final List<CoachOffer> offers =
                        snap.data ?? const <CoachOffer>[];
                    if (offers.isEmpty) return const _NothingToSell();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (final CoachOffer offer in offers) ...<Widget>[
                          _Tier(
                            offer: offer,
                            busy: _busyId == offer.id,
                            onBuy: busy ? null : () => _buy(offer),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                      ],
                    );
                  },
            ),
            if (_note != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (_needsAccount)
              Align(
                alignment: Alignment.centerLeft,
                child: AppTextButton(
                  label: 'Sign in',
                  onPressed: busy ? null : _signIn,
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            // Apple requires this, and requires it reachable without buying
            // anything first. It is a text button rather than a primary one
            // because it is for the minority who already paid.
            AppTextButton(
              label: 'Restore purchases',
              busy: _restoring,
              onPressed: busy ? null : _restore,
            ),
            const SizedBox(height: AppSpacing.lg),
            const _Renewal(),
            const SizedBox(height: AppSpacing.md),
            // Wrap, not Row. Two text buttons overflowed a 430pt phone by 29
            // pixels, and the narrowest surface the plate board tests is 320.
            // These are the two links Guideline 3.1.2 requires to be present
            // and functional, so a layout that clips one on a small phone is a
            // rejection rather than a cosmetic complaint.
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                AppTextButton(label: 'Terms of use', onPressed: _openTerms),
                AppTextButton(
                  label: 'Privacy policy',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PrivacyPolicyScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One tier, priced by the store.
class _Tier extends StatelessWidget {
  const _Tier({required this.offer, required this.busy, this.onBuy});

  final CoachOffer offer;
  final bool busy;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  offer.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                // Straight from the storefront, already formatted. The month
                // is ours to say because every product is monthly; the figure
                // never is.
                '${offer.price} / month',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            offer.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Subscribe',
              busy: busy,
              onPressed: onBuy,
            ),
          ),
        ],
      ),
    );
  }
}

/// The build cannot sell, or the store had nothing to offer.
///
/// One state for both, because they are the same fact to a runner and neither
/// is their problem. It does not say "error": nothing is broken from where they
/// are standing.
class _NothingToSell extends StatelessWidget {
  const _NothingToSell();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Not available to buy yet',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Everything you record stays free and stays yours in the '
            'meantime.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The auto-renew disclosure, in the words each store expects to see.
///
/// **It named the Apple ID on both platforms until 2026-09-11**, when the
/// paywall was opened on Android for the first time and told a Play customer
/// that their Apple ID would be charged and that they should cancel in their
/// Apple ID settings. Both sentences were false, on the screen immediately
/// before somebody parts with money — and a billing disclosure naming the wrong
/// payment method is the kind of thing Google checks rather than the kind it
/// overlooks.
///
/// The Apple wording is Apple's own required phrasing and is unchanged. The
/// Play wording says the same things about the same subscription: that it
/// renews, when it is charged, how much notice cancelling needs, and where to
/// do it. Play does not prescribe the sentence the way Apple does; what it
/// wants is that the terms are stated before purchase and that they are true.
/// Apple's phrasing, kept verbatim because Apple prescribes the sentence.
const String _appleRenewal =
    'Subscriptions renew every month until cancelled. Payment is charged to '
    'your Apple ID at confirmation of purchase, and renews within 24 hours '
    'before the period ends unless auto-renew is switched off at least 24 '
    'hours before then. Manage or cancel it in your Apple ID settings.';

/// The same four facts, about the store actually taking the money. Play
/// prescribes the facts rather than the wording.
const String _googleRenewal =
    'Subscriptions renew every month until cancelled. Payment is charged to '
    'your Google Play account at confirmation of purchase, and renews within '
    '24 hours before the period ends unless auto-renew is switched off at '
    'least 24 hours before then. Manage or cancel it in the Play Store under '
    'Payments and subscriptions.';

/// Which disclosure [platform] needs.
///
/// Top-level and public so a test can read both without pumping a widget: the
/// bug this exists to prevent was a `const` string nothing ever asserted on,
/// correct for the only platform anybody had run.
/// What the shop is called on this platform.
///
/// Top-level and platform-taking rather than a getter on the paywall, because
/// settings needs the same two names to say where a subscription is managed,
/// and a second copy of this is a second chance to name the wrong store — which
/// is the defect `the_paywall_names_the_right_store_test.dart` exists for.
String storeName(TargetPlatform platform) =>
    platform == TargetPlatform.android ? 'Google Play' : 'the App Store';

/// What the *person's* account with that shop is called.
///
/// Two names rather than one, because they are not interchangeable: a person
/// has an Apple ID or a Google Play account, and the shop is the App Store or
/// Google Play.
String storeAccountName(TargetPlatform platform) =>
    platform == TargetPlatform.android ? 'Google Play account' : 'Apple ID';

String renewalWording(TargetPlatform platform) =>
    platform == TargetPlatform.android ? _googleRenewal : _appleRenewal;

class _Renewal extends StatelessWidget {
  const _Renewal();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      renewalWording(defaultTargetPlatform),
      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
    );
  }
}
