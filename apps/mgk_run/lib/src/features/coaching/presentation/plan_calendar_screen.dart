import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../domain/plan_builder.dart';
import '../domain/plan_headline.dart';
import '../domain/session_status.dart';
import '../domain/stored_plan.dart';
import '../domain/training_plan.dart';
import 'plan_screen.dart' show kPlannedWeekHorizon;
import 'session_labels.dart';
import 'week_calendar.dart';

/// Every week of the block as a calendar, scrolled through.
///
/// The Plan tab shows only the week the runner is in; this is where the rest
/// lives. Opening on the current week rather than at week one, because a runner
/// eleven weeks in does not want to scroll past eleven weeks they have run.
///
/// **Weeks past the horizon are drawn back, not withheld.** Sessions firm up
/// about a week ahead, so week nine's Tuesday is a projection — the runner can
/// see it, and can see that it is provisional, which is more honest than either
/// hiding it or presenting it as settled.
class PlanCalendarScreen extends StatefulWidget {
  const PlanCalendarScreen({
    super.key,
    required this.plan,
    required this.weeks,
    this.now,
    this.statusFor,
    this.onOpenWeek,
    this.unit = UnitSystem.metric,
  });

  final StoredPlan plan;

  /// The sessions for each week index. Weeks absent from this map are shown as
  /// their skeleton shape rather than invented on the spot.
  final Map<int, TrainingWeek> weeks;

  final DateTime? now;

  /// Status for a weekday of the *current* week.
  final SessionStatus? Function(int weekday)? statusFor;

  final void Function(SkeletonWeek slot, int weekday)? onOpenWeek;
  final UnitSystem unit;

  @override
  State<PlanCalendarScreen> createState() => _PlanCalendarScreenState();
}

class _PlanCalendarScreenState extends State<PlanCalendarScreen> {
  late final ScrollController _scroll;

  /// Roughly one pane plus its gap. Only used to jump near the current week on
  /// open, so that it is built; [_landOnCurrent] then puts it exactly.
  static const double _paneExtent = 208;

  /// The current week's pane, so the first frame can be corrected onto it.
  final GlobalKey _currentWeek = GlobalKey();

  /// The day the calendar is read from: today once the plan has started, its
  /// first day before then (ADR-0034), so a rhythm does not open on the last
  /// week of a cycle it has not begun.
  DateTime _anchor(DateTime today) =>
      widget.plan.hasStartedBy(today) ? today : widget.plan.startDate;

  @override
  void initState() {
    super.initState();
    final today = widget.now ?? DateTime.now();
    final current = widget.plan.weekIndexOn(_anchor(today));
    _scroll = ScrollController(
      initialScrollOffset: (current - 1) * _paneExtent,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _landOnCurrent());
  }

  /// Puts the current week's title at the top of the list, with the list's own
  /// top gap above it.
  ///
  /// **The estimate alone overshot.** Panes are not all [_paneExtent] tall, so
  /// "(week - 1) × 208" landed a runner three weeks in with "This week" and
  /// its dates tucked under the app bar and the first card starting half way
  /// down (screen board P4). The estimate still runs first, because a pane has
  /// to be built before it can be measured; this corrects it before anybody
  /// has seen it.
  void _landOnCurrent() {
    if (!mounted || !_scroll.hasClients) return;
    final pane = _currentWeek.currentContext?.findRenderObject();
    if (pane == null) return;
    final position = _scroll.position;
    final reveal = RenderAbstractViewport.of(
      pane,
    ).getOffsetToReveal(pane, 0).offset;
    _scroll.jumpTo(
      (reveal - AppSpacing.md).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = widget.now ?? DateTime.now();
    final started = widget.plan.hasStartedBy(today);
    final anchor = _anchor(today);
    final current = widget.plan.weekIndexOn(anchor);
    final weeks = widget.plan.skeleton.weeks;

    return Scaffold(
      // The themed bar, not a transparent one. Overriding it to transparent
      // over a transparent Scaffold took the title and the back arrow with it,
      // and cost a back route the runner needs more than they need the
      // photograph running the last 56px to the top of the screen.
      appBar: AppBar(title: const Text('Your calendar')),
      body: PhotoBackdrop(
        image: 'assets/images/backgrounds/in-run.jpg',
        scrim: ScrimStrength.grounded,
        opacity: 0.34,
        alignment: Alignment.topCenter,
        child: SafeArea(
          child: ListView.separated(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            itemCount: weeks.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, i) {
              final slot = weeks[i];
              final isCurrent = slot.index == current;
              final beyondHorizon =
                  slot.index > current + kPlannedWeekHorizon - 1;

              return Entrance(
                key: isCurrent ? _currentWeek : null,
                index: i,
                child: WeekCalendar(
                  week:
                      widget.weeks[slot.index] ??
                      // Not yet materialised: draw the deterministic fill so a
                      // future week is a shape rather than a blank pane. It is
                      // marked provisional above, which is what makes showing
                      // it honest.
                      buildFallbackWeek(slot, widget.plan.profile),
                  weekStart: widget.plan.dateFor(
                    weekIndex: slot.index,
                    weekday: 1,
                    on: anchor,
                  ),
                  // Nothing is today before the plan starts.
                  today: isCurrent && started ? today : null,
                  statusFor: isCurrent && started ? widget.statusFor : null,
                  dimmed: beyondHorizon,
                  title: isCurrent && !started
                      ? planStartsLabel(widget.plan.startDate)
                      : (isCurrent ? 'This week · ' : '') +
                            weekRangeLabel(
                              widget.plan.dateFor(
                                weekIndex: slot.index,
                                weekday: 1,
                                on: anchor,
                              ),
                            ),
                  subtitle: _subtitle(slot, beyondHorizon),
                  unit: widget.unit,
                  onTapDay: widget.onOpenWeek == null
                      ? null
                      : (weekday) => widget.onOpenWeek!(slot, weekday),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _subtitle(SkeletonWeek slot, bool provisional) => weekSubtitle(
    widget.plan,
    slot,
    unit: widget.unit,
    provisional: provisional,
    week: widget.weeks[slot.index],
  );
}
