import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../sync/presentation/backup_scheduler.dart';
import '../data/exercise_lookup.dart';
import '../data/starters.dart';
import '../domain/session.dart';
import '../domain/workout_library.dart';
import '../domain/workout_template.dart';
import 'resume_or_discard.dart';
import 'workout_editor_screen.dart';

/// What the library was left with.
sealed class LibraryOutcome {
  const LibraryOutcome();
}

/// Start this workout — throwing away the session that was open first, when
/// the lifter said so.
final class StartWorkout extends LibraryOutcome {
  const StartWorkout(this.workout, {this.discardingOpen = false});

  final SavedWorkout workout;

  /// True only when the lifter answered "Discard it" to "Push is still open".
  final bool discardingOpen;
}

/// Go back to the session that was already open.
final class ResumeOpen extends LibraryOutcome {
  const ResumeOpen();
}

/// **Your workouts** — the lifter's library, and what a session starts from.
///
/// Each row does the two things a row is for: **Start**, and a "…" for Edit,
/// Duplicate and Delete. Tapping the row opens it in place to every movement
/// with its sets and reps.
///
/// **There is no preview any more** (the design review's finding 7). A row
/// opened a sheet that showed the workout and offered Start, which was one
/// screen between the lifter and the thing they came to do; what the sheet
/// showed now opens inside the row, and Start is on the row itself. Nor is
/// there a builder (R5): a workout comes from a session saved as one, or from
/// one of the three starters, and the editor is for changing one that exists.
///
/// Pops with a [LibraryOutcome], or null.
class WorkoutLibraryScreen extends StatefulWidget {
  const WorkoutLibraryScreen({
    super.key,
    required this.library,
    required this.lookup,
    this.log = const <Session>[],
    this.startLabel = 'Start',
    this.openSessionName,
    this.openAt,
    this.backup,
  });

  final WorkoutLibrary library;
  final ExerciseLookup lookup;

  /// For "last done", and the editor's recent movements.
  final List<Session> log;

  /// `Start`, or `Use` when the library was opened to fill a session that is
  /// already running.
  final String startLabel;

  /// The session already open, when there is one. Start then asks whether to
  /// resume it or discard it — a session is never overwritten without being
  /// asked, and the library no longer says "no" and leaves it at that.
  final String? openSessionName;

  /// The workout whose row starts open — Track's card opens the library at
  /// the workout it shows.
  final String? openAt;

  /// Where backup stands, for the mark on a row not yet backed up. Null is a
  /// build with no server.
  final ValueListenable<BackupStatus>? backup;

  static Future<LibraryOutcome?> open(
    BuildContext context, {
    required WorkoutLibrary library,
    required ExerciseLookup lookup,
    List<Session> log = const <Session>[],
    String startLabel = 'Start',
    String? openSessionName,
    String? openAt,
    ValueListenable<BackupStatus>? backup,
  }) => Navigator.of(context).push<LibraryOutcome>(
    MaterialPageRoute<LibraryOutcome>(
      builder: (_) => WorkoutLibraryScreen(
        library: library,
        lookup: lookup,
        log: log,
        startLabel: startLabel,
        openSessionName: openSessionName,
        openAt: openAt,
        backup: backup,
      ),
    ),
  );

  @override
  State<WorkoutLibraryScreen> createState() => _WorkoutLibraryScreenState();
}

enum _RowAction { edit, duplicate, delete }

class _WorkoutLibraryScreenState extends State<WorkoutLibraryScreen> {
  List<SavedWorkout>? _saved;

  /// The row opened to its movements. One at a time: two open rows is a
  /// comparison nobody asked for, pushing the rest of the list off the screen.
  late String? _expanded = widget.openAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await widget.library.all();
    if (!mounted) return;
    setState(() => _saved = saved);
  }

  void _say(String message, {String? action, VoidCallback? onAction}) =>
      AppToast.show(context, message, actionLabel: action, onAction: onAction);

  Future<void> _start(SavedWorkout workout) async {
    final open = widget.openSessionName;
    if (open == null) {
      Navigator.of(context).pop(StartWorkout(workout));
      return;
    }
    final choice = await askResumeOrDiscard(
      context,
      openName: open,
      wantedName: workout.name,
    );
    if (!mounted || choice == null) return;
    Navigator.of(context).pop(switch (choice) {
      OpenSessionChoice.resume => const ResumeOpen(),
      OpenSessionChoice.discardAndStart => StartWorkout(
        workout,
        discardingOpen: true,
      ),
    });
  }

  Future<void> _more(SavedWorkout workout) async {
    final choice = await showGlassSheet<_RowAction>(
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
              SectionLabel(workout.name),
              const SizedBox(height: AppSpacing.sm),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () => Navigator.of(sheet).pop(_RowAction.edit),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Duplicate'),
                onTap: () => Navigator.of(sheet).pop(_RowAction.duplicate),
              ),
              const Divider(height: AppSpacing.lg),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColors.danger,
                ),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: AppColors.danger),
                ),
                onTap: () => Navigator.of(sheet).pop(_RowAction.delete),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _RowAction.edit:
        await _edit(workout);
      case _RowAction.duplicate:
        final copy = await widget.library.save(
          name: uniqueWorkoutName(workout.name, <String>[
            for (final w in _saved ?? const <SavedWorkout>[]) w.name,
          ]),
          movements: workout.movements,
        );
        await _load();
        _say('${copy.name} added.');
      case _RowAction.delete:
        await _delete(workout);
    }
  }

  Future<void> _edit(SavedWorkout workout) async {
    await Navigator.of(context).push<SavedWorkout>(
      MaterialPageRoute<SavedWorkout>(
        builder: (_) => WorkoutEditorScreen(
          library: widget.library,
          lookup: widget.lookup,
          workout: workout,
          log: widget.log,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _delete(SavedWorkout workout) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete ${workout.name}?'),
        content: const Text(
          'The sessions you did from it stay in your log. Only the saved '
          'workout goes.',
        ),
        actions: <Widget>[
          AppTextButton(
            label: 'Keep it',
            onPressed: () => Navigator.of(dialog).pop(false),
          ),
          AppTextButton(
            label: 'Delete',
            onPressed: () => Navigator.of(dialog).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.library.remove(workout.id);
    await _load();
    if (!mounted) return;
    _say(
      '${workout.name} deleted.',
      action: 'Undo',
      onAction: () async {
        await widget.library.restore(workout.id);
        await _load();
      },
    );
  }

  /// One of the three starting points (R11), with an Undo that takes back
  /// exactly what was added.
  Future<void> _addStarter(WorkoutSplit split) async {
    final added = await addStarter(widget.library, split);
    await _load();
    if (!mounted) return;
    unawaited(AppHaptics.selection());
    _say(
      added.length == 1
          ? '${added.single.name} added.'
          : '${split.name} added: ${added.length} workouts.',
      action: 'Undo',
      onAction: () async {
        for (final w in added) {
          await widget.library.remove(w.id);
        }
        await _load();
      },
    );
  }

  /// The glass header's height below the status bar, until it has been
  /// measured.
  static const double _headerHeight = 72;

  /// What the header measured, status bar included.
  double? _header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saved = _saved;
    return Scaffold(
      backgroundColor: AppColors.bg,
      // Track's photograph, carried on so the library reads as a step further
      // into the same place. At texture strength — this screen does not lead
      // with it — and open through the middle, where the rows are, so the
      // glass has something to be glass over.
      body: PhotoBackdrop(
        image: 'assets/images/backgrounds/hero_track.webp',
        child: Builder(
          builder: (context) {
            final top = MediaQuery.paddingOf(context).top;
            final bottom = MediaQuery.paddingOf(context).bottom;
            // Measured, not assumed: its two lines grow with the phone's text
            // size, and the list starts wherever the header actually ends.
            final header = _header ?? top + _headerHeight;
            final padding = EdgeInsets.fromLTRB(
              AppSpacing.lg,
              header + AppSpacing.md,
              AppSpacing.lg,
              bottom + AppSpacing.xxl,
            );
            return Stack(
              children: <Widget>[
                Positioned.fill(
                  // Every row's glass reads one blur of the photograph instead
                  // of taking a pass each — what makes glass rows affordable
                  // in a list. The rows never overlap, which grouping needs.
                  child: BackdropGroup(
                    child: switch (saved) {
                      // Null is "not read yet", empty is "you have none". A
                      // spinner where the empty state belongs tells a new
                      // lifter to wait for something that is never coming.
                      null => const Center(child: CircularProgressIndicator()),
                      final List<SavedWorkout> list when list.isEmpty =>
                        ListView(
                          padding: padding,
                          children: <Widget>[_Starters(onAdd: _addStarter)],
                        ),
                      final List<SavedWorkout> list => ListView(
                        padding: padding,
                        children: <Widget>[
                          for (final (i, workout) in list.indexed)
                            Entrance(
                              index: i,
                              child: _WorkoutRow(
                                key: ValueKey<String>(workout.id),
                                workout: workout,
                                lastDone: lastDone(workout.id, widget.log),
                                expanded: _expanded == workout.id,
                                startLabel: widget.startLabel,
                                onToggle: () => setState(
                                  () => _expanded = _expanded == workout.id
                                      ? null
                                      : workout.id,
                                ),
                                onStart: () => _start(workout),
                                onMore: () => _more(workout),
                                backup: widget.backup,
                              ),
                            ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'To add one, finish a session and save it as a '
                            'workout.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    },
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _Measured(
                    onHeight: (h) {
                      if (h != _header) setState(() => _header = h);
                    },
                    child: GlassSurface.bar(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.sm,
                          top + AppSpacing.xs,
                          AppSpacing.lg,
                          AppSpacing.sm,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 56),
                          child: Row(
                            children: <Widget>[
                              AppIconButton(
                                icon: Icons.arrow_back,
                                tooltip: 'Back',
                                color: AppColors.textSecondary,
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    const SectionLabel('Library'),
                                    Text(
                                      'Your workouts',
                                      style: theme.textTheme.titleLarge,
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
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WorkoutRow extends StatelessWidget {
  const _WorkoutRow({
    super.key,
    required this.workout,
    required this.lastDone,
    required this.expanded,
    required this.startLabel,
    required this.onToggle,
    required this.onStart,
    required this.onMore,
    this.backup,
  });

  final SavedWorkout workout;
  final DateTime? lastDone;
  final bool expanded;
  final String startLabel;
  final VoidCallback onToggle;
  final VoidCallback onStart;
  final VoidCallback onMore;
  final ValueListenable<BackupStatus>? backup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabular = <FontFeature>[const FontFeature.tabularFigures()];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        expanded: expanded,
        child: GlassSurface(
          grouped: true,
          onTap: onToggle,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          workout.name,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          workoutLine(workout, lastDone),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // A quiet mark on a workout this phone has and the server
                  // does not — only for somebody signed in, for whom that is
                  // news. Signed out, every row would carry it, which says
                  // nothing.
                  if (backup case final backup?)
                    ValueListenableBuilder<BackupStatus>(
                      valueListenable: backup,
                      builder: (context, status, _) =>
                          status.state == BackupState.signedOut ||
                              status.isBackedUp(workout.id)
                          ? const SizedBox.shrink()
                          : const Padding(
                              padding: EdgeInsets.only(right: AppSpacing.sm),
                              child: Tooltip(
                                message: 'Not backed up yet',
                                child: Icon(
                                  Icons.cloud_off_outlined,
                                  size: 16,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                    ),
                  SmallPill(label: startLabel, onPressed: onStart),
                  AppIconButton(
                    icon: Icons.more_horiz,
                    tooltip: 'More for ${workout.name}',
                    color: AppColors.textSecondary,
                    onPressed: onMore,
                  ),
                ],
              ),
              AnimatedSize(
                duration: AppMotion.base,
                curve: AppMotion.standard,
                alignment: Alignment.topCenter,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(
                          0,
                          AppSpacing.sm,
                          AppSpacing.md,
                          0,
                        ),
                        child: Column(
                          children: <Widget>[
                            for (final (i, m) in workout.movements.indexed)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.xs,
                                ),
                                child: Row(
                                  children: <Widget>[
                                    // At least 24 wide, so the names line up;
                                    // wider when the text is, rather than
                                    // breaking "10" in two.
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        minWidth: 24,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: AppSpacing.xs,
                                        ),
                                        child: Text(
                                          '${i + 1}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: AppColors.textTertiary,
                                                fontFeatures: tabular,
                                              ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        m.name,
                                        style: theme.textTheme.bodyMedium,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(
                                      prescription(m),
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: AppColors.textSecondary,
                                            fontFeatures: tabular,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(
                          top: AppSpacing.xs,
                          right: AppSpacing.md,
                        ),
                        child: Text(
                          // The movements themselves: "6 movements" does not
                          // tell a Push from a Pull in a list of six.
                          workout.movementNames.take(3).join(' · ') +
                              (workout.movementCount > 3
                                  ? ' + ${workout.movementCount - 3} more'
                                  : ''),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nothing saved yet: the three starting points (R11), each one tap from being
/// in the library — because an empty list with a builder under it was the same
/// blank page the library was meant to solve.
class _Starters extends StatelessWidget {
  const _Starters({required this.onAdd});

  final ValueChanged<WorkoutSplit> onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Nothing saved yet', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Start from one of these, or finish a session and save it as a '
          'workout.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final (i, split) in starterSplits.indexed)
          Entrance(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _StarterRow(split: split, onAdd: () => onAdd(split)),
            ),
          ),
      ],
    );
  }
}

class _StarterRow extends StatelessWidget {
  const _StarterRow({required this.split, required this.onAdd});

  final WorkoutSplit split;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = templatesOf(split);
    // The sessions by name, unless the one session is the split's own name
    // again: "Full Body · Full Body" said nothing twice.
    final holds = sessions.length == 1
        ? '1 workout'
        : sessions.map((t) => t.name).join(', ');
    return GlassSurface(
      grouped: true,
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: 88,
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  0.2126, 0.7152, 0.0722, 0, 0, //
                  0.2126, 0.7152, 0.0722, 0, 0, //
                  0.2126, 0.7152, 0.0722, 0, 0, //
                  0, 0, 0, 1, 0, //
                ]),
                child: Image.asset(
                  split.image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: AppColors.surface),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(split.name, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            '${split.daysPerWeek} days a week · $holds',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    SmallPill(label: 'Add', onPressed: onAdd),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `3 × 8`, or `3 sets` when there is no rep target.
String prescription(TemplateMovement m) => m.repTarget == null
    ? '${m.sets} ${m.sets == 1 ? 'set' : 'sets'}'
    : '${m.sets} × ${m.repTarget}';

/// `6 movements · 18 sets · last done 23 Sep`, the line under a workout's name.
String workoutLine(SavedWorkout w, DateTime? lastDone) => <String>[
  '${w.movementCount} ${w.movementCount == 1 ? 'movement' : 'movements'}',
  '${w.setCount} ${w.setCount == 1 ? 'set' : 'sets'}',
  lastDone == null ? 'not done yet' : 'last done ${_shortDate(lastDone)}',
].join(' · ');

String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Reports its child's height after layout — so what sits under a header can
/// start where the header really ends, at any text size.
class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasured(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) =>
      renderObject.onHeight = onHeight;
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.onHeight);

  ValueChanged<double> onHeight;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h == _last) return;
    _last = h;
    // After the frame: a report during layout would rebuild mid-layout.
    SchedulerBinding.instance.addPostFrameCallback((_) => onHeight(h));
  }
}
