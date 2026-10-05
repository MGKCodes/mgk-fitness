import 'package:flutter/material.dart';

import '../brand/app_brand.dart';
import '../motion/press_scale.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import 'app_buttons.dart';
import 'section_label.dart';

/// An app's icon and its full name, in a row: the head of a screen where a
/// decision is made, so it is plain which of the two look-alike apps is
/// asking (4 October 2026). The paywall and the delete screen carry it.
class AppIdentityRow extends StatelessWidget {
  const AppIdentityRow({
    super.key,
    required this.icon,
    required this.name,
    this.size = 40,
  });

  final ImageProvider icon;

  /// `MGKFitness: Lift`.
  final String name;

  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.225);
    return Row(
      children: <Widget>[
        // The sign-in's edge: both icons are dark squares on a dark screen.
        DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: const Color(0x2EFFFFFF), width: 0.8),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Image(
              image: icon,
              width: size,
              height: size,
              excludeFromSemantics: true,
              // An icon that will not load leaves its square, not an error
              // printed across a screen asking somebody to decide something.
              errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// **The two ways to delete, the same in both apps** (4 October 2026): this
/// app's data, keeping the MGKFitness account for the other app, or the whole
/// account and everything in both.
///
/// One login serves the suite (ADR-0008), so "delete my account" is two
/// requests wearing one name. The server has always taken both; Lift asked
/// which, and Run sent only its own until this was shared.
///
/// A choice rather than two buttons: both are destructive, so the screen must
/// not offer two ways to fire. One choice, then one confirmed action. It opens
/// on the narrower, because a destructive screen should not start on its most
/// destructive option.
///
/// "This app's data", not "my Lift data": both apps' brand rules forbid the
/// bare app name in a sentence, where "your Run data" and "your run data" are
/// one phrase meaning two things. The [AppIdentityRow] above it says which
/// app this is.
class DeletionChoice extends StatelessWidget {
  const DeletionChoice({
    super.key,
    required this.wide,
    required this.onChanged,
    required this.otherApp,
    required this.holds,
    this.enabled = true,
  });

  /// Whether the whole account is chosen.
  final bool wide;

  final ValueChanged<bool> onChanged;

  /// The other app's full name: `MGKFitness: Run`.
  final String otherApp;

  /// What this app holds, as a sentence: what the narrow choice erases.
  final String holds;

  final bool enabled;

  /// What a test taps to choose each.
  static const Key narrowKey = ValueKey<String>('delete-this-app');
  static const Key wideKey = ValueKey<String>('delete-everything');

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      const SectionLabel('How much', color: AppColors.textTertiary),
      const SizedBox(height: AppSpacing.sm),
      _Choice(
        key: narrowKey,
        chosen: !wide,
        danger: false,
        enabled: enabled,
        onTap: () => onChanged(false),
        title: "Delete this app's data",
        // Not "your account stays": it goes too when the other app holds
        // nothing, which the note under the choice says. What is always true
        // is that the other app's data is not touched.
        body: '$holds Anything $otherApp holds is left alone.',
      ),
      _Choice(
        key: wideKey,
        chosen: wide,
        danger: true,
        enabled: enabled,
        onTap: () => onChanged(true),
        title: 'Delete my whole $kPlatformName account',
        body:
            'Everything above, everything $otherApp holds, and the login '
            'itself. You will not be able to sign in to either app.',
      ),
    ],
  );
}

/// What becomes of the login, said before the deletion rather than discovered
/// after it, in the same words in both apps.
String deletionLoginNote({required bool wide, required String otherApp}) => wide
    ? 'This removes the account itself, so anything $otherApp holds goes '
          'with it. If you only want out of this app, choose the first option.'
    : 'Your login is your $kPlatformName account, shared with $otherApp. If '
          '$otherApp holds no data, there is nothing left for the account to '
          'be for, so it goes too. We will tell you which happened.';

/// What happened, once the server has answered, in the same words in both
/// apps. Not always what was asked for, and said either way.
///
/// [removed] is what this app held, as a sentence saying it has gone from our
/// servers. [keptForOtherApp] is the server keeping the login because
/// [otherApp] holds data; a login that is still there for any other reason
/// could not be removed, and says who to email.
String deletionOutcome({
  required String removed,
  required bool wide,
  required bool accountDeleted,
  required bool keptForOtherApp,
  required String otherApp,
  required String supportEmail,
}) {
  if (keptForOtherApp) {
    return '$removed Your $kPlatformName account is still active because '
        '$otherApp is using it${wide ? '.' : ', which is what you asked for.'}';
  }
  if (!accountDeleted) {
    return '$removed Your login could not be removed, though — email '
        '$supportEmail and we will finish it by hand.';
  }
  return wide
      ? '$removed Everything $otherApp held is gone as well, along with your '
            'login.'
      // Asked for the narrow one and got the wide one, because there was
      // nothing left to keep. Said plainly rather than glossed.
      : '$removed Your $kPlatformName account went too: nothing else was '
            'using it, so there was nothing left for it to be for.';
}

class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.chosen,
    required this.danger,
    required this.enabled,
    required this.onTap,
    required this.title,
    required this.body,
  });

  final bool chosen;

  /// Whether this is the choice that takes everything, whose chosen edge is
  /// the danger colour. Greyscale is the rule (ADR-0009) and status is the
  /// sanctioned exception: "this one takes everything" is status.
  final bool danger;

  final bool enabled;
  final VoidCallback onTap;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        button: true,
        selected: chosen,
        child: PressScale(
          enabled: enabled,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: AppRadius.cardAll,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  borderRadius: AppRadius.cardAll,
                  color: AppColors.surface,
                  border: Border.all(
                    color: chosen
                        ? (danger ? AppColors.danger : AppColors.textSecondary)
                        : AppColors.elevated,
                    width: chosen ? 2 : 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      chosen
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: chosen
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            body,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.45,
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
        ),
      ),
    );
  }
}

/// A short panel that says one thing that matters: what becomes of the login,
/// or that deleting does not cancel a subscription. An action under it when
/// there is one thing to do about it.
class NoticePanel extends StatelessWidget {
  const NoticePanel({
    super.key,
    required this.label,
    required this.text,
    this.action,
  });

  final String label;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
      action == null ? AppSpacing.lg : AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.cardAll,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionLabel(label, color: AppColors.textTertiary),
        const SizedBox(height: AppSpacing.sm),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        ?action,
      ],
    ),
  );
}

/// **Deleting the account does not stop the store charging for it**, said
/// where the deletion is asked for and again once it is done, with the way to
/// cancel beside it. The same words in both apps since 5 October 2026: Run's,
/// which Lift's delete screen did not have.
///
/// The subscription is between the person and Apple or Google; deleting the
/// data the coach runs on does not end it, and nothing on our side can.
/// Apple's account-deletion guidance asks for this to be said, and for the
/// way to cancel to be offered where it is said.
class StillBillingNotice extends StatelessWidget {
  const StillBillingNotice({
    super.key,
    required this.store,
    required this.onManage,
  });

  /// The shop that bills it: "Google Play", "the App Store".
  final String store;

  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) => NoticePanel(
    label: 'About your subscription',
    text:
        'Deleting your account does not cancel your subscription. Cancel it '
        'in $store, or it will keep renewing.',
    action: AppTextButton(label: 'Manage subscription', onPressed: onManage),
  );
}

/// Whether deleting the account erases this phone's copy too, with what each
/// answer means. On by default where it is offered: somebody deleting their
/// account has asked for their data to go, and the copy on the phone is the
/// part of that they are least likely to think of.
class PhoneCopySwitch extends StatelessWidget {
  const PhoneCopySwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.erasing,
    required this.keeping,
  });

  final bool value;

  /// Null while something is in flight.
  final ValueChanged<bool>? onChanged;

  /// What erasing removes: "Your runs, plan… are removed from this phone as
  /// well."
  final String erasing;

  /// What keeping leaves.
  final String keeping;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                "Also erase this phone's copy",
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
        Text(
          value ? erasing : keeping,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textTertiary,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
