import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../../../core/units/distance.dart';
import '../../../core/units/unit_system.dart';
import '../domain/prescribed_distance.dart';
import '../domain/session_status.dart';
import '../domain/training_plan.dart';
import 'session_labels.dart';

/// A week as seven days, Monday to Sunday, with today picked out.
///
/// A list of sessions says what to do; a calendar says where you are in the
/// week — what is gone, what is rest, what is coming.
///
/// **One pane, seven cells.** The week is a single sheet of glass with the days
/// marked on it, not seven glass tiles side by side: seven `BackdropFilter`s
/// would cost more and, worse, would read as seven objects rather than as one
/// week. Today is the only thing that breaks the surface.
///
/// **Each cell carries two facts, not four.** The date, and how far. An earlier
/// version also stacked a weekday letter and a session-kind initial into ~48px,
/// which put two unlabelled numbers on top of each other and gave Threshold the
/// letter "T" directly beneath Thursday's "T". The weekday now sits in one
/// header row rather than being repeated seven times.
///
/// **The cell is the bar.** A previous version drew a small vertical bar scaled
/// to the week's longest run — directly above the distance written in words. It
/// looked like a chart, so the eye tried to decode it, and there was nothing to
/// decode: the bar and the number said the same thing, and the bar said it
/// without a scale. The size now shows in the cell's own fill, which costs no
/// space, needs no legend (the number beneath teaches it), and turns a column of
/// weeks into a readable ramp — which is the only reason to stack weeks in a
/// grid at all. The session *kind* is deliberately not here; a 48px cell cannot
/// hold the word "Threshold", and that is what the week list and the day screen
/// are for.
class WeekCalendar extends StatelessWidget {
  const WeekCalendar({
    super.key,
    required this.week,
    required this.weekStart,
    this.today,
    this.statusFor,
    this.onTapDay,
    this.onTapWeek,
    this.title,
    this.subtitle,
    this.dimmed = false,
    this.unit = UnitSystem.metric,
  });

  final TrainingWeek week;

  /// The Monday this week begins on, so day numbers are real dates.
  final DateTime weekStart;

  /// Today, when it falls inside this week. Null when looking at another week —
  /// nothing should read as "now" in a week that is not now.
  final DateTime? today;

  /// The recorded status of a given weekday, if any.
  final SessionStatus? Function(int weekday)? statusFor;

  /// Receives the weekday tapped (1=Mon..7=Sun).
  final void Function(int weekday)? onTapDay;

  /// Opens the week. Set on the pane rather than the cells when the whole
  /// thing is one target.
  final VoidCallback? onTapWeek;

  /// Heading inside the pane — "This week", "Week 4". Kept in the glass rather
  /// than floating above it: a label outside its container belongs to the page,
  /// and this one belongs to the week.
  final String? title;

  /// The line under the heading — the week's planned volume.
  final String? subtitle;

  /// Weeks past the planning horizon, drawn back so they read as provisional
  /// without being hidden.
  final bool dimmed;

  final UnitSystem unit;

  /// The longest session in the week, used to scale the cell fills so they read
  /// relative to *this* week rather than to an absolute distance.
  double get _peak => week.runs.isEmpty
      ? 0
      : week.runs.map((s) => s.distanceMeters).reduce((a, b) => a > b ? a : b);

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      onTap: onTapWeek,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      // A little more frost than the default: this pane carries small numerals
      // over a photograph, and legibility beats seeing the picture through it.
      blurSigma: 28,
      tintOpacity: dimmed ? 0.07 : 0.12,
      child: Opacity(
        opacity: dimmed ? 0.62 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (title != null) ...<Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SectionLabel(title!),
                        if (subtitle != null) ...<Widget>[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onTapWeek != null)
                    const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppColors.textTertiary,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            // One header row instead of a letter inside every cell.
            Row(
              children: <Widget>[
                for (var weekday = 1; weekday <= 7; weekday++)
                  Expanded(
                    child: Text(
                      weekdayName(weekday).substring(0, 1),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            // No `stretch`: the Row sits in an unbounded Column, so stretching the
            // cross axis asks for infinite height. Every cell has the same
            // structure and a fixed-height bar, so they line up without it.
            Row(
              children: <Widget>[
                for (var weekday = 1; weekday <= 7; weekday++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: weekday == 7 ? 0 : AppSpacing.xs,
                      ),
                      child: _Day(
                        date: DateTime(
                          weekStart.year,
                          weekStart.month,
                          weekStart.day + (weekday - 1),
                        ),
                        session: week.sessionOn(weekday),
                        peak: _peak,
                        status: statusFor?.call(weekday),
                        isToday: today != null && today!.weekday == weekday,
                        unit: unit,
                        onTap: onTapDay == null
                            ? null
                            : () => onTapDay!(weekday),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.date,
    required this.session,
    required this.peak,
    required this.status,
    required this.isToday,
    required this.unit,
    this.onTap,
  });

  final DateTime date;
  final PlannedSession? session;
  final double peak;
  final SessionStatus? status;
  final bool isToday;
  final UnitSystem unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final run = session;
    final isRest = run == null;
    final isSupport = run != null && run.kind.isSupport;
    final skipped = status == SessionStatus.skipped;

    // Today is the only emphasis. With no accent colour to spend (ADR-0009),
    // marking anything else flattens the one distinction that matters.
    // On glass, a solid fill would punch a hole in the pane. A run day is a
    // faint lift out of it; a rest day is the glass itself; today alone is
    // opaque, because today is the one thing that should feel solid.
    // How big this session is, against the week's longest. This is what the
    // fill encodes.
    final fraction = isRest || peak <= 0 ? 0.0 : run.distanceMeters / peak;
    final background = isToday
        ? AppColors.primary
        : (isRest
              ? Colors.transparent
              // 0.05 for the shortest run up to 0.20 for the long run. Small
              // numbers: past ~0.22 a cell stops reading as glass and starts
              // reading as a button.
              : AppColors.textPrimary.withValues(
                  alpha: skipped ? 0.04 : 0.05 + 0.15 * fraction,
                ));
    final ink = isToday ? AppColors.onPrimary : AppColors.textPrimary;
    final quiet = isToday ? AppColors.onPrimary : AppColors.textTertiary;
    // The status marks sit one step brighter than the rest-day caption. They
    // are the line the eye runs along to read a week — at tertiary they were
    // there for anyone already looking for them, which is not the same thing.
    final mark = isToday ? AppColors.onPrimary : AppColors.textSecondary;

    return Semantics(
      // The visual is deliberately terse; the label is not.
      label: _semanticLabel(),
      button: !isRest && onTap != null,
      child: Material(
        color: background,
        borderRadius: AppRadius.chipAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // Rest days are tappable too — the week opens either way, and a dead
          // cell in the middle of a live row is a worse affordance than a live
          // one that shows a rest day.
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md,
              horizontal: 2,
            ),
            decoration: BoxDecoration(
              borderRadius: AppRadius.chipAll,
              border: isToday || !isRest
                  ? null
                  : Border.all(
                      color: AppColors.textPrimary.withValues(alpha: 0.08),
                    ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '${date.day}',
                  style: TextStyle(
                    color: isRest && !isToday ? AppColors.textSecondary : ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                if (isSupport)
                  // A word, like rest gets. The dumbbell glyph is drawn on a
                  // diagonal, so at 13px it read as a double-headed arrow — and
                  // a rest day showing a word while a strength day showed a
                  // smudge had it backwards: rest is nothing, strength is
                  // something you do.
                  Text(
                    'Strength',
                    style: TextStyle(
                      color: quiet,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else if (isRest)
                  Text(
                    'Rest',
                    style: TextStyle(
                      color: quiet,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  Text(
                    // With the unit, because "7" under "20" is two numbers and
                    // no information.
                    formatPrescribed(run.distanceMeters, unit),
                    style: TextStyle(
                      color: skipped ? quiet : ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      decoration: skipped ? TextDecoration.lineThrough : null,
                    ),
                  ),

                // A mark *beside* the state rather than replacing it, so a
                // session that has been dealt with still says what it was.
                //
                // Skipped gets a mark of its own, in the same slot: a
                // line-through on an 11px number and a dimmer bar were the only
                // difference between "skipped" and "not yet", which at a glance
                // is no difference at all. Greyscale, not `danger` — a skipped
                // session is a normal event in a training block, not an error,
                // and the one red thing on the screen would read as a telling-off.
                SizedBox(
                  height: 14,
                  // Guarded on the session, not just the status: a status for a
                  // day with no session would otherwise draw a tick on "Rest".
                  // Callers only answer for the day carrying a session today,
                  // so this is a trap rather than a bug — but it is one line.
                  child: switch (isRest ? null : status) {
                    SessionStatus.completed => Icon(
                      Icons.check,
                      size: 13,
                      color: mark,
                    ),
                    SessionStatus.skipped => Icon(
                      Icons.close,
                      size: 13,
                      color: mark,
                    ),
                    _ => null,
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _semanticLabel() {
    final parts = <String>[
      '${date.day}',
      if (session == null)
        'rest day'
      else ...<String>[
        kindLabel(session!.kind),
        Distance.meters(session!.distanceMeters).format(unit),
      ],
      if (isToday) 'today',
      if (status == SessionStatus.completed) 'completed',
      if (status == SessionStatus.skipped) 'skipped',
    ];
    return parts.join(', ');
  }
}
