import 'package:flutter/material.dart';

import '../brand/app_brand.dart';
import '../motion/entrance.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import 'app_card.dart';

/// The one account every app in the suite signs into, as it is drawn wherever
/// somebody meets it: the head of the sign-in screen, the card at the top of
/// Settings, and the circle that stands for a person.
///
/// Written in Run and moved here when Lift's copies had drifted: its sign-in
/// was headed "Sign in" with no platform name, and its Settings led with a sync
/// card where Run's leads with a person. The account is one account, so the
/// parts that show it are drawn once.

/// The head of the sign-in screen: which app this is, then whose account.
///
/// **The account is named for the suite, never for the app.** What is made
/// here is not an account for one app. It is the MGKFitness Account that works
/// across every app in the suite, and heading the screen with one app's name
/// would say the opposite to the person who already has one from the other.
/// The app shows itself above it instead, with its own icon ([AppIdentity]),
/// so nobody wonders either which app they are in or whose account it is.
///
/// "Account" since 3 October 2026, in both apps: Run's said "Profile", and the
/// suite's owner reads it as an account, which is also what both apps' delete
/// screens and documents call it.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.line,
    required this.otherApp,
    this.app,
  });

  /// What this visit is: `Create your account`, `Welcome back`.
  final String line;

  /// The sibling app the same sign-in works in: `Lift` in Run, `Run` in Lift.
  final String otherApp;

  /// Which app this is, above the suite's name: an [AppIdentity]. Null draws
  /// nothing.
  final Widget? app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (app case final Widget app) ...<Widget>[
          Center(child: app),
          const SizedBox(height: AppSpacing.lg),
        ],
        // One line, shrunk to fit rather than wrapped: "Account" is wider than
        // "Profile" was, and on a 375-point phone the name broke over two
        // lines.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$kPlatformName Account',
            maxLines: 1,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        // The words arrive; the form under them does not. Staggering the
        // fields would put movement under a cursor and risk fighting autofill
        // and focus on the one screen that should feel most solid.
        Entrance(
          child: Text(
            line,
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        // Said whether signing in or signing up. Somebody signing in may be
        // arriving from the other app with an account they did not know
        // reached this far, and that is worth telling them while they are
        // wondering whether their details will work.
        Entrance(
          child: Text(
            'One account for every $kPlatformName app. The same '
            // A hyphen that never breaks: split over two lines, "sign-" read
            // as a word of its own.
            'sign‑in works in $otherApp and in anything else we make, '
            'so you only set this up once.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// Which app this is: its icon from the home screen and its name under it, as
/// the home screen shows them.
///
/// [icon] is the icon itself, downscaled from the one the phone shows, rather
/// than a drawing of it; each app ships its own. A hairline edge keeps the
/// charcoal square from dissolving into a dark photograph behind it.
class AppIdentity extends StatelessWidget {
  const AppIdentity({
    super.key,
    required this.icon,
    required this.name,
    this.size = 72,
  });

  final ImageProvider icon;

  /// The name on the home screen: `Run`, `Lift`.
  final String name;

  /// Larger than a home screen's 60, so it is the first thing read. It was
  /// 48 while Run's sign-up still listed what an account gives under the head,
  /// which at 64 pushed the screen's last link under the bottom of a 393-point
  /// phone; the list is gone (1.0.1).
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The corner of an iOS icon, near enough at this size.
    final radius = BorderRadius.circular(size * 0.225);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: size,
          height: size,
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: const Color(0x2EFFFFFF)),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Image(
              image: icon,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // The name under it says the same thing to a screen reader.
              excludeFromSemantics: true,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          name,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// How a name is drawn when there is no picture of its owner.
///
/// Initials where a name was given, and null where none was, which the avatar
/// draws as the generic mark. Both are ordinary states.
///
/// **At most two characters, from at most two words.** A long name reduced to
/// four initials is unreadable in a 40px circle, and a single character is
/// enough for most people. Non-Latin scripts fall through the same path: the
/// first character of each of the first two words, whatever those characters
/// are.
String? initialsFor(String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return null;
  final picked = words.take(2).map((w) => w.characters).toList();
  return picked.map((c) => c.first).join().toUpperCase();
}

/// What fills an avatar that has no photo: the initials, or the generic mark.
///
/// Fills its box and is not clipped, so an avatar that sometimes holds a photo
/// can swap this in under its own circle. [InitialsAvatar] is the circle for an
/// app that keeps no photo at all.
///
/// Greyscale like everything else (ADR-0009): the initials sit in silver on the
/// elevated surface, the same pairing the apps use for a filled control.
class AvatarInitials extends StatelessWidget {
  const AvatarInitials({super.key, required this.initials, required this.size});

  final String? initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.elevated,
      child: Center(
        child: initials == null
            ? Icon(
                Icons.person_outline,
                size: size * 0.52,
                color: AppColors.textSecondary,
              )
            : Text(
                initials!,
                style: TextStyle(
                  // Scaled off the circle rather than the text theme: this
                  // renders at 64px on a card and at 96px on the account
                  // screen, and a fixed size would be wrong at both.
                  fontSize: size * 0.38,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}

/// A circular avatar that is only ever initials or the generic mark.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.initials, this.size = 40});

  final String? initials;
  final double size;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox(
      width: size,
      height: size,
      child: AvatarInitials(initials: initials, size: size),
    ),
  );
}

/// Who this is, in one card at the top of Settings: a face, a name, and what
/// they are paying for.
///
/// **The hierarchy is the point.** A settings header answers "is this me?", and
/// the thing that answers it fastest is a face, then a name. The address is
/// confirmation rather than identity, and the plan is a fact, short enough to
/// sit under a name. What can be done to the account is one tap in.
class ProfileCard extends StatelessWidget {
  /// Somebody signed in.
  const ProfileCard({
    super.key,
    required this.avatar,
    required this.title,
    this.email,
    this.plan,
    this.planColor = AppColors.textSecondary,
    this.onTap,
  }) : note = null;

  /// Nobody signed in, which is an ordinary state: both apps open on a working
  /// tracker with no account.
  const ProfileCard.withoutAccount({
    super.key,
    required this.avatar,
    required this.title,
    required String this.note,
    this.onTap,
  }) : email = null,
       plan = null,
       planColor = AppColors.textSecondary;

  /// Drawn at 64px: an app's own avatar, or an [InitialsAvatar].
  final Widget avatar;

  /// The name where there is one, the address where there is not.
  final String title;

  /// Under the title, when the title is a name.
  final String? email;

  /// What they pay for, as a fact: `Coach`, `Free`, `Coach · payment failed`.
  /// Null draws nothing, for the moment before the read lands.
  final String? plan;
  final Color planColor;

  /// Where things stand with no account. States the position.
  final String? note;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final quiet = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textTertiary,
    );
    const chevron = Icon(
      Icons.chevron_right,
      size: 20,
      color: AppColors.textTertiary,
    );

    if (note != null) {
      return AppCard(
        onTap: onTap,
        child: Row(
          children: <Widget>[
            avatar,
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: titleStyle),
                  const SizedBox(height: 2),
                  Text(note!, style: quiet?.copyWith(height: 1.35)),
                ],
              ),
            ),
            if (onTap != null) chevron,
          ],
        ),
      );
    }

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        children: <Widget>[
          avatar,
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: titleStyle, overflow: TextOverflow.ellipsis),
                if (email != null) ...<Widget>[
                  const SizedBox(height: 1),
                  Text(email!, style: quiet, overflow: TextOverflow.ellipsis),
                ],
                if (plan != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    plan!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: planColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null) chevron,
        ],
      ),
    );
  }
}
