import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../data/exercise_lookup.dart';
import '../domain/previous_performance.dart';
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
import 'rest_bar.dart';
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
  });

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

  /// How long the next rest runs for. Starts at the default and follows the
  /// lifter's adjustments — see [_adjustRest].
  Duration _restLength = RestTimer.defaultRest;

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_onFocusMoved);
    _ticker?.cancel();
    _clock.dispose();
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

  void _say(String message, {String? action, VoidCallback? onAction}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
          action: action == null
              ? null
              : SnackBarAction(
                  label: action,
                  // An Undo outliving the screen does nothing, rather than
                  // writing into a session that has since been finished.
                  onPressed: () {
                    if (mounted) onAction?.call();
                  },
                ),
        ),
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

  void _startRest() {
    setState(() {
      _rest = RestTimer(startedAt: _clock.value, duration: _restLength);
      _restAlerted = false;
    });
  }

  /// Adjusts the running rest, and remembers the new length for the next one.
  void _adjustRest(Duration by) {
    final rest = _rest;
    if (rest == null) return;
    setState(() {
      _rest = rest.extendedBy(by, _clock.value);
      final next = _restLength + by;
      _restLength = next < _minRest ? _minRest : next;
      if (!_rest!.isDoneAt(_clock.value)) _restAlerted = false;
    });
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
      // of a set.
      _startRest();
      unawaited(AppHaptics.commit());
    }
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
    final choice = await showModalBottomSheet<Object>(
      context: context,
      useSafeArea: true,
      // As tall as its five rows, not capped at 9/16 of the screen — the cap
      // overflowed it by 20px on a short screen — and scrollable below that.
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
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
    if (planner == null) return;

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

    // Back, by arrow or gesture, and Discard all pop — each takes this
    // screen's Undo with it (see [_dropMessages]).
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _dropMessages();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: PhotoBackdrop(
          image: 'assets/images/backgrounds/hero_home.webp',
          scrim: ScrimStrength.quiet,
          child: SafeArea(
            child: Column(
              children: <Widget>[
                _Header(
                  onBack: () => Navigator.of(context).maybePop(),
                  name: _session.name,
                  startedAt: _session.startedAt,
                  clock: _clock,
                  volumeKg: _session.volumeKg,
                  massUnit: widget.massUnit,
                  completedSets: _session.completedSets,
                  movements: _session.exercises.length,
                  canFinish: canFinish,
                  onFinish: _finish,
                ),
                Expanded(
                  child: _session.exercises.isEmpty
                      ? _EmptyState(
                          onAdd: _addExercises,
                          onOpenLibrary: widget.library == null
                              ? null
                              : _openLibrary,
                          onDiscard: _confirmDiscard,
                        )
                      : ListView(
                          // Dragging the list puts the keyboard away — the second
                          // of three ways out, with a tap elsewhere and Done.
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.sm,
                            AppSpacing.lg,
                            AppSpacing.xxl,
                          ),
                          children: <Widget>[
                            for (final exercise in _session.exercises)
                              // Animated, because ticking the last set collapses
                              // the card under the lifter's finger. A jump cut
                              // there reads as the card having been deleted.
                              AnimatedSize(
                                key: ValueKey<String>(exercise.id),
                                duration: AppMotion.fast,
                                curve: AppMotion.standard,
                                alignment: Alignment.topCenter,
                                child: ExerciseCard(
                                  exercise: exercise,
                                  catalogue: _lookup.find(exercise.name),
                                  massUnit: widget.massUnit,
                                  previous: _previousFor(exercise.name),
                                  isCollapsed: _isCollapsed(exercise),
                                  onToggleCollapsed: () =>
                                      _toggleCollapsed(exercise),
                                  onSwap: widget.planner == null
                                      ? null
                                      : () => _swap(exercise),
                                  onAddSet: () => _addSet(exercise),
                                  onRemove: () => _removeExercise(exercise),
                                  onToggle: _toggle,
                                  onCommit: _commit,
                                  focusFor: _node,
                                  onCycleSetType: _cycleType,
                                  onSetMenu: (set) => _setMenu(exercise, set),
                                  onRemoveSet: (set) =>
                                      _removeSet(exercise, set),
                                  onRejected: _refused,
                                ),
                              ),
                            const SizedBox(height: AppSpacing.sm),
                            AppOutlinedButton(
                              onPressed: full ? null : _addExercises,
                              icon: Icons.add,
                              label: 'Add exercise',
                              expand: true,
                            ),
                            if (full)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.xs,
                                ),
                                child: Text(
                                  '${SessionLimits.movements} movements is the '
                                  'most one session holds.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppColors.textTertiary),
                                ),
                              ),
                            const SizedBox(height: AppSpacing.xl),
                            // Here rather than in the header: saving is decided
                            // about the shape of a session after seeing it, and
                            // the list is where the shape is.
                            //
                            // Not for a session from a saved workout — that
                            // workout learns from it at Finish, and a save here
                            // made a second copy — and a statement once saved,
                            // so a second tap cannot make a third.
                            if (widget.library != null && !_fromLibrary)
                              Center(
                                child: _savedToLibrary
                                    ? Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: AppSpacing.sm,
                                        ),
                                        child: Text(
                                          'Saved to your workouts',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
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
                            // Destructive, so it sits at the bottom of the list
                            // rather than in the chrome.
                            Center(
                              child: AppTextButton(
                                label: 'Discard session',
                                onPressed: _confirmDiscard,
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.danger,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),

                // The keyboard bar takes the rest bar's place while a number is
                // being typed — the keyboard covers that edge anyway.
                if (editing && keyboardUp)
                  _KeyboardBar(
                    onPrevious: () => _moveFocus(-1),
                    onNext: () => _moveFocus(1),
                    onLogSet: _logFocusedSet,
                    onDone: () => FocusManager.instance.primaryFocus?.unfocus(),
                  )
                else if (_rest != null)
                  ValueListenableBuilder<DateTime>(
                    valueListenable: _clock,
                    builder: (context, now, _) => RestBar(
                      timer: _rest!,
                      now: now,
                      onAdjust: _adjustRest,
                      onDismiss: () => setState(() => _rest = null),
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

/// Previous, next, *Log set*, Done — above the keyboard, while a number is
/// being typed.
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
      child: Material(
        color: AppColors.surface,
        child: Padding(
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
      ),
    );
  }
}

/// Session name, the three numbers, and **Finish**.
///
/// Finish lives here rather than as a full-width slab pinned to the bottom. That
/// slab read as the screen's purpose — the thing you came to press — when
/// actually it is what you do once, at the end, after logging everything.
class _Header extends StatelessWidget {
  const _Header({
    required this.onBack,
    required this.name,
    required this.startedAt,
    required this.clock,
    required this.volumeKg,
    required this.massUnit,
    required this.completedSets,
    required this.movements,
    required this.canFinish,
    required this.onFinish,
  });

  /// Leaves the session running and goes back. Safe and non-destructive: every
  /// change is already persisted, the session stays open, and Track offers to
  /// resume it — which is why this needs no confirmation.
  final VoidCallback onBack;

  final String name;
  final DateTime startedAt;

  /// Read by the elapsed figure alone — see `_ActiveSessionScreenState._clock`.
  final ValueListenable<DateTime> clock;

  /// Canonical kilograms. Summed before rounding, then rendered once.
  final double volumeKg;

  final MassUnit massUnit;
  final int completedSets;
  final int movements;
  final bool canFinish;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconButton(
                onPressed: onBack,
                icon: Icons.arrow_back,
                color: AppColors.textSecondary,
                tooltip: 'Back — the session stays open',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const SectionLabel('In progress'),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: theme.textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              AppFilledButton(
                // Nothing ticked is not a session. Finishing would put an empty
                // row in the log and an empty card in the cross-app feed.
                onPressed: canFinish ? onFinish : null,
                label: 'Finish',
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // **A card, not a strip**, and **two by two, not four across** —
          // four in a row collided at 390pt ("1410 kg3").
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: ValueListenableBuilder<DateTime>(
                        valueListenable: clock,
                        builder: (context, now, _) => StatBlock(
                          label: 'Elapsed',
                          value: _clockText(now.difference(startedAt).abs()),
                          // Crosses an hour and gains two characters.
                          shrinkToFit: true,
                        ),
                      ),
                    ),
                    Expanded(
                      child: StatBlock(
                        label: 'Volume',
                        value: volumeKg == 0
                            ? '—'
                            : Mass.kilograms(volumeKg).label(massUnit),
                        shrinkToFit: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: StatBlock(
                        label: 'Sets',
                        value: '$completedSets',
                        shrinkToFit: true,
                      ),
                    ),
                    Expanded(
                      child: StatBlock(
                        label: 'Movements',
                        value: '$movements',
                        shrinkToFit: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _clockText(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onAdd,
    required this.onOpenLibrary,
    required this.onDiscard,
  });

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
              'The clock is running',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Add the first movement when you get to it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(label: 'Add exercise', onPressed: onAdd),
            if (onOpenLibrary != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              AppOutlinedButton(
                onPressed: onOpenLibrary,
                label: 'Your workouts',
                expand: true,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            AppTextButton(
              label: 'Discard session',
              onPressed: onDiscard,
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            ),
          ],
        ),
      ),
    );
  }
}
