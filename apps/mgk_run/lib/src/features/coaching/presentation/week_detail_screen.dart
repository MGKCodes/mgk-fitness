import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../../../core/units/distance.dart';
import '../../../core/units/unit_system.dart';
import '../data/adaptation_service.dart';
import '../domain/pace_model.dart';
import '../domain/runner_profile.dart';
import '../domain/training_plan.dart';
import 'session_labels.dart';
import 'week_adjust_sheet.dart';

/// One week's sessions across Mon–Sun, with **deterministic** target paces
/// (derived in Dart from the runner's time trial — never the model). Off days
/// read as rest. A provisional week (filled from the skeleton) says so.
class WeekDetailScreen extends StatefulWidget {
  const WeekDetailScreen({
    super.key,
    required this.week,
    required this.slot,
    required this.paces,
    this.focusedWeekday,
    this.adaptation,
    this.profile,
    this.onRevised,
    this.unit = UnitSystem.metric,
  });

  final TrainingWeek week;
  final SkeletonWeek slot;
  final TrainingPaces paces;

  /// The day the runner arrived on (1=Mon..7=Sun), when they opened the week by
  /// tapping one. That day is scrolled into view and its row sits raised.
  ///
  /// Optional: opening the week as a whole — from the plan arc, or a preview —
  /// passes nothing and every day reads the same, which is correct. Out-of-range
  /// values are ignored rather than asserted; a bad weekday should cost the
  /// emphasis, not the screen.
  final int? focusedWeekday;

  /// When both are provided, an "Adjust" action lets the runner revise the week
  /// from a natural-language request. Null hides it (e.g. a static preview).
  final AdaptationService? adaptation;
  final RunnerProfile? profile;

  /// Persists an approved revision. Without it the revised week lives only in
  /// this route's state and dies when the runner closes the screen, so the
  /// revision is awaited before the screen claims the week was updated.
  final Future<void> Function(TrainingWeek revised)? onRevised;

  final UnitSystem unit;

  @override
  State<WeekDetailScreen> createState() => _WeekDetailScreenState();
}

class _WeekDetailScreenState extends State<WeekDetailScreen> {
  late TrainingWeek _week = widget.week;

  /// Marks the focused row so it can be scrolled to. Held for the life of the
  /// state: the focus is where the runner came *from* and does not move.
  final GlobalKey _focusedKey = GlobalKey();

  bool get _canAdjust => widget.adaptation != null && widget.profile != null;

  /// The focused weekday, or null when there isn't a valid one.
  int? get _focused {
    final day = widget.focusedWeekday;
    return day != null && day >= DateTime.monday && day <= DateTime.sunday
        ? day
        : null;
  }

  @override
  void initState() {
    super.initState();
    if (_focused != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealFocusedDay());
    }
  }

  /// Brings the tapped day into view. Sunday sits below the fold on a small
  /// phone, so without this the screen would open on Monday and the runner
  /// would have to hunt for the day they just tapped.
  void _revealFocusedDay() {
    final target = _focusedKey.currentContext;
    if (!mounted || target == null) return;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    Scrollable.ensureVisible(
      target,
      duration: still ? Duration.zero : AppMotion.base,
      curve: AppMotion.entrance,
      // Above centre: the tapped day, and enough of the days around it to keep
      // the runner's place in the week.
      alignment: 0.3,
    );
  }

  Future<void> _openAdjust() async {
    final revised = await showModalBottomSheet<TrainingWeek>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => WeekAdjustSheet(
        adaptation: widget.adaptation!,
        week: _week,
        slot: widget.slot,
        profile: widget.profile!,
        unit: widget.unit,
      ),
    );
    if (revised == null || !mounted) return;

    // Persist before showing the revision, so the screen never displays — or
    // confirms — a change that isn't on disk.
    final persist = widget.onRevised;
    if (persist != null) {
      try {
        await persist(revised);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't save that change. The week is unchanged."),
          ),
        );
        return;
      }
      if (!mounted) return;
    }

    setState(() => _week = revised);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Week updated.')));
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focused;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Week ${widget.slot.index} · ${phaseLabel(widget.slot.phase)}',
        ),
        actions: _canAdjust
            ? <Widget>[
                IconButton(
                  icon: const Icon(Icons.tune),
                  tooltip: 'Adjust week',
                  onPressed: _openAdjust,
                ),
              ]
            : null,
      ),
      body: SafeArea(
        // A Column rather than a ListView: seven rows are cheap to build at
        // once, and a lazy list leaves the off-screen row unbuilt — so the one
        // day that most needs scrolling to would have no context to scroll to.
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_week.provisional) const _ProvisionalBanner(),
              for (var day = 1; day <= 7; day++)
                _DayRow(
                  key: day == focused ? _focusedKey : null,
                  name: weekdayName(day),
                  session: _week.runOn(day),
                  paces: widget.paces,
                  unit: widget.unit,
                  focused: day == focused,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProvisionalBanner extends StatelessWidget {
  const _ProvisionalBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.chipAll,
        border: Border.all(color: AppColors.elevated),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Provisional week, filled from your plan. It will refine as your '
              'coach catches up.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    super.key,
    required this.name,
    required this.session,
    required this.paces,
    required this.unit,
    this.focused = false,
  });

  final String name;
  final PlannedSession? session;
  final TrainingPaces paces;
  final UnitSystem unit;

  /// The day the runner tapped to get here. See [WeekDetailScreen.focusedWeekday].
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final isRest = s == null;

    // Focus is *elevation*, not fill. Today — the one thing this design
    // language emphasises — is a solid silver chip with inverted ink
    // (week_calendar.dart); reusing that here would make "the day you tapped"
    // and "now" indistinguishable. Raising the card one step up the surface
    // ladder is a different move in the same greyscale, and reads as "this row,
    // out of the seven" without claiming to be today.
    final row = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        color: focused ? AppColors.elevated : null,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 40,
              child: Text(
                name,
                style: TextStyle(
                  color: switch ((focused, isRest)) {
                    (true, _) => AppColors.textPrimary,
                    (false, true) => AppColors.textTertiary,
                    (false, false) => AppColors.textSecondary,
                  },
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: isRest
                  ? const Text(
                      'Rest',
                      style: TextStyle(color: AppColors.textTertiary),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          kindLabel(s.kind),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _paceLabel(s.kind, paces),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
            ),
            if (!isRest)
              Text(
                Distance.meters(
                  s.distanceMeters,
                ).format(unit, fractionDigits: 1),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );

    if (!focused) return row;
    // Emphasis that only exists in pixels is emphasis a screen reader never
    // hears. Merged so the row is announced as one thing that is selected,
    // rather than a bare "selected" node beside four unrelated labels.
    return MergeSemantics(child: Semantics(selected: true, child: row));
  }

  String _paceLabel(SessionKind kind, TrainingPaces paces) {
    final pace = paceFor(kind, paces);
    return pace == null ? '' : 'target ${pace.format(unit)}';
  }
}
