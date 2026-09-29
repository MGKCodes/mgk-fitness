import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../data/exercise_lookup.dart';
import '../domain/previous_performance.dart';
import '../domain/rest_alerts.dart';
import '../domain/rest_lengths.dart';
import '../domain/rest_timer.dart';
import '../../planning/domain/coach_planner.dart';
import '../../planning/domain/planned_movement.dart';
import '../../planning/presentation/swap_sheet.dart';
import '../../sync/presentation/backup_scheduler.dart';
import '../domain/session.dart';
import '../domain/session_recorder.dart';
import '../domain/workout_library.dart';
import 'exercise_card.dart';
import 'exercise_picker_sheet.dart';
import 'finish_sheet.dart';
import 'reorder_sheet.dart';
import 'save_workout_prompt.dart';
import 'session_summary_screen.dart';
import 'workout_library_screen.dart';

/// The screen you are looking at while standing at a rack.
///
/// Everything here is designed around one fact: **the lifter is between sets and
/// does not want to be here.** So the common path is a single tap on the tick —
/// weight and reps are already carried forward, and typing is the exception.
///
/// No spinner blocks a set being logged. Every write goes to the on-device
/// database and returns; the network is not consulted and cannot fail here.
///
/// ## The screen answers before the disk does
///
/// A change shows the moment it is made and is written behind it, through one
/// queue, in order. Storage's answer is adopted when the queue runs dry — an
/// earlier answer arriving while later changes are still queued would put back
/// what the lifter just changed. That queue is also why a fast double-tap on a
/// tick is one tick: both taps read the state the first one left.
class ActiveSessionScreen extends StatefulWidget {
  const ActiveSessionScreen({
    super.key,
    required this.recorder,
    required this.session,
    this.massUnit = MassUnit.kilograms,
    this.lookup,
    this.library,
    this.backup,
    this.onFinished,
    this.planner,
    this.log = const <Session>[],
    this.onSwapped,
    this.onOpenCoach,
    this.startRestOnOpen = false,
    this.now,
    this.editing = false,
    this.restAlerts,
    this.restLengths,
  });

  /// The buzz for a rest that ends while the phone is locked or the app is in
  /// the background. Null is a build (or a test) with no notifications, where
  /// the timer works exactly as it always did: on screen, and buzzing only
  /// while looked at.
  final RestAlerts? restAlerts;

  /// Each movement's rest length, as this lifter last left it. Null starts
  /// every rest at the session's length, as before.
  final RestLengths? restLengths;

  /// Fixing a session that already happened, rather than logging one.
  ///
  /// The same rows, limits and input rules — the recorder is one aimed at that
  /// session (`DriftSessionRecorder.editing`), so every change is written as
  /// it is made. What changes is around the rows: no clock and no rest, the
  /// date where the elapsed time was, **Done** where Finish was, and nothing
  /// that would discard or save a copy. Leaving, by Done or by back, saves:
  /// unticked sets go, as they do at Finish.
  final bool editing;

  final SessionRecorder recorder;

  /// The session as it stood when this screen opened. Kept fresh from here on.
  final Session session;

  /// What the lifter works in. Storage stays kilograms regardless — this only
  /// decides what the fields show and how a typed number is read.
  final MassUnit massUnit;

  /// The 266-movement catalogue, for form images and muscle groups. Injected so
  /// a test can pass a small one instead of loading the lot.
  final ExerciseLookup? lookup;

  /// The lifter's saved workouts. **Null hides both library actions** rather
  /// than showing ones that cannot work — the same rule every other optional
  /// dependency in this app follows, and the honest state for a build with no
  /// on-device database.
  final WorkoutLibrary? library;

  /// Handed to the summary, which says whether this session is backed up.
  final BackupHooks? backup;

  /// Called after a session is finished or discarded, so the caller can reload.
  final VoidCallback? onFinished;

  /// The coach, for swapping a movement mid-session. Null hides the action.
  final CoachPlanner? planner;

  /// Finished sessions, so a suggested replacement's target can be derived from
  /// what this lifter has actually lifted — and so each movement can say what
  /// was lifted on it last time, and seed its first set with it.
  final List<Session> log;

  /// Reports a swap that was accepted, so the plan can record that they did
  /// something other than what it asked for. Without this the plan would go on
  /// claiming a movement they replaced.
  final void Function(String replaced, PlannedMovement with_)? onSwapped;

  /// Opens the coach, from the summary this screen ends on.
  ///
  /// Nothing on the *running* screen uses it: mid-session the coach is reached
  /// from the mark floating over the shell, exactly as it is everywhere else,
  /// and a second entry point here would be a second answer to a question that
  /// already has one. **Null hides the action**, which is the same rule
  /// [planner] and [library] follow.
  final VoidCallback? onOpenCoach;

  /// Opens already resting. **For the preview harness only** — rest is never
  /// restored from disk, so a screenshot of the bar is otherwise unreachable
  /// without driving a tap.
  @visibleForTesting
  final bool startRestOnOpen;

  /// What "now" is, for the elapsed clock. Injected so a test or the preview
  /// harness can pin it — same convention as [PhotosSurface.now]. Null means
  /// the real clock, which is every case outside a test.
  final DateTime? now;

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen>
    with WidgetsBindingObserver {
  late Session _session = widget.session;
  late final ExerciseLookup _lookup = widget.lookup ?? ExerciseLookup();

  /// The clock, **on its own**. It ticks every second and only the two things
  /// reading it — the elapsed figure and the rest bar — redraw. It used to be a
  /// `setState` on the whole screen, which rebuilt every card, every field and
  /// every "last time" line once a second for the length of a session.
  late final ValueNotifier<DateTime> _clock = ValueNotifier<DateTime>(
    widget.now ?? DateTime.now(),
  );
  Timer? _ticker;

  /// The rest since the last set was ticked. Null when nothing is resting.
  ///
  /// Held on the screen rather than in the session, because rest is not part of
  /// what happened: it is not written to the database, and reopening a recovered
  /// session should not resume a countdown from an hour ago.
  RestTimer? _rest;

  /// Whether the buzz for this rest has already gone off, so a timer sitting at
  /// zero does not vibrate once a second until it is dismissed.
  bool _restAlerted = false;

  /// How long the next rest runs for when the movement has no length of its
  /// own. Starts at the default and follows the lifter's adjustments — see
  /// [_adjustRest].
  Duration _restLength = RestTimer.defaultRest;

  /// Each movement's rest, as this lifter last left it, keyed by lowercased
  /// name. Loaded once when the screen opens; see [RestLengths].
  Map<String, Duration> _restLengths = <String, Duration>{};

  /// The movement whose set started the running rest, so an adjustment is
  /// remembered against the right one.
  String? _restMovement;

  /// Whether a background alert is scheduled right now, so leaving the screen
  /// can withdraw it.
  bool _alertScheduled = false;

  /// Whether this screen has already considered offering rest alerts — once a
  /// session at most, and in practice once ever. See [_offerRestAlerts].
  bool _consideredAlerts = false;

  /// Whether this session has already been saved to the library, or was filled
  /// **from** it. Either suppresses the offer to save on the way out.
  bool _savedToLibrary = false;
  bool _filledFromLibrary = false;

  /// Started from a saved workout — here, or from Track with its sets laid out.
  bool get _fromLibrary => _filledFromLibrary || _session.templateId != null;

  /// The name field of the save dialog. See [promptToSaveWorkout] for why it is
  /// owned here rather than built with the dialog.
  final TextEditingController _nameField = TextEditingController();

  /// Exercises the lifter has opened or closed **by hand**, keyed by id. Only
  /// the overrides; a finished movement collapses on its own.
  final Map<String, bool> _expanded = <String, bool>{};

  /// One focus node per field, `<set id>:<field>`, so focus can be moved
  /// between fields by the keyboard bar and flushed before anything reads.
  final Map<String, FocusNode> _focus = <String, FocusNode>{};

  /// "Last time" per movement name, worked out once per session rather than
  /// per card per rebuild — it sorts the whole log to answer.
  final Map<String, PreviousPerformance?> _previous =
      <String, PreviousPerformance?>{};

  /// The list's scroll, which folds the top bar in and drifts the photograph.
  final ScrollController _scroll = ScrollController();

  /// The write queue — see the class comment.
  Future<void> _writes = Future<void>.value();
  int _queued = 0;

  /// When a refused keystroke was last explained, so holding a key down does
  /// not stack a message per repeat.
  DateTime? _lastRefusal;

  bool _isCollapsed(SessionExercise e) => !(_expanded[e.id] ?? !e.isComplete);

  void _toggleCollapsed(SessionExercise e) =>
      setState(() => _expanded[e.id] = _isCollapsed(e));

  PreviousPerformance? _previousFor(String name) => _previous.putIfAbsent(
    name.toLowerCase(),
    () =>
        PreviousPerformance.of(widget.log, name, excludeSessionId: _session.id),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_onFocusMoved);
    if (widget.startRestOnOpen) _startRest();
    unawaited(_loadRestLengths());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      // A pinned clock stays pinned. Ticking it would walk the elapsed time
      // forward from the frozen start and undo the point of injecting it.
      _clock.value = widget.now ?? DateTime.now();
      _alertIfRestOver();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Going to the background is leaving the field: whatever was typed is
    // saved before the operating system can decide to end the process.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    // The phone went in a pocket, or the screen locked, with a rest running:
    // hand the buzz to the operating system. Back in the foreground the
    // screen's own buzz is the one, so the system's is withdrawn — never both.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(_scheduleRestAlert());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_withdrawRestAlert());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_onFocusMoved);
    // A rest belongs to this screen. Leaving it ends the rest, and an alert
    // for a rest nobody is taking would buzz into whatever comes next.
    if (_alertScheduled) unawaited(widget.restAlerts?.cancel());
    _ticker?.cancel();
    _clock.dispose();
    _scroll.dispose();
    _nameField.dispose();
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  // ---- the write queue ------------------------------------------------------

  /// Shows [optimistic] now and writes [write] behind it.
  void _change(
    Session Function(Session session) optimistic,
    Future<Session> Function() write,
  ) {
    setState(() => _session = optimistic(_session));
    _enqueue(write);
  }

  /// Writes in order; adopts storage's version when nothing is queued behind.
  Future<void> _enqueue(Future<Session> Function() write) {
    _queued++;
    final done = _writes.then((_) async {
      Session? stored;
      Object? failure;
      try {
        stored = await write();
      } on Object catch (e) {
        failure = e;
      }
      _queued--;
      if (!mounted) return;
      if (failure != null) {
        // What is on screen may now be ahead of what is stored. Storage is the
        // authority, so it is read back and the lifter is told.
        final current = await widget.recorder.current();
        if (!mounted) return;
        if (current != null) setState(() => _session = current);
        _say(
          failure is SessionLimitReached
              ? 'That would pass ${failure.what}.'
              : 'That change didn\'t save. Try it again.',
        );
        return;
      }
      if (_queued == 0 && stored != null) setState(() => _session = stored!);
    });
    _writes = done;
    return done;
  }

  // ---- messages ---------------------------------------------------------------

  void _say(
    String message, {
    String? action,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 5),
  }) {
    if (ScaffoldMessenger.maybeOf(context) == null) return;
    // On glass, over the session — the same material as its bars.
    AppToast.show(
      context,
      message,
      duration: duration,
      actionLabel: action,
      // An Undo outliving the screen does nothing, rather than writing into a
      // session that has since been finished.
      onAction: action == null
          ? null
          : () {
              if (mounted) onAction?.call();
            },
    );
  }

  /// Takes this screen's message with it when the lifter leaves. The messenger
  /// is the app's, so an Undo shown here otherwise followed them onto the
  /// summary — "Cable Fly removed. Undo", under a session already finished.
  void _dropMessages() =>
      ScaffoldMessenger.maybeOf(context)?.removeCurrentSnackBar();

  void _refused(String why) {
    final now = DateTime.now();
    final last = _lastRefusal;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _lastRefusal = now;
    _say(why);
  }

  // ---- fields and the keyboard bar ---------------------------------------------

  FocusNode _node(SessionSet set, SetField field) => _focus.putIfAbsent(
    '${set.id}:${field.name}',
    () => FocusNode(debugLabel: '${set.id}:${field.name}'),
  );

  /// Every field on screen, in reading order — what the keyboard bar's previous
  /// and next walk. Collapsed movements are skipped; their fields are not there.
  List<String> get _fieldOrder => <String>[
    for (final e in _session.exercises)
      if (!_isCollapsed(e))
        for (final set in e.sets) ...<String>[
          '${set.id}:${SetField.weight.name}',
          '${set.id}:${SetField.reps.name}',
        ],
  ];

  String? get _focusedKey {
    for (final entry in _focus.entries) {
      if (entry.value.hasFocus) return entry.key;
    }
    return null;
  }

  void _onFocusMoved() {
    if (mounted) setState(() {});
  }

  void _moveFocus(int by) {
    final key = _focusedKey;
    final order = _fieldOrder;
    if (key == null) return;
    final at = order.indexOf(key);
    final next = at + by;
    if (at < 0 || next < 0 || next >= order.length) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    _focus[order[next]]?.requestFocus();
  }

  /// Leaves whatever field has focus and waits for its value to be handed
  /// over.
  ///
  /// **Unfocusing is not immediate.** Flutter applies focus changes in a
  /// microtask, and the field hands over its number when it hears it lost
  /// focus — so reading the session straight after `unfocus()` reads it
  /// *before* the number arrives. That is exactly how "Log set" once refused a
  /// set for having no reps while the reps were on screen, then refocused the
  /// field, which cancelled the pending change so the number was never saved.
  Future<void> _settleFields() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
  }

  /// Ticks the set whose field has focus, from the keyboard bar.
  Future<void> _logFocusedSet() async {
    final key = _focusedKey;
    if (key == null) return;
    final setId = key.split(':').first;
    await _settleFields();
    if (!mounted) return;
    for (final s in _session.exercises.expand((e) => e.sets)) {
      if (s.id == setId) {
        if (!s.isCompleted) _toggle(s);
        return;
      }
    }
  }

  // ---- rest ----------------------------------------------------------------------

  /// Buzzes once, the moment rest runs out.
  ///
  /// **This only fires while the app is in the foreground.** A backgrounded
  /// Flutter app has no ticker, so a lifter who pockets their phone gets the
  /// right time when they look — see [RestTimer] — but no buzz.
  void _alertIfRestOver() {
    final rest = _rest;
    if (rest == null || _restAlerted || !rest.isDoneAt(_clock.value)) return;
    _restAlerted = true;
    // The one occasion in this app that earns AppHaptics' stated exception:
    // something the app did on its own, for somebody who cannot look.
    unawaited(AppHaptics.milestone());
  }

  Future<void> _loadRestLengths() async {
    final store = widget.restLengths;
    if (store == null) return;
    final lengths = await store.all();
    if (!mounted) return;
    _restLengths = lengths;
  }

  /// The rest a set of [movement] starts: that movement's own, if the lifter
  /// has ever settled on one, or the session's.
  Duration _lengthFor(String? movement) =>
      (movement == null ? null : _restLengths[movement.toLowerCase()]) ??
      _restLength;

  void _startRest({String? movement}) {
    setState(() {
      _rest = RestTimer(
        startedAt: _clock.value,
        duration: _lengthFor(movement),
      );
      _restMovement = movement;
      _restAlerted = false;
    });
  }

  /// Adjusts the running rest, and remembers the new length for the next one —
  /// this movement's next rest, and the session's default.
  void _adjustRest(Duration by) {
    final rest = _rest;
    if (rest == null) return;
    final movement = _restMovement;
    var next = _lengthFor(movement) + by;
    if (next < _minRest) next = _minRest;
    setState(() {
      _rest = rest.extendedBy(by, _clock.value);
      _restLength = next;
      if (movement != null) _restLengths[movement.toLowerCase()] = next;
      if (!_rest!.isDoneAt(_clock.value)) _restAlerted = false;
    });
    if (movement != null) {
      unawaited(widget.restLengths?.remember(movement, next));
    }
  }

  /// Hands the running rest's buzz to the operating system, if there is still
  /// some rest to run.
  Future<void> _scheduleRestAlert() async {
    final alerts = widget.restAlerts;
    final rest = _rest;
    if (alerts == null || rest == null || widget.editing) return;
    // The screen's clock, like everything else here: at most a second behind
    // the wall, and pinnable in a test.
    if (rest.isDoneAt(_clock.value)) return;
    _alertScheduled = true;
    await alerts.schedule(at: rest.endsAt, title: 'Rest over', body: _nextUp());
  }

  Future<void> _withdrawRestAlert() async {
    if (!_alertScheduled) return;
    _alertScheduled = false;
    await widget.restAlerts?.cancel();
  }

  /// What the alert tells the lifter to go and do: the first set not yet
  /// ticked, in the order the session holds them. The one fact worth reading
  /// on a lock screen.
  String _nextUp() {
    for (final exercise in _session.exercises) {
      for (final set in exercise.sets) {
        if (!set.isCompleted) {
          return 'Next: ${exercise.name}, set ${exercise.labelFor(set)}.';
        }
      }
    }
    return 'Back to it.';
  }

  /// Offers the background buzz, once, the first time a rest starts.
  ///
  /// A toast rather than the system prompt straight away: the prompt is a
  /// one-shot on iOS, and asking cold — before the lifter has seen what it is
  /// for — is how it gets refused. Here it arrives beside the timer it is
  /// about. Letting the toast go by counts as an answer, so it is never
  /// offered twice.
  Future<void> _offerRestAlerts() async {
    final alerts = widget.restAlerts;
    if (alerts == null || _consideredAlerts || widget.editing) return;
    _consideredAlerts = true;
    if (await alerts.asked() || await alerts.allowed()) return;
    if (!mounted) return;
    await alerts.markAsked();
    if (!mounted) return;
    _say(
      'Want a buzz when rest is over, even with your phone locked?',
      action: 'Turn on',
      onAction: () => unawaited(alerts.ask()),
      // Long enough to read and decide with a bar in your hands. Five
      // seconds went by on the emulator before a thumb reached it.
      duration: const Duration(seconds: 10),
    );
  }

  /// Below this, rest is not a rest. Stops repeated −30s taps from setting the
  /// remembered length to zero and silently disabling the feature.
  static const Duration _minRest = Duration(seconds: 15);

  // ---- sets --------------------------------------------------------------------------

  /// The current version of [set] — see [_toggle].
  SessionSet _fresh(SessionSet set) {
    for (final e in _session.exercises) {
      for (final s in e.sets) {
        if (s.id == set.id) return s;
      }
    }
    return set;
  }

  /// Ticks or unticks a set.
  ///
  /// **A tick needs reps.** An empty set ticked is a logged set of nothing —
  /// it counts toward the set total and lifts no weight — so the reps field is
  /// focused instead and the lifter is told why.
  void _toggle(SessionSet tapped) {
    // The row's copy may be a frame old — a field can have just handed over a
    // number on the pointer-down of this same tap — so the set is read fresh.
    final set = _fresh(tapped);
    if (!set.isCompleted && set.reps == 0) {
      _node(set, SetField.reps).requestFocus();
      _say('Add the reps first.');
      return;
    }
    final completing = !set.isCompleted;
    _change(
      (s) => s.mapSet(set.id, (x) => x.copyWith(isCompleted: completing)),
      () => widget.recorder.updateSet(set.id, isCompleted: completing),
    );
    if (completing) {
      // Only on completion. Un-ticking is a correction to the log, not the end
      // of a set — and nobody is resting while fixing last week.
      if (!widget.editing) {
        _startRest(movement: _exerciseOf(set.id)?.name);
        unawaited(_offerRestAlerts());
      }
      unawaited(AppHaptics.commit());
    }
  }

  /// The movement [setId] belongs to, as the session holds it now.
  SessionExercise? _exerciseOf(String setId) {
    for (final e in _session.exercises) {
      if (e.sets.any((s) => s.id == setId)) return e;
    }
    return null;
  }

  void _commit(SessionSet set, int? reps, double? weightKg) {
    _change(
      (s) =>
          s.mapSet(set.id, (x) => x.copyWith(reps: reps, weightKg: weightKg)),
      () => widget.recorder.updateSet(set.id, reps: reps, weightKg: weightKg),
    );
  }

  void _cycleType(SessionSet tapped) {
    final next = _fresh(tapped).setType.next;
    final set = tapped;
    _change(
      (s) => s.mapSet(set.id, (x) => x.copyWith(setType: next)),
      () => widget.recorder.updateSet(set.id, setType: next),
    );
  }

  /// Adds a set. The first set of a movement starts from what was lifted on it
  /// last time; after that, each set carries the one before it.
  void _addSet(SessionExercise exercise) {
    final seed = exercise.sets.isEmpty
        ? _previousFor(exercise.name)?.sets.firstOrNull
        : null;
    _enqueue(
      () => widget.recorder.addSet(
        exercise.id,
        reps: seed?.reps,
        weightKg: seed?.weightKg,
      ),
    );
  }

  void _removeSet(SessionExercise exercise, SessionSet set) {
    _change(
      (s) => s.withoutSet(set.id),
      () => widget.recorder.removeSet(set.id),
    );
    unawaited(AppHaptics.selection());
    _say(
      'Set removed.',
      action: 'Undo',
      onAction: () => _change(
        (s) => s.withSetRestored(exercise.id, set),
        () => widget.recorder.restoreSet(exercise.id, set),
      ),
    );
  }

  /// The set's own menu — its type, and Remove. Reached by holding the label,
  /// for anybody who never finds the swipe.
  Future<void> _setMenu(SessionExercise exercise, SessionSet set) async {
    // As tall as its five rows, not capped at 9/16 of the screen — the cap
    // overflowed it by 20px on a short screen — and scrollable below that.
    final choice = await showGlassSheet<Object>(
      context: context,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
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
              SectionLabel('Set ${exercise.labelFor(set)} · ${exercise.name}'),
              const SizedBox(height: AppSpacing.sm),
              for (final type in SetType.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: SizedBox(
                    width: 28,
                    child: Center(
                      child: Text(
                        type.marker ?? '1',
                        style: Theme.of(sheet).textTheme.titleSmall,
                      ),
                    ),
                  ),
                  title: Text(switch (type) {
                    SetType.working => 'Working set',
                    SetType.warmup => 'Warm-up',
                    SetType.dropSet => 'Drop set',
                    SetType.failure => 'To failure',
                  }),
                  trailing: set.setType == type
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () => Navigator.of(sheet).pop(type),
                ),
              const Divider(height: AppSpacing.lg),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColors.danger,
                ),
                title: const Text(
                  'Remove set',
                  style: TextStyle(color: AppColors.danger),
                ),
                onTap: () => Navigator.of(sheet).pop('remove'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'remove') {
      _removeSet(exercise, set);
    } else if (choice is SetType && choice != set.setType) {
      _change(
        (s) => s.mapSet(set.id, (x) => x.copyWith(setType: choice)),
        () => widget.recorder.updateSet(set.id, setType: choice),
      );
    }
  }

  // ---- movements ----------------------------------------------------------------------

  /// Removes a movement — asking first only when it would take logged work.
  ///
  /// With nothing ticked it goes at once, with Undo: an empty card is cheap to
  /// lose and cheap to get back. With sets ticked the lifter is asked, naming
  /// what goes, because that is an hour's evidence one mistap away from a
  /// ✕ that sits beside the swap icon.
  Future<void> _removeExercise(SessionExercise exercise) async {
    final logged = exercise.sets.where((s) => s.isCompleted).length;
    if (logged > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Remove ${exercise.name}?'),
          content: Text(
            'Its $logged logged ${logged == 1 ? 'set goes' : 'sets go'} with it.',
          ),
          actions: <Widget>[
            AppTextButton(
              label: 'Keep it',
              onPressed: () => Navigator.of(dialog).pop(false),
            ),
            AppTextButton(
              label: 'Remove',
              onPressed: () => Navigator.of(dialog).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _change(
      (s) => s.withoutExercise(exercise.id),
      () => widget.recorder.removeExercise(exercise.id),
    );
    _say(
      '${exercise.name} removed.',
      action: 'Undo',
      onAction: () => _change(
        (s) => s.withExerciseRestored(exercise),
        () => widget.recorder.restoreExercise(exercise),
      ),
    );
  }

  Future<void> _addExercises() async {
    final room = SessionLimits.movements - _session.exercises.length;
    final names = await ExercisePickerSheet.show(
      context,
      lookup: _lookup,
      recent: PreviousPerformance.recentNames(widget.log),
      room: room,
    );
    if (!mounted || names == null) return;
    final chosen = <String>[
      for (final n in names)
        if (n.trim().isNotEmpty) n.trim(),
    ];
    if (chosen.isEmpty) return;
    await _enqueue(() => widget.recorder.addExercises(chosen));
  }

  /// Asks the coach for something else, and applies what the lifter picks —
  /// in the old movement's place, keeping anything already logged on it. See
  /// [SessionRecorder.replaceExercise].
  Future<void> _swap(SessionExercise exercise) async {
    final planner = widget.planner;
    if (planner == null) return _replaceByHand(exercise);

    final choice = await SwapSheet.show(
      context,
      planner: planner,
      session: _session,
      movement: exercise.name,
      log: widget.log,
      unit: widget.massUnit,
    );
    if (choice == null || !mounted) return;

    await _enqueue(
      () => widget.recorder.replaceExercise(
        exercise.id,
        choice.name,
        sets: choice.sets,
        reps: choice.reps,
        weightKg: choice.target?.kilograms,
      ),
    );
    widget.onSwapped?.call(exercise.name, choice);
  }

  /// Opens the reorder sheet and applies the new order, one move at a time,
  /// through the same queue as every other write.
  Future<void> _reorder() async {
    final order = await ReorderSheet.show(
      context,
      exercises: _session.exercises,
    );
    if (!mounted || order == null) return;
    final current = <String>[for (final e in _session.exercises) e.id];
    for (var i = 0; i < order.length && i < current.length; i++) {
      if (current[i] == order[i]) continue;
      final id = order[i];
      current
        ..remove(id)
        ..insert(i, id);
      final to = i;
      await _enqueue(() => widget.recorder.moveExercise(id, to));
    }
  }

  /// Swaps a movement for one the lifter picks, with no coach involved.
  ///
  /// The swap icon used to exist only for a coached lifter, so somebody whose
  /// cable machine was taken could only remove the movement and add another —
  /// losing its place and its set count. Every app the 2026-09-29 research
  /// compared offers a replace mid-workout, free.
  ///
  /// The replacement takes the work that was left: as many sets as were still
  /// unticked, at the reps they were aiming for, at the weight this lifter
  /// last used on the new movement. Logged sets stay where they are, under the
  /// old name, because they were lifted — see [SessionRecorder.replaceExercise].
  Future<void> _replaceByHand(SessionExercise exercise) async {
    final names = await ExercisePickerSheet.show(
      context,
      lookup: _lookup,
      recent: PreviousPerformance.recentNames(widget.log),
      replacing: exercise.name,
    );
    if (!mounted || names == null || names.isEmpty) return;
    final name = names.first.trim();
    if (name.isEmpty || name.toLowerCase() == exercise.name.toLowerCase()) {
      return;
    }
    final left = exercise.sets.where((s) => !s.isCompleted).toList();
    final aimed = (left.isNotEmpty ? left : exercise.sets).firstOrNull;
    await _enqueue(
      () => widget.recorder.replaceExercise(
        exercise.id,
        name,
        sets: left.isNotEmpty ? left.length : exercise.sets.length,
        reps: aimed?.reps,
        weightKg: _previousFor(name)?.sets.firstOrNull?.weightKg,
      ),
    );
  }

  // ---- library ---------------------------------------------------------------------------

  /// Fills an empty session from one of the lifter's saved workouts — the
  /// whole library, opened to choose from, with each movement's sets laid out
  /// from last time.
  Future<void> _openLibrary() async {
    final library = widget.library;
    if (library == null) return;
    final workout = await WorkoutLibraryScreen.open(
      context,
      library: library,
      lookup: _lookup,
      log: widget.log,
      startLabel: 'Use this workout',
    );
    if (workout == null || !mounted) return;
    setState(() => _filledFromLibrary = true);
    await _enqueue(
      () => widget.recorder.fillFromLibrary(
        workoutId: workout.id,
        name: workout.name,
        movements: seedWorkout(workout.movements, widget.log),
        snapshot: TemplateMovement.encode(workout.movements),
      ),
    );
  }

  /// Saves what is on screen to the library, under a name the lifter confirms.
  Future<void> _saveToLibrary() async {
    final library = widget.library;
    if (library == null || _session.exercises.isEmpty) return;
    final name = await promptToSaveWorkout(
      context,
      library: library,
      field: _nameField,
      suggestedName: _session.name,
      movements: workoutMovementsOf(_session),
    );
    if (name == null || !mounted) return;
    setState(() => _savedToLibrary = true);
  }

  // ---- ending -------------------------------------------------------------------------------

  /// Ends the session, after one look at what that means.
  ///
  /// **Finish asks once.** It was a single tap on a button in the header, with
  /// no confirmation and no way back, and unticked sets were quietly kept. The
  /// sheet says what is being saved and — first — what is not.
  Future<void> _finish() async {
    if (widget.editing) return _doneEditing();
    // Whatever is being typed is part of what is finished — settled first, so
    // its write is in the queue before the queue is waited on.
    await _settleFields();
    await _writes;
    if (!mounted) return;

    final confirmed = await FinishSheet.show(
      context,
      session: _session,
      massUnit: widget.massUnit,
    );
    if (confirmed != true || !mounted) return;

    // Finish is a write like any other, so it waits its turn.
    await _writes;

    // What this session did to the workout it came from — read **before**
    // Finish drops the unticked sets, because a row left unticked is a set
    // skipped today, not one removed from the workout.
    final started = _session;
    final snapshot = TemplateMovement.decode(started.templateSnapshot);
    final lesson = snapshot == null || started.templateId == null
        ? null
        : TemplateUpdate.between(snapshot, started);
    final fromLibrary = _fromLibrary;

    final finished = await widget.recorder.finish();
    if (!mounted) return;
    unawaited(AppHaptics.commit());
    widget.onFinished?.call();

    // A replacement is not a pop, so the PopScope below does not see it.
    _dropMessages();
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SessionSummaryScreen(
          session: finished,
          massUnit: widget.massUnit,
          log: widget.log,
          library: widget.library,
          // No offer to save a session that came from the library — its
          // workout learns from it instead — or one saved already, or one
          // with nothing in it.
          offerSave:
              !_savedToLibrary && !fromLibrary && finished.exercises.isNotEmpty,
          templateId: started.templateId,
          lesson: lesson,
          backup: widget.backup,
          onOpenCoach: widget.onOpenCoach,
        ),
      ),
    );
  }

  bool _leaving = false;

  /// Saves an edit to a past session and leaves — by Done or by back.
  ///
  /// Every change is already written; what this adds is Finish's rule, that
  /// an unticked set did not happen, and the stamp that sends the session to
  /// backup. With nothing ticked it stays: a session with no sets is not a
  /// session, and deleting one is its page's job.
  Future<void> _doneEditing() async {
    if (_leaving) return;
    await _settleFields();
    await _writes;
    if (!mounted) return;
    if (_session.completedSets == 0) {
      _say('Tick at least one set — or delete the session from its page.');
      return;
    }
    if (_session.untickedSets > 0) {
      final confirmed = await FinishSheet.show(
        context,
        session: _session,
        massUnit: widget.massUnit,
        title: 'Save ${_session.name}?',
        actionLabel: 'Save',
      );
      if (confirmed != true || !mounted) return;
    }
    await _writes;
    await widget.recorder.finish();
    if (!mounted) return;
    unawaited(AppHaptics.commit());
    widget.onFinished?.call();
    _leaving = true;
    _dropMessages();
    Navigator.of(context).pop();
  }

  Future<void> _confirmDiscard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Discard this session?'),
        content: const Text(
          'Everything you have logged in it is deleted. This cannot be undone.',
        ),
        actions: <Widget>[
          AppTextButton(
            label: 'Keep going',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppTextButton(
            label: 'Discard',
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _settleFields();
    await _writes;
    await widget.recorder.discard();
    if (!mounted) return;
    widget.onFinished?.call();
    Navigator.of(context).pop();
  }

  // ---- building --------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final canFinish = _session.completedSets > 0;
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    final editing = _focusedKey != null;
    final full = _session.exercises.length >= SessionLimits.movements;
    final top = MediaQuery.paddingOf(context).top;
    final empty = _session.exercises.isEmpty;

    // Back, by arrow or gesture, and Discard all pop — each takes this
    // screen's Undo with it (see [_dropMessages]).
    return PopScope(
      // Editing, back is Done: it saves, then leaves.
      canPop: !widget.editing || _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _dropMessages();
        } else if (widget.editing) {
          unawaited(_doneEditing());
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        // **Content between two panes of glass.** The photograph behind, the
        // list scrolling between a bar that folds in at the top and a dock at
        // the bottom — the one material in the app, used where it has
        // something to refract (D6). The cards themselves stay solid.
        body: AnimatedBuilder(
          animation: _scroll,
          builder: (context, child) => PhotoBackdrop(
            image: 'assets/images/backgrounds/hero_home.webp',
            scrim: ScrimStrength.grounded,
            // The photograph drifts at a fraction of the scroll — the depth
            // cue that says the list is in front of it, not painted on it.
            offset: -(_scrollOffset.clamp(0, 600)) * 0.12,
            child: child,
          ),
          child: Column(
            children: <Widget>[
              Expanded(
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: empty
                          ? Padding(
                              padding: EdgeInsets.only(top: top + _barHeight),
                              child: _EmptyState(
                                editing: widget.editing,
                                onAdd: _addExercises,
                                onOpenLibrary: widget.library == null
                                    ? null
                                    : _openLibrary,
                                onDiscard: _confirmDiscard,
                              ),
                            )
                          : _list(context, full: full, top: top),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _TopBar(
                        editing: widget.editing,
                        scroll: _scroll,
                        // Folded from the start when there is no list to
                        // scroll — the empty state has no large title.
                        alwaysFolded: empty,
                        onBack: () => Navigator.of(context).maybePop(),
                        name: _session.name,
                        startedAt: _session.startedAt,
                        clock: _clock,
                        canFinish: canFinish,
                        onFinish: _finish,
                      ),
                    ),
                    if (!empty && !(editing && keyboardUp))
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _Dock(
                          rest: widget.editing ? null : _rest,
                          clock: _clock,
                          onAdd: full ? null : _addExercises,
                          onAdjust: _adjustRest,
                          onDismiss: () => setState(() => _rest = null),
                        ),
                      ),
                  ],
                ),
              ),
              // Below the list rather than over it, so a field brought into
              // view is never brought in under the bar.
              if (editing && keyboardUp)
                _KeyboardBar(
                  onPrevious: () => _moveFocus(-1),
                  onNext: () => _moveFocus(1),
                  onLogSet: _logFocusedSet,
                  onDone: () => FocusManager.instance.primaryFocus?.unfocus(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The top bar's height below the status bar. The list starts under it.
  static const double _barHeight = 56;

  /// Room at the foot of the list for the dock to float over the last card.
  static const double _dockRoom = 120;

  double get _scrollOffset => _scroll.hasClients ? _scroll.offset : 0;

  Widget _list(
    BuildContext context, {
    required bool full,
    required double top,
  }) {
    return ListView(
      controller: _scroll,
      // Dragging the list puts the keyboard away — the second of three ways
      // out, with a tap elsewhere and Done.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        top + _barHeight,
        AppSpacing.lg,
        _dockRoom + MediaQuery.paddingOf(context).bottom,
      ),
      children: <Widget>[
        _LargeTitle(
          editing: widget.editing,
          name: _session.name,
          startedAt: _session.startedAt,
          clock: _clock,
          volumeKg: _session.volumeKg,
          massUnit: widget.massUnit,
          completedSets: _session.completedSets,
          movements: _session.exercises.length,
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final exercise in _session.exercises)
          // Animated, because ticking the last set collapses the card under
          // the lifter's finger. A jump cut there reads as the card having
          // been deleted.
          AnimatedSize(
            key: ValueKey<String>(exercise.id),
            duration: AppMotion.base,
            curve: AppMotion.snappy,
            alignment: Alignment.topCenter,
            child: ExerciseCard(
              exercise: exercise,
              catalogue: _lookup.find(exercise.name),
              massUnit: widget.massUnit,
              previous: _previousFor(exercise.name),
              isCollapsed: _isCollapsed(exercise),
              onToggleCollapsed: () => _toggleCollapsed(exercise),
              onSwap: () => _swap(exercise),
              onAddSet: () => _addSet(exercise),
              onRemove: () => _removeExercise(exercise),
              onToggle: _toggle,
              onCommit: _commit,
              focusFor: _node,
              onCycleSetType: _cycleType,
              onSetMenu: (set) => _setMenu(exercise, set),
              onRemoveSet: (set) => _removeSet(exercise, set),
              onRejected: _refused,
            ),
          ),
        if (full)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              '${SessionLimits.movements} movements is the most one session '
              'holds.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        // With the other decisions about the session's shape, at the foot of
        // the list, and only once there is an order to change.
        if (_session.exercises.length > 1)
          Center(
            child: AppTextButton(
              label: 'Reorder movements',
              icon: Icons.swap_vert,
              onPressed: _reorder,
            ),
          ),
        // Here rather than in the header: saving is decided about the shape
        // of a session after seeing it, and the list is where the shape is.
        //
        // Not for a session from a saved workout — that workout learns from
        // it at Finish, and a save here made a second copy — and a statement
        // once saved, so a second tap cannot make a third.
        if (widget.library != null && !_fromLibrary && !widget.editing)
          Center(
            child: _savedToLibrary
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Text(
                      'Saved to your workouts',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                : AppTextButton(
                    label: 'Save to your workouts',
                    onPressed: _saveToLibrary,
                  ),
          ),
        const SizedBox(height: AppSpacing.sm),
        // Destructive, so it sits at the bottom of the list rather than in
        // the chrome. Not while editing: a session that happened is deleted
        // from its page, softly, with Undo.
        if (!widget.editing)
          Center(
            child: AppTextButton(
              label: 'Discard session',
              onPressed: _confirmDiscard,
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            ),
          ),
      ],
    );
  }
}

/// Previous, next, *Log set*, Done — above the keyboard, while a number is
/// being typed. Glass, like the dock whose place it takes.
///
/// **The iOS number pad has no return key**, and Flutter does not put a field
/// away when you tap elsewhere on a phone. With neither, the only way to close
/// the keyboard was to leave the screen. This is the third way out, and the
/// fast path through a set: type the weight, next, type the reps, log it.
class _KeyboardBar extends StatelessWidget {
  const _KeyboardBar({
    required this.onPrevious,
    required this.onNext,
    required this.onLogSet,
    required this.onDone,
  });

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onLogSet;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    // Part of the field's own tap region. Without it, pressing the bar counted
    // as a tap outside the field: the field let go on the pointer-down, the
    // bar — shown only while a field has focus — was gone before the tap
    // landed, and nothing on it could ever be pressed.
    return TextFieldTapRegion(
      child: GlassSurface.bar(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          children: <Widget>[
            AppIconButton(
              icon: Icons.keyboard_arrow_up,
              onPressed: onPrevious,
              tooltip: 'Previous field',
              color: AppColors.textSecondary,
            ),
            AppIconButton(
              icon: Icons.keyboard_arrow_down,
              onPressed: onNext,
              tooltip: 'Next field',
              color: AppColors.textSecondary,
            ),
            const Spacer(),
            AppTextButton(label: 'Log set', onPressed: onLogSet),
            AppTextButton(
              label: 'Done',
              onPressed: onDone,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The bar across the top: back, and **Finish** — and, once the large title
/// has scrolled under it, the session's name and clock on glass.
///
/// At the top of the list it is only its two controls over the photograph:
/// the large title below says everything, and a pane with nothing under it
/// yet would be glass over glass. It folds in as the title passes beneath,
/// the way a navigation bar does.
class _TopBar extends StatelessWidget {
  const _TopBar({
    this.editing = false,
    required this.scroll,
    required this.alwaysFolded,
    required this.onBack,
    required this.name,
    required this.startedAt,
    required this.clock,
    required this.canFinish,
    required this.onFinish,
  });

  final ScrollController scroll;
  final bool alwaysFolded;

  /// Done instead of Finish, and no running clock — see
  /// [ActiveSessionScreen.editing].
  final bool editing;

  /// Leaves the session running and goes back. Safe and non-destructive: every
  /// change is already persisted, the session stays open, and Track offers to
  /// resume it — which is why this needs no confirmation.
  final VoidCallback onBack;

  final String name;
  final DateTime startedAt;

  /// Read by the clock alone — see `_ActiveSessionScreenState._clock`.
  final ValueListenable<DateTime> clock;
  final bool canFinish;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return AnimatedBuilder(
      animation: scroll,
      builder: (context, _) {
        final offset = scroll.hasClients ? scroll.offset : 0.0;
        // Folded once the name in the large title has passed under the bar.
        final t = alwaysFolded ? 1.0 : ((offset - 28) / 44).clamp(0.0, 1.0);
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: t,
                  child: const GlassSurface.bar(child: SizedBox.expand()),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.08 * t),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.sm,
                top,
                AppSpacing.lg,
                0,
              ),
              child: SizedBox(
                height: _ActiveSessionScreenState._barHeight,
                child: Row(
                  children: <Widget>[
                    AppIconButton(
                      onPressed: onBack,
                      icon: Icons.arrow_back,
                      color: AppColors.textSecondary,
                      tooltip: editing
                          ? 'Back — your changes are saved'
                          : 'Back — the session stays open',
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Opacity(
                        opacity: t,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              name,
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (editing)
                              Text(
                                'Editing',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              )
                            else
                              ValueListenableBuilder<DateTime>(
                                valueListenable: clock,
                                builder: (context, now, _) => Text(
                                  _clockText(now.difference(startedAt).abs()),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: AppColors.textSecondary,
                                    fontFeatures: const <FontFeature>[
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    AppFilledButton(
                      // Nothing ticked is not a session. Finishing would put an
                      // empty row in the log and an empty card in the
                      // cross-app feed.
                      onPressed: canFinish ? onFinish : null,
                      label: editing ? 'Done' : 'Finish',
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The name, large, and the session in one line: elapsed · volume · sets ·
/// movements. It scrolls with the list and hands the name to the bar.
///
/// **One line, not a card of four.** The two-by-two card was the fix for four
/// columns colliding at 390pt ("1410 kg3"); a sentence that wraps cannot
/// collide, and it gives the list the height the card took.
class _LargeTitle extends StatelessWidget {
  const _LargeTitle({
    this.editing = false,
    required this.name,
    required this.startedAt,
    required this.clock,
    required this.volumeKg,
    required this.massUnit,
    required this.completedSets,
    required this.movements,
  });

  final bool editing;
  final String name;
  final DateTime startedAt;
  final ValueListenable<DateTime> clock;

  /// Canonical kilograms. Summed before rounding, then rendered once.
  final double volumeKg;
  final MassUnit massUnit;
  final int completedSets;
  final int movements;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionLabel(editing ? 'Editing' : 'In progress'),
        const SizedBox(height: AppSpacing.xs),
        Text(name, style: theme.textTheme.headlineSmall, maxLines: 2),
        const SizedBox(height: AppSpacing.sm),
        ValueListenableBuilder<DateTime>(
          valueListenable: clock,
          builder: (context, now, _) => Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  // Editing, the date: which session this is, not how long ago
                  // it started.
                  text: editing
                      ? _dateText(startedAt)
                      : _clockText(now.difference(startedAt).abs()),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
                TextSpan(
                  text: <String>[
                    '',
                    if (volumeKg > 0) Mass.kilograms(volumeKg).label(massUnit),
                    '$completedSets ${completedSets == 1 ? 'set' : 'sets'}',
                    '$movements ${movements == 1 ? 'movement' : 'movements'}',
                  ].join('  ·  '),
                ),
              ],
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// The dock: *Add exercise* at rest, the rest timer while resting.
///
/// **The timer grows out of the dock** rather than arriving as a second bar:
/// ticking a set changes what the one control at the bottom of the screen is
/// for, on a spring, and it goes back when rest is over. It replaced a flat
/// strip pinned under the list.
///
/// Rest is still not a mode. Nothing behind the dock is blocked; tick the next
/// set and the timer starts again, ignore it and it sits there.
class _Dock extends StatelessWidget {
  const _Dock({
    required this.rest,
    required this.clock,
    required this.onAdd,
    required this.onAdjust,
    required this.onDismiss,
  });

  final RestTimer? rest;

  /// The screen's one-second ticker, which the countdown repaints from.
  final ValueListenable<DateTime> clock;

  /// Null when the session is full.
  final VoidCallback? onAdd;
  final void Function(Duration by) onAdjust;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final timer = rest;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: GlassSurface.dock(
        padding: EdgeInsets.zero,
        child: AnimatedSize(
          duration: AppMotion.base,
          curve: AppMotion.snappy,
          alignment: Alignment.bottomCenter,
          child: AnimatedSwitcher(
            duration: AppMotion.base,
            switchInCurve: AppMotion.entrance,
            switchOutCurve: AppMotion.exit,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: timer == null
                ? _AddRow(key: const ValueKey<String>('add'), onAdd: onAdd)
                : ValueListenableBuilder<DateTime>(
                    key: const ValueKey<String>('rest'),
                    valueListenable: clock,
                    builder: (context, now, _) => _RestRow(
                      timer: timer,
                      now: now,
                      onAdjust: onAdjust,
                      onDismiss: onDismiss,
                      onAdd: onAdd,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({super.key, required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: AppTextButton(
      label: 'Add exercise',
      icon: Icons.add,
      onPressed: onAdd,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        minimumSize: const Size.fromHeight(52),
      ),
    ),
  );
}

/// The countdown, in the dock: a ring draining with the time left, the time,
/// −30 s / +30 s, and Skip — Done once rest is over.
class _RestRow extends StatelessWidget {
  const _RestRow({
    required this.timer,
    required this.now,
    required this.onAdjust,
    required this.onDismiss,
    required this.onAdd,
  });

  final RestTimer timer;

  /// Driven from the screen's existing one-second ticker rather than a second
  /// one here. See [RestTimer] for why the ticker only controls repainting.
  final DateTime now;
  final void Function(Duration by) onAdjust;
  final VoidCallback onDismiss;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = timer.remainingAt(now);
    final done = timer.isDoneAt(now);
    final quiet = TextButton.styleFrom(
      foregroundColor: AppColors.textSecondary,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 36,
            height: 36,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: 1 - timer.progressAt(now)),
              duration: AppMotion.base,
              builder: (context, left, _) => CircularProgressIndicator(
                value: left,
                strokeWidth: 3,
                backgroundColor: Colors.white.withValues(alpha: 0.10),
                valueColor: AlwaysStoppedAnimation<Color>(
                  done ? AppColors.success : AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // Its natural width, not a share of the row. It was a Flexible
          // beside a Spacer and a flex-3 button group, which left it a fifth
          // of the row and broke "REST OVER" onto two lines (emulator,
          // 2026-09-29). The buttons are what scale down instead.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SectionLabel(
                done ? 'Rest over' : 'Resting',
                emphasis: LabelEmphasis.stat,
                color: done ? AppColors.success : AppColors.textSecondary,
              ),
              Text(
                // Past zero it counts up: how long the lifter has actually
                // rested, not a timer frozen at 0:00 — see
                // [RestTimer.overtimeAt].
                done
                    ? '+${RestTimer.format(timer.overtimeAt(now))}'
                    : RestTimer.format(remaining),
                style: theme.textTheme.titleLarge?.copyWith(
                  // Tabular, or the whole row twitches sideways every second
                  // as the digit widths change.
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
          // Scaled down rather than overflowing, at a large text size on a
          // small phone.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Hidden once rest is over: adding thirty seconds to a
                  // finished timer is not what anyone means by "+30".
                  if (!done) ...<Widget>[
                    AppTextButton(
                      label: '−30s',
                      onPressed: () => onAdjust(const Duration(seconds: -30)),
                      style: quiet,
                    ),
                    AppTextButton(
                      label: '+30s',
                      onPressed: () => onAdjust(const Duration(seconds: 30)),
                      style: quiet,
                    ),
                  ],
                  AppTextButton(
                    label: done ? 'Done' : 'Skip',
                    onPressed: onDismiss,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  AppIconButton(
                    icon: Icons.add,
                    tooltip: 'Add exercise',
                    onPressed: onAdd,
                    color: AppColors.textSecondary,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _clockText(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$sec' : '$m:$sec';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    this.editing = false,
    required this.onAdd,
    required this.onOpenLibrary,
    required this.onDiscard,
  });

  final bool editing;
  final VoidCallback onAdd;

  /// Fills the session from one of the lifter's saved workouts. **Null when
  /// there is no library** — a build with no on-device database.
  final VoidCallback? onOpenLibrary;

  /// Discard has to be reachable **here too**: Finish is disabled with nothing
  /// logged, and backing out leaves the session open.
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              editing ? 'Nothing left in this session' : 'The clock is running',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              editing
                  ? 'Add a movement, or go back and delete the session.'
                  : 'Add the first movement when you get to it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(label: 'Add exercise', onPressed: onAdd),
            if (onOpenLibrary != null && !editing) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              AppOutlinedButton(
                onPressed: onOpenLibrary,
                label: 'Your workouts',
                expand: true,
              ),
            ],
            if (!editing) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              AppTextButton(
                label: 'Discard session',
                onPressed: onDiscard,
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// `Tue 23 Sep` — which session is being edited.
String _dateText(DateTime d) {
  const days = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
}
