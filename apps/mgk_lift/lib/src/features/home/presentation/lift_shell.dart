import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../coaching/presentation/plan_surface.dart';
import '../../profile/presentation/profile_surface.dart';
import '../../settings/domain/unit_preferences.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../stats/domain/session_history.dart';
import '../../tracking/domain/session.dart';
import '../../tracking/domain/session_recorder.dart';
import '../../tracking/presentation/track_controller.dart';
import '../../tracking/presentation/track_surface.dart';

/// The authenticated app: Track / Plan / Profile, with the coach floating over
/// all three.
///
/// Deliberately the same shape as `mgk_run`'s `HomeShell`, because the two apps
/// are one product rather than two apps sharing a palette. Three surfaces, three
/// time horizons:
///
///   Track    now      — the session you are in, or the one you are about to do
///   Plan     ahead    — what the coach has you working toward (paid)
///   Profile  behind   — the log, progress photos, settings
///
/// **The coach is a mark at the shell, not a dock inside a tab** (Run's
/// ADR-0017). A dock can only exist on one screen, so the coach would be present
/// on a third of the app and absent from the rest. Floating it means the answer
/// to "can I ask about this?" is always yes, wherever you are.
///
/// Everything is injected. The real Drift + Supabase stack is wired only in
/// `main.dart`, so tests and previews pass fakes and this file stays free of
/// both.
class LiftShell extends StatefulWidget {
  const LiftShell({
    super.key,
    this.recorder,
    this.units,
    this.history,
    this.onOpenCoach,
    this.hasCoachNote = false,
    this.initialTab = 0,
  });

  /// Owns a session while it is happening. **Null disables starting one**,
  /// which is the right behaviour for a build with no on-device database — the
  /// app still runs and the action reads as unavailable rather than erroring.
  final SessionRecorder? recorder;

  /// Where the lifter's chosen units come from. Null keeps them for the session
  /// at the defaults, which is what tests and previews want.
  final UnitPreferencesStore? units;

  /// The finished sessions Profile reports on. Null reads as an empty log,
  /// which is a real state (a new account) rather than an error.
  final SessionHistory? history;

  /// Opens the conversation. **Null hides the mark entirely** rather than
  /// showing an inert one — a mark that cannot open anything is worse than no
  /// mark. It is null until the coach client exists.
  final VoidCallback? onOpenCoach;

  /// Whether the coach has an observation the lifter has not seen. Drives the
  /// unread dot only; the mark itself is always available when [onOpenCoach] is.
  final bool hasCoachNote;

  /// Which surface to open on. Exists so a preview can address a tab directly —
  /// tapping Flutter's canvas from an automation harness is unreliable.
  final int initialTab;

  @override
  State<LiftShell> createState() => _LiftShellState();
}

class _LiftShellState extends State<LiftShell> {
  late int _index = widget.initialTab;

  /// By name rather than by literal, so re-ordering the bar cannot silently send
  /// someone to the wrong surface. Only the two that are navigated to *in code*
  /// need one — Profile is reachable from the bar alone, and a constant nothing
  /// references is just another thing to keep in step with the list.
  static const int _trackTab = 0;
  static const int _planTab = 1;

  /// Vertical room the floating mark occupies, handed to the surfaces through
  /// MediaQuery so their SafeArea absorbs it. Only applied when there is a mark.
  ///
  /// Its height plus the gap beneath it — a compact pill, since the mark stopped
  /// being full-width.
  static const double _coachMarkReserve = 64;

  /// Held at the shell rather than on a surface, because Track logs in these
  /// units and Profile reports in them — one load, so the two cannot disagree.
  UnitPreferences _units = const UnitPreferences();

  /// Whether a session is already open, so Track can offer to resume rather
  /// than to start. Refreshed whenever a session ends.
  bool _hasOpenSession = false;

  /// The finished log, held at the shell because Profile reports on it and
  /// finishing a session on Track changes it.
  List<Session> _log = const <Session>[];

  @override
  void initState() {
    super.initState();
    unawaited(_loadUnits());
    unawaited(_refreshSession());
    unawaited(_refreshLog());
  }

  Future<void> _loadUnits() async {
    final store = widget.units;
    if (store == null) return;
    final loaded = await store.load();
    if (!mounted || loaded == _units) return;
    setState(() => _units = loaded);
  }

  Future<void> _refreshLog() async {
    final source = widget.history;
    if (source == null) return;
    final loaded = await source.all();
    if (!mounted) return;
    setState(() => _log = loaded);
  }

  Future<void> _refreshSession() async {
    final recorder = widget.recorder;
    if (recorder == null) return;
    final open = await recorder.current() != null;
    if (!mounted || open == _hasOpenSession) return;
    setState(() => _hasOpenSession = open);
  }

  @override
  Widget build(BuildContext context) {
    final openCoach = widget.onOpenCoach;
    return Scaffold(
      body: Stack(
        children: <Widget>[
          // The room the mark needs is reserved *here*, by the thing that knows
          // whether there is a mark. Each surface reserving it itself meant
          // dead space above the nav bar whenever the coach was absent — and
          // three places to remember to keep in step.
          MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: MediaQuery.of(context).padding.copyWith(
                bottom: openCoach == null ? 0 : _coachMarkReserve,
              ),
            ),
            child: IndexedStack(
              index: _index,
              children: <Widget>[
                TrackSurface(
                  onOpenPlan: () => _go(_planTab),
                  hasOpenSession: _hasOpenSession,
                  onStartSession: widget.recorder == null ? null : _openSession,
                ),
                const PlanSurface(),
                ProfileSurface(
                  log: _log,
                  massUnit: _units.mass,
                  onOpenTrack: () => _go(_trackTab),
                  onOpenSettings: _openSettings,
                ),
              ],
            ),
          ),
          // Over every surface, which is the entire point.
          //
          // Right-aligned and only as wide as its label, **not** stretched to
          // the margins. Full-width it sat directly under Track's "Start a
          // session" button as a second pill of the same size and weight, and
          // the eye could not tell which one was the point of the screen. The
          // coach is permanently available, not the thing you came here to do.
          if (openCoach != null)
            Positioned(
              right: AppSpacing.lg,
              bottom: AppSpacing.lg,
              child: _CoachMark(
                hasUnread: widget.hasCoachNote,
                onTap: openCoach,
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: const <NavigationDestination>[
          // "Track", not "Home". In Run the front page is a summary of the day;
          // here it is the thing you are actually doing in the gym, and the
          // label should say so.
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Track',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Plan',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  void _go(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  /// Opens Settings, applying unit changes as they happen rather than on close.
  ///
  /// The shell holds the units, so a change here reaches Track and Profile
  /// without either of them reloading — one source, so the two cannot disagree
  /// about what a lifter works in.
  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          initial: _units,
          store: widget.units,
          onChanged: (prefs) => setState(() => _units = prefs),
        ),
      ),
    );
  }

  Future<void> _openSession() async {
    final recorder = widget.recorder;
    if (recorder == null) return;
    await TrackController(recorder).openSession(
      context,
      massUnit: _units.mass,
      onDone: () {
        unawaited(_refreshSession());
        unawaited(_refreshLog());
      },
    );
    // Also on return, not only via onDone: backing out of the screen with the
    // session still open must leave Track offering to resume it.
    await _refreshSession();
    await _refreshLog();
  }
}

/// The floating way in to the coach.
///
/// A pill that wraps its label rather than filling the width. See the call site
/// for why: at full width it read as a second primary button.
///
/// Placeholder for the reveal treatment `mgk_run` uses, which animates the
/// coach's latest observation before settling. Kept visually identical in
/// resting state so the two apps read the same; the animation comes across when
/// the coach itself does.
class _CoachMark extends StatelessWidget {
  const _CoachMark({required this.hasUnread, required this.onTap});

  final bool hasUnread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassSurface(
      onTap: onTap,
      // Fully rounded, not the control radius. A rounded rectangle at this size
      // reads as a button; a pill reads as a persistent affordance.
      borderRadius: BorderRadius.circular(999),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        // Wrap the content. `Expanded` here is what made it full-width.
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Not `Icons.auto_awesome`: the sparkle is on every AI feature
          // shipped in the last three years, and it says "generated" rather
          // than "someone is paying attention".
          const Icon(
            Icons.chat_bubble_outline,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('Coach', style: theme.textTheme.bodyMedium),
          if (hasUnread) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.textPrimary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
