import '../../../core/brand.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../../auth/data/auth_repository.dart';
import '../../legal/data/account_deletion_service.dart';
import '../../legal/domain/account_deleter.dart';
import '../../legal/presentation/legal_screen.dart';
import '../../../dev/dev_coach_model_controls.dart';
import '../../../dev/dev_persona_controls.dart';
import '../data/backup_consent_factory.dart';
import '../data/backup_eraser.dart';
import '../data/backup_health_factory.dart';
import '../domain/backup_consent.dart';
import '../domain/backup_health.dart';
import '../../health/domain/workout_source.dart';
import '../../coaching/domain/coach_subscription.dart';
import '../../coaching/data/entitlement_repository.dart';
import '../../onboarding/domain/intro_store.dart';
import 'settings_row.dart';
import 'permissions_screen.dart';
import 'account_screen.dart';
import 'backup_screen.dart';
import 'avatar.dart';
import '../domain/profile_photo.dart';
import '../data/file_profile_photo.dart';
import '../../legal/domain/legal_urls.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'permissions_section.dart';
import '../domain/unit_settings.dart';

/// The shipped version, shown at the foot of Settings.
///
/// A committed constant rather than a read of the bundle: the app takes no
/// dependency it does not need, and the preview harness has no bundle to read.
/// **Keep it in step with `version:` in pubspec.yaml.**
const String kAppVersion = '1.0.0';

/// Settings: **everything about the app rather than about the running.**
///
/// This is where a control belongs if it is not itself training — who is signed
/// in, how distances read, what the app promises about the data, and how to
/// leave. Profile used to lead with the signed-in address and a joined-on date;
/// those are account facts, so they are here, and Profile is about runs.
///
/// There is no row through to Profile any more. Profile is a tab — a row here
/// pointing at a page one tap away was a leftover from when it was not.
///
/// ## The order is a decision, not the order these were written in
///
/// Build 12's field test called this screen disorganised, and the specific
/// complaint underneath that word was that it read as **one undifferentiated
/// list**: the fold fell somewhere in the middle of it, and consent, the
/// permissions and the account all sat below the fold with nothing to mark
/// them out. Headings existed, but every heading looked like every other one,
/// so seven of them in a column read as no structure at all.
///
/// So the page is four **bands**, separated by rules — the only separator on
/// the screen, which is what makes it mean something. Inside a band, headings
/// separate sections; between bands, a rule does. The bands descend by how
/// much of the runner's record each one decides:
///
///  1. **Where you stand** — the name, and either the account or the plain
///     statement that there is not one. It leads because nothing below it can
///     be judged without it: whether backup can be switched on at all depends
///     on whether there is an account, and this is the band that says.
///  2. **What the app may do with your running** — backup consent, then what
///     the app is allowed to read off the phone. The two decisions on this
///     screen with any weight, and the two a runner comes back here to check.
///  3. **What neither of those touches** — how a distance is printed, and what
///     the app says about itself. Reversible in a tap, consequential to
///     nothing, and correspondingly far down.
///  4. **Leaving** — one row, alone, at the foot.
///
/// **Band 4 is the exception that proves the ordering.** Ranked by consequence
/// it would come first: deleting the account decides more about the record
/// than anything else here. It is last because it is the only control on this
/// screen that cannot be undone, and an irreversible control is placed by the
/// cost of reaching it *by accident* rather than by its importance. The danger
/// tint is the same argument in colour (ADR-0009), and the confirmation screen
/// behind it is the same argument again.
///
/// **Backup consent moved up a band rather than down.** ADR-0012's cost
/// function turns on the question not being something a runner has to go
/// looking for, and this switch is also where consent is *withdrawn* — which
/// must be at least as easy as giving it was. It used to sit below the unit
/// picker, below a rule, below the fold. Band 2 puts it in the first
/// screenful, directly under the block that says whether there is an account
/// for a grant to attach to: strictly more findable than before, and now
/// beside the thing it depends on.
///
/// Takes its dependencies as parameters like every other screen here, so it
/// renders against fakes in tests and the preview harness.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.unit,
    required this.settings,
    this.onUnitChanged,
    this.memberSince,
    this.appVersion = kAppVersion,
    this.auth = const AuthRepository(),
    this.deleter = const AccountDeletionService(),
    this.consentStore,
    this.backupHealthStore,
    this.eraser,
    this.onBackupGranted,
    this.health,
    this.introStore,
    this.onNameChanged,
    this.ensureAccount,
    this.entitlements = const SupabaseEntitlements(),
    this.photoStore = const FileProfilePhoto(),
  });

  /// Where workouts recorded elsewhere come from.
  ///
  /// Injected so a test can supply a fake, and defaulted to the real HealthKit
  /// reader so the screen works on a device without this being threaded through
  /// the whole app first. Worth wiring properly at the shell once more than one
  /// screen needs it.
  final WorkoutSource? health;

  /// The unit currently in effect.
  final UnitSystem unit;

  final UnitSettings settings;

  /// Called once the new unit is stored, so the app around this screen can
  /// re-render in the chosen units.
  final ValueChanged<UnitSystem>? onUnitChanged;

  /// When the runner's record starts — their first recorded run. Null when they
  /// have not run yet, which simply drops the line rather than inventing a date.
  final DateTime? memberSince;

  /// Shown at the foot of the page. Injectable so a build that reads the real
  /// bundle version can pass it in; [kAppVersion] is the committed fallback.
  final String appVersion;

  final AuthRepository auth;
  final AccountDeleter deleter;

  /// Where the profile photo is kept. It never leaves the phone — see
  /// [ProfilePhotoStore] for why that is a rule rather than an omission.
  final ProfilePhotoStore photoStore;

  /// Read to **print** where the runner stands, never to unlock anything.
  ///
  /// The coach's own gate is the server's; this screen only ever draws a
  /// sentence. See [CoachSubscription].
  final EntitlementRepository entitlements;

  /// Where the backup answer lives. Defaults to the platform store.
  final BackupConsentStore? consentStore;

  /// Where the last push's outcome was written down. Defaults to the platform
  /// store, which is the same file `main.dart` hands the backup — this screen
  /// and the push path find it through the factory rather than by being wired
  /// to each other, exactly as they already do for consent. Naming it
  /// `backupHealthStore` rather than `healthStore` because [health] on this
  /// screen is HealthKit, and two unrelated meanings of "health" one field
  /// apart is a trap.
  final BackupHealthStore? backupHealthStore;

  /// Removes what is already stored when consent is withdrawn. Null skips the
  /// erase, which is what the preview harness wants.
  final BackupErasure? eraser;

  /// Pushes what this phone already holds, once consent has just been given.
  ///
  /// **Granting used to write the answer and stop.** `backfill()` had exactly
  /// two callers, both at launch inside `HomeShell`, so a runner who created an
  /// account in Settings and turned backup on uploaded nothing at all -- not
  /// then, and not until the next cold start. They had said yes and watched
  /// nothing happen, which is the same evidence as a backup that does not work.
  final Future<void> Function()? onBackupGranted;

  /// The other home for the runner's name — the one that answers when there is
  /// no account.
  ///
  /// **The name row used to write to auth metadata and nowhere else**, which
  /// made it useless to exactly the people who had just supplied a name: a
  /// runner with no account saw "Nothing in particular" under a heading that
  /// only appeared if they had already been running, and any correction they
  /// made went into a session that did not exist. The intro records the name
  /// against the install; this is that same store, so the row reads and writes
  /// what the coach is actually using.
  ///
  /// Null keeps an edit in memory for the session.
  final IntroStore? introStore;

  /// Reports a changed name upwards, so the shell that opened this screen stops
  /// handing the coach the old one. Signed in, the auth stream would eventually
  /// say so; signed out there is no stream to say anything.
  final ValueChanged<String?>? onNameChanged;

  /// Raises sign-up and resolves true once there is a session.
  ///
  /// **Backup is the second gate an account stands at**, alongside asking for a
  /// plan. Everything else here works with nobody signed in, because the
  /// on-device database is the source of truth (CLAUDE.md rule 1) — but a
  /// backup switch is a promise to put this runner's data somewhere it can be
  /// attributed to them, and with no account there is no such place. The switch
  /// would have flipped on, written consent, and mirrored nothing.
  ///
  /// Null means the caller has already decided an account is not required —
  /// the preview harness and tests that are not about this.
  final Future<bool> Function()? ensureAccount;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late UnitSystem _unit = widget.unit;
  bool _saving = false;

  /// What the coach calls them. Held in state rather than read from the
  /// repository on every build so the row updates the moment it is changed,
  /// without waiting on an auth event to come back round.
  ///
  /// Seeded from the account, then topped up from the install store once that
  /// read comes back — see [_loadName]. Starting from the account rather than
  /// waiting for both means the row is right immediately for anybody signed in
  /// and right one frame later for anybody not.
  late String? _name = widget.auth.currentName;

  late final IntroStore _introStore =
      widget.introStore ?? InMemoryIntroStore(done: true);

  late final BackupConsentStore _consentStore =
      widget.consentStore ?? createBackupConsentStore();
  BackupConsent _consent = BackupConsent.unknown;
  bool _consentBusy = false;

  late final BackupHealthStore _backupHealthStore =
      widget.backupHealthStore ?? createBackupHealthStore();
  BackupHealth _backupHealth = const BackupHealth();

  @override
  void initState() {
    super.initState();
    unawaited(_loadConsent());
    unawaited(_loadBackupHealth());
    unawaited(_loadName());
    unawaited(_loadSubscription());
    unawaited(_loadLocation());
    unawaited(_loadPhoto());
  }

  /// The avatar, read once and held so it can be drawn synchronously. An
  /// avatar that resolves a Future rebuilds into place after the rest of the
  /// screen has drawn, which reads as a flicker.
  File? _photo;

  Future<void> _loadPhoto() async {
    final File? f = await widget.photoStore.read();
    if (!mounted) return;
    setState(() => _photo = f);
  }

  /// The support page, which has been live and CI-pinned the whole time with
  /// nothing in the app pointing at it.
  Future<void> _openSupport() async {
    final Uri uri = Uri.parse(kSupportUrl);
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    if (!mounted) return;
    // Says where it is when the browser will not open. A dead support link is
    // worse than a long one — the same reasoning as LegalScreen's terms row.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open support. It is at $uri')),
    );
  }

  /// Null until the read lands, which is not the same as [CoachSubscription.none]
  /// — one means "we have not looked yet", the other "you have nothing". The
  /// row draws nothing at all while it is null, because a settings screen that
  /// flashes *Free* at a paying subscriber for half a second is worse than one
  /// that takes half a second to fill in.
  CoachSubscription? _subscription;

  Future<void> _loadSubscription() async {
    final CoachSubscription read = await widget.entitlements.subscription();
    if (!mounted) return;
    setState(() => _subscription = read);
  }

  /// Fills in the name for a runner whose account does not hold one.
  ///
  /// The account wins where it has an answer: it is what travels between
  /// devices and what every other reader consults. The install store answers
  /// for the ordinary new case, where there is no account at all.
  Future<void> _loadName() async {
    if (_name != null) return;
    final local = await _introStore.readName();
    if (!mounted || local == null) return;
    setState(() => _name = local);
  }

  Future<void> _loadConsent() async {
    final value = await _consentStore.read();
    if (mounted) setState(() => _consent = value);
  }

  /// Read once on open rather than watched. The backup writes this file from
  /// the push path, which does not run while somebody is sitting on Settings,
  /// so there is nothing to keep up with.
  Future<void> _loadBackupHealth() async {
    final value = await _backupHealthStore.read();
    if (mounted) setState(() => _backupHealth = value);
  }

  /// Granting starts the mirror. Withdrawing stops it AND removes what is
  /// already stored — a switch that only stopped future uploads would be a
  /// pause dressed up as a withdrawal.
  ///
  /// **Granting needs an account first.** The mirror writes rows attributed to
  /// a user; with nobody signed in there is nothing to attribute them to, so
  /// the switch would have read "On" while every push failed on a row-level
  /// policy — the exact shape of promise this section exists to stop the app
  /// making. Withdrawal is never gated: consent must be at least as easy to
  /// take back as it was to give, and somebody who is not signed in has by
  /// definition nothing left to withdraw anyway.
  Future<void> _setConsent(BackupConsent next) async {
    if (_consentBusy || next == _consent) return;

    // Before the optimistic flip below, not after it. Asked afterwards, the
    // switch would slide to On, raise a sign-up, and then have to slide back
    // when it was refused — which reads as the app changing its mind.
    if (next == BackupConsent.granted && !widget.auth.isSignedIn) {
      final signedIn =
          await (widget.ensureAccount?.call() ?? Future<bool>.value(true));
      // The gate pushed a route and awaited it, so this screen may be gone.
      if (!signedIn || !mounted) return;
    }

    setState(() {
      _consent = next;
      _consentBusy = true;
    });
    // Local first, so uploads stop before the erase is attempted rather than
    // racing it.
    await _consentStore.write(next);

    var erased = true;
    if (next == BackupConsent.declined) {
      erased = await widget.eraser?.eraseAll() ?? true;
    } else if (next == BackupConsent.granted) {
      // After the consent write, never before: the mirror reads consent on
      // every call, so a backfill started first would push under an answer that
      // had not been recorded yet.
      await widget.onBackupGranted?.call();
    }
    if (!mounted) return;
    setState(() => _consentBusy = false);
    if (!erased) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Backup is off, but your stored data could not be removed. '
            'Try again when you have a connection.',
          ),
        ),
      );
    }
  }

  Future<void> _select(UnitSystem unit) async {
    if (unit == _unit || _saving) return;
    setState(() {
      _unit = unit;
      _saving = true;
    });
    // save() is contractually non-throwing and writes locally first, so the
    // choice holds even with no network — no failure branch to show here.
    await widget.settings.save(unit);
    if (!mounted) return;
    setState(() => _saving = false);
    widget.onUnitChanged?.call(unit);
  }

  /// Changes what the coach calls this runner.
  ///
  /// The intro accepts any name at all, on the grounds that a name is not a
  /// format and every rule that rejects one rejects somebody real. That is only
  /// a fair trade if a typo can be put right afterwards, and until this existed
  /// it could not be: the name was written once at sign-up and read back
  /// forever, in the coach's brief, on every screen that greets them.
  ///
  /// Cleared rather than rejected when left blank, so "do not use a name" is a
  /// reachable answer rather than a validation error.

  /// What Geolocator says right now, for the Permissions row's value.
  ///
  /// Read here as well as inside `PermissionsSection` rather than plumbed down
  /// from it: the index shows the value without opening the screen that owns
  /// it, so the index has to be able to ask. It is one cheap platform call on
  /// a screen that is already doing three.
  LocationPermission? _location;

  Future<void> _loadLocation() async {
    try {
      final p = await Geolocator.checkPermission();
      if (mounted) setState(() => _location = p);
    } on Object {
      // A platform without location is not an error state, it is a blank one.
      if (mounted) setState(() => _location = null);
    }
  }

  /// Distance, as a sheet rather than a segmented control on the index.
  ///
  /// The control itself was fine; what it cost was the two lines under it
  /// explaining that the setting is shared with Lift and that runs are stored
  /// in metric regardless. Both are worth saying and neither is worth saying
  /// every time somebody opens Settings, so they say it here, where the choice
  /// is made.
  Future<void> _pickUnit() async {
    final picked = await showModalBottomSheet<UnitSystem>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Center(child: SheetHandle()),
                const SizedBox(height: AppSpacing.lg),
                Text('Distance', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.md),
                for (final option in UnitSystem.values)
                  SettingsRow(
                    title: option == UnitSystem.metric ? 'Kilometres' : 'Miles',
                    trailing: option == _unit
                        ? const Icon(
                            Icons.check,
                            size: 20,
                            color: AppColors.textPrimary,
                          )
                        : const SizedBox(width: 20),
                    onTap: () => Navigator.of(sheetContext).pop(option),
                  ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Shared with Lift — changing it here changes it there too. '
                  'Your runs are always stored in metric.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null && picked != _unit) await _select(picked);
  }

  Future<void> _openAccount() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StatefulBuilder(
          // The photo and the name live in THIS state, so the pushed screen
          // reads them rather than owning them and needs telling when they
          // change. Rebuilding only the index would leave a screen still
          // showing the avatar somebody has just replaced.
          builder: (_, setScreenState) => AccountScreen(
            auth: widget.auth,
            deleter: widget.deleter,
            subscription: _subscription,
            memberSince: widget.memberSince,
            name: _name,
            photo: _photo,
            onSignOut: _signOut,
            onEditName: () async {
              await _editName();
              setScreenState(() {});
            },
            onPickPhoto: () async {
              await _pickPhoto();
              setScreenState(() {});
            },
            onCreateAccount: _createAccount,
            onRemovePhoto: _photo == null
                ? null
                : () async {
                    await widget.photoStore.clear();
                    await _evictPhoto();
                    if (!mounted) return;
                    setState(() => _photo = null);
                    setScreenState(() {});
                  },
          ),
        ),
      ),
    );
    // The account may have been deleted or the plan changed while that screen
    // was open, so the card is re-read rather than trusted.
    if (mounted) {
      await _loadSubscription();
      if (mounted) setState(() {});
    }
  }

  /// Picks a photo and copies it into the app's own storage.
  ///
  /// **No permission is requested and none is declared on Android.** The
  /// plugin uses the system photo picker, which hands back one file the person
  /// chose and grants no access to the library. On iOS the usage string in
  /// Info.plist is still required — its absence is a crash rather than a
  /// refusal, because iOS terminates an app that reaches a protected resource
  /// without one.
  Future<void> _pickPhoto() async {
    try {
      final XFile? picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // Downscaled on the way in. A modern phone camera produces a 4000px
        // image and this is drawn at 96px; keeping the original would spend
        // several megabytes of the runner's storage on an avatar.
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 88,
      );
      if (picked == null) return;
      final File? saved = await widget.photoStore.write(File(picked.path));
      await _evictPhoto();
      if (!mounted || saved == null) return;
      setState(() => _photo = saved);
    } on Object {
      // A cancelled pick, a file that cannot be read, a platform with no
      // picker. None of it is worth an error state on a settings screen.
    }
  }

  /// Drops the old bytes from Flutter's image cache.
  ///
  /// The file keeps one path for the life of the install, and the cache is
  /// keyed by path — so without this, choosing a second photo draws the first.
  Future<void> _evictPhoto() async {
    final File? old = _photo;
    if (old != null) await FileImage(old).evict();
  }

  Future<void> _openBackup() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        // A [StatefulBuilder] so the pushed screen can redraw itself. The
        // consent lives in THIS state — the gate, the erase and the backfill
        // all hang off it — so the screen reads it rather than owning it, and
        // needs telling when it changes. Calling only the index's setState
        // would leave a switch that has been flipped still drawn as it was.
        builder: (_) => StatefulBuilder(
          builder: (_, setScreenState) => BackupScreen(
            consent: _consent,
            health: _backupHealth,
            busy: _consentBusy,
            onChanged: (next) async {
              await _setConsent(next);
              setScreenState(() {});
              if (mounted) setState(() {});
            },
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openPermissions() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PermissionsScreen(health: widget.health),
      ),
    );
    // The runner may have changed a permission in the OS settings app while
    // that screen was open, so the value on the index is re-read rather than
    // trusted.
    if (mounted) await _loadLocation();
  }

  Future<void> _editName() async {
    // `TextFormField` with an `initialValue` rather than a controller of our
    // own, deliberately: a controller created here has to be disposed here,
    // and disposing it the moment `showDialog` returns kills it while the
    // dialog is still animating out — the field rebuilds against a disposed
    // notifier and throws. This field owns its controller and outlives the
    // route properly.
    var draft = _name ?? '';
    final given = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('What should the coach call you?'),
        content: TextFormField(
          initialValue: draft,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'Your name',
            helperText: 'Leave it empty and the coach will not use a name.',
            // A dialog is narrower than the field this was written for, and
            // helper text is one line unless told otherwise — so the sentence
            // explaining the escape hatch was itself cut off at "will not u...".
            helperMaxLines: 2,
          ),
          onChanged: (v) => draft = v,
          onFieldSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: <Widget>[
          AppTextButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(draft),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // A dismissed dialog pops null, which is not the same as an empty string:
    // one means "changed my mind", the other means "no name, thanks".
    if (given == null || !mounted) return;

    // **Both homes, every time.** The account is where a name travels from
    // device to device; the install store is where it lives for the runner who
    // has no account, which is now the ordinary one. Writing only the first is
    // what made this row a no-op for most of the people who reach it. Writing
    // only the second would drop the name on a second phone.
    //
    // `updateName` on a signed-out repository would be a round trip with no
    // session behind it, so it is skipped rather than allowed to throw.
    if (widget.auth.isSignedIn) await widget.auth.updateName(given);
    await _introStore.writeName(given);
    if (!mounted) return;

    final trimmed = given.trim();
    final next = trimmed.isEmpty ? null : trimmed;
    setState(() => _name = next);
    widget.onNameChanged?.call(next);
  }

  /// Signs the runner in, or up, from the account section.
  ///
  /// The same gate the backup switch and the plan flow raise, reached
  /// deliberately rather than by walking into it. Somebody who has decided they
  /// want an account should not have to flip a switch they may not want in
  /// order to be offered one.
  Future<void> _createAccount() async {
    await (widget.ensureAccount?.call() ?? Future<bool>.value(false));
    // Rebuilt either way: a completed sign-up changes every row in this
    // section, and a refused one leaves them exactly as they were.
    if (mounted) setState(() {});
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Sign out?'),
        content: const Text(
          'Your runs stay on this device. Sign back in to sync them.',
        ),
        actions: <Widget>[
          AppTextButton(
            label: 'Stay signed in',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Settings is pushed *over* [AuthGate], so signing out swaps the tree
    // underneath this route while leaving the route itself on top: the dialog
    // closed, the account line still read the same address, and signing out
    // looked like a button that did nothing. Drop back to the root so what the
    // gate just built — the signed-out flow — is what the runner actually sees.
    //
    // Captured before the await rather than read after it: the context may be
    // gone by then, and a navigator cannot be looked up from a dead one.
    final navigator = Navigator.of(context);
    await widget.auth.signOut();
    if (!mounted) return;
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = widget.auth.currentEmail;
    final signedIn = widget.auth.isSignedIn;

    // ── The shape of this screen ────────────────────────────────────────────
    //
    // **An index, not an essay.** What stood here was four bands of rows, each
    // with a sentence under it, plus three explanatory paragraphs — roughly two
    // and a half screens of scrolling to reach a version number. Every sentence
    // was true and each was written to be read once; together they meant a
    // runner opening Settings for the fifth time read five explanations to
    // check one switch.
    //
    // A settings index has one job: show what everything is set to, without
    // touching anything. So each row carries its value on the right — `Miles`,
    // `Not set up`, `Location on` — and the explanations moved to the screens
    // where the settings are actually changed.
    //
    // Two of those moves were not cosmetic:
    //
    //  * **Backup.** Its paragraph was the only disclosure on the path where a
    //    runner finds the switch in Settings and flips it — no prompt is raised
    //    there. So the switch moved WITH the words, to [BackupScreen], rather
    //    than the words being cut.
    //  * **Permissions.** Four rows and a five-line iOS-paths paragraph, on a
    //    screen everybody opens, for text nobody reads until the day they need
    //    it. Now one row saying whether location is on.
    //
    // **Then it was too empty**, which is the correction to the correction: it
    // went from two and a half screens to half of one, and empty reads as
    // unfinished rather than economical. Three changes answer that, and none of
    // them is padding. The header became a profile rather than an address. The
    // rows gained an About group — which surfaced a genuine omission, since the
    // support page has been live and CI-pinned the whole time with nothing in
    // the app pointing at it. And the footer is pinned to the bottom instead of
    // floating under the last button with a third of a screen below it.
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        // A column of a scroll view and a footer, rather than a list with the
        // footer as its last child: the version belongs at the bottom of the
        // SCREEN, and as a list item it sat wherever the content happened to
        // end.
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                children: <Widget>[
                  // Who this is — a face, a name, and what they are paying,
                  // where there was a heading and a bare address.
                  Entrance(
                    child: _ProfileCard(
                      email: signedIn ? email : null,
                      name: _name,
                      photo: _photo,
                      subscription: _subscription,
                      onCreateAccount: signedIn ? null : _createAccount,
                      // Always, not only when signed in: the name and the
                      // photo live behind this card and both exist before an
                      // account does.
                      onOpen: _openAccount,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // **One row, and that is honest.** `Coach calls you` sat
                  // here too until the header became a profile, and then the
                  // name was on the screen twice -- once as the card's
                  // headline and once as this group's value. A header states
                  // identity and a detail screen edits it; repeating it is the
                  // kind of thing that reads as an oversight because it is
                  // one. It lives under Account > Details now, a tap away
                  // behind the face it belongs to.
                  Entrance(
                    index: 1,
                    child: SettingsGroup(
                      label: 'Preferences',
                      children: <Widget>[
                        SettingsRow(
                          title: 'Distance',
                          value: _unit == UnitSystem.metric
                              ? 'Kilometres'
                              : 'Miles',
                          onTap: _saving ? null : _pickUnit,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  Entrance(
                    index: 2,
                    child: SettingsGroup(
                      label: 'Your data',
                      children: <Widget>[
                        SettingsRow(
                          title: 'Back up my data',
                          value: backupRowValue(_consent),
                          onTap: _openBackup,
                        ),
                        SettingsRow(
                          title: 'Permissions',
                          value: locationRowValue(_location),
                          onTap: _openPermissions,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // **About was a single button and is now the group it should
                  // have been.** Adding it surfaced a real omission rather than
                  // filling space: mgkfitness.mgkcodes.com/run/support has been
                  // live and pinned by a CI check the whole time, both store
                  // listings point at it, and nothing inside the app did — so a
                  // runner whose backup was failing had no route to a person.
                  Entrance(
                    index: 3,
                    child: SettingsGroup(
                      label: 'About',
                      children: <Widget>[
                        SettingsRow(title: 'Support', onTap: _openSupport),
                        SettingsRow(
                          title: 'Privacy & legal',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => LegalScreen(
                                auth: widget.auth,
                                deleter: widget.deleter,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Debug builds only: enter the app as a seeded runner. Last,
                  // under a divider, because it is a tool rather than a setting
                  // — and absent entirely from a release bundle.
                  if (kDebugMode) ...<Widget>[
                    const Divider(
                      height: AppSpacing.xxl,
                      color: AppColors.elevated,
                    ),
                    DevPersonaSection(
                      // The shell this screen was pushed over is rebuilt when
                      // the persona changes, so going back to a stale route
                      // would show the previous runner's app. Return to the
                      // new one.
                      onSwitched: () => Navigator.of(
                        context,
                      ).popUntil((route) => route.isFirst),
                    ),
                    // Which model answers. Under the persona because the two
                    // compose: pick a runner worth talking about, then ask
                    // several models about them and compare.
                    const DevCoachModelSection(),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                '$kProductName ${widget.appVersion} · MGKCodes',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Who this is, in one card: a face, a name, and what they are paying for.
///
/// It was a `SectionLabel`, a bare bold address and two rows — four elements
/// for two facts, and the address was the only thing on the screen not sitting
/// in a row. Then it was a card with three grey lines, one of which repeated an
/// instruction the account screen already gives.
///
/// **The hierarchy is the fix.** A settings header answers "is this me?" and
/// the thing that answers it fastest is a face, then a name. The address is
/// confirmation rather than identity, and the plan is a fact — `Coach · Active`
/// — not the instruction `manage it in Google Play`, which belongs one level
/// down where somebody has gone looking for it.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.email,
    required this.name,
    required this.photo,
    required this.subscription,
    required this.onCreateAccount,
    required this.onOpen,
  });

  /// Null when signed out, which is an ordinary state: the app opens on a
  /// working tracker with no account (ADR-0019).
  final String? email;

  final String? name;
  final File? photo;

  /// Null until the read lands, which is not the same as [CoachSubscription.none]
  /// — one means "we have not looked yet", the other "you have nothing". The
  /// line is omitted while it is null, because a card that flashes *Free* at a
  /// paying subscriber for half a second is worse than one that fills in.
  final CoachSubscription? subscription;

  final VoidCallback? onCreateAccount;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (email == null) {
      return AppCard(
        // The profile, not the sign-up. The name and the photo are behind this
        // card whether or not there is an account, and the invitation to make
        // one is on that screen where it can be explained.
        onTap: onOpen,
        child: Row(
          children: <Widget>[
            // The same avatar signed out: a runner who gave the coach a name
            // in the intro has one before they have an account.
            Avatar(photo: photo, name: name, size: 64),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name ?? 'Create an account',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // States the position rather than selling the fix.
                    'Everything is on this phone only. An account backs up '
                    'your training and lets you ask for a plan.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      );
    }

    return AppCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        children: <Widget>[
          Avatar(photo: photo, name: name, size: 64),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // The name leads where there is one. Somebody who gave none
                // gets the address promoted rather than a placeholder — an
                // empty line reserved for a name they declined to give is a
                // reproach.
                Text(
                  name ?? email!,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (name != null) ...<Widget>[
                  const SizedBox(height: 1),
                  Text(
                    email!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (subscription != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  _PlanLine(subscription!),
                ],
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: 20,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}

/// The plan as a fact, short enough to sit under a name.
///
/// **Three states, not one with adjectives.** Free, paid up, and "the store is
/// chasing a payment" want different sentences and one of them wants a colour.
/// The third is why this is worth drawing: it is the only case where somebody
/// believes they are paying, the coach is locked, and the app would otherwise
/// say nothing. The full explanation is on the account screen; this is the
/// headline.
class _PlanLine extends StatelessWidget {
  const _PlanLine(this.subscription);

  final CoachSubscription subscription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (String text, Color colour) = switch (subscription.standing) {
      // Says what the free app *is* rather than what it lacks: recording is
      // the product, not a trial of one (ADR-0030).
      SubscriptionStanding.none => ('Free', AppColors.textTertiary),
      SubscriptionStanding.active => (
        subscription.tier.label,
        AppColors.textSecondary,
      ),
      SubscriptionStanding.billingRetry => (
        '${subscription.tier.label} · payment failed',
        AppColors.danger,
      ),
      SubscriptionStanding.ended => (
        '${subscription.tier.label} · ended',
        AppColors.textTertiary,
      ),
    };

    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: colour,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
