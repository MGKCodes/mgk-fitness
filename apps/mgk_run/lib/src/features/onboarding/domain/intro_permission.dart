/// The permissions the intro asks for, **one at a time, for real**.
///
/// ## Why the dialog fires here
///
/// An earlier version of this screen only *described* the permissions and left
/// the real prompts to the moment each was first needed. That is the textbook
/// iOS advice and it was wrong for Runio, for a reason the textbook does not
/// cover: the first thing a runner does after onboarding is press start, and a
/// permission sheet landing on top of a run they are trying to begin is worse
/// than one asked by a coach who has just explained itself.
///
/// So the coach explains, the runner taps, the real dialog appears, and the
/// coach says something about whichever way it went. The explanation is still
/// what makes it work — what changed is that the answer is settled while
/// somebody is sitting still, rather than on a pavement.
///
/// ## Why a list
///
/// One at a time, each with its own explanation, because a runner who is shown
/// two system dialogs back to back reads them as a toll rather than a
/// conversation. The list is the order they are asked in; adding one is an
/// entry here and a branch in `requestIntroPermission`.
library;

/// Which permission. Each needs its own platform call, so this is a closed set
/// rather than a string.
enum IntroPermissionKind {
  /// Foreground location. What run recording needs.
  location,

  /// HealthKit reads: runs recorded on a watch or in another app.
  healthKit,
}

/// One permission, and everything the coach says around it.
class IntroPermission {
  const IntroPermission({
    required this.kind,
    required this.explain,
    required this.cta,
    required this.granted,
    required this.denied,
  });

  final IntroPermissionKind kind;

  /// What it is for, before the dialog. Plain, and about the runner rather
  /// than about the API.
  final String explain;

  /// The button that raises the real dialog.
  final String cta;

  /// What the coach says when it was allowed.
  final String granted;

  /// What the coach says when it was not.
  ///
  /// **Never an error.** A refused permission is a shape the app is built for,
  /// not a failure it recovers from, so this says what still works and where to
  /// change their mind. A runner who declines has made a choice, and being
  /// scolded for it by a coach they met ninety seconds ago is how an app gets
  /// deleted.
  final String denied;
}

/// The order they are asked in.
///
/// Location first: it is what recording needs, so it is the one worth spending
/// the runner's patience on. Health second, because it is an enhancement — a
/// runner who says no to it simply starts from an empty log.
///
/// **Both requests are real as of 2026-08-10** — location through geolocator,
/// Health through the same `WorkoutSource` the rest of the app reads. Neither
/// can be verified from the Windows harness this repo is developed on, so they
/// are checked on a device; the refusal path stays covered by widget tests,
/// which inject their own answer.
///
/// **Neither can be asked twice.** iOS records the answer on first ask and
/// never shows the sheet again for the life of the install, so walking this
/// conversation a second time replays the words without the dialogs. Settings →
/// Permissions says how to actually revoke, because nothing in the app can.
const List<IntroPermission> introPermissions = <IntroPermission>[
  IntroPermission(
    kind: IntroPermissionKind.location,
    explain:
        'First, location. It is how I follow a run while you are out there, '
        'so I can tell you how far you went and how quick.',
    cta: 'Allow location',
    granted: 'Great. That is the one that matters most.',
    denied:
        'No problem at all. Tell me about your runs afterwards and I will '
        'log them just the same. You can switch location on any time in '
        'Settings if you change your mind.',
  ),
  IntroPermission(
    kind: IntroPermissionKind.healthKit,
    explain:
        'And Health. If you let me look, I can see runs you have already '
        'done and anything you record on a watch, so we are not starting '
        'from nothing.',
    cta: 'Allow Health',
    // **Deliberately conditional.** iOS does not tell an app which health reads
    // were granted, so "granted" here only means the sheet was answered. A
    // runner who ticked nothing would otherwise be promised their history was
    // coming, and then watch nothing arrive.
    granted: 'Perfect. If there is anything there, I will pick it up.',
    denied:
        'That is fine. We will start from the runs we do together instead. '
        'You can change it later in Settings if you want me to look.',
  ),
];
