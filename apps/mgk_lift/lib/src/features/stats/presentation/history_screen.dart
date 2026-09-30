import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../sync/presentation/backup_scheduler.dart';
import '../../tracking/domain/session.dart';

/// **Every session**, not the last five (F16) — grouped by week, newest first,
/// each one opening the session it names.
///
/// Profile showed five and nothing led past them, so a session from last month
/// could be counted in every total and never be looked at again, let alone
/// fixed. This is the way in to all of them.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({
    super.key,
    required this.log,
    required this.onOpen,
    this.massUnit = MassUnit.kilograms,
    this.now,
    this.backup,
  });

  /// Finished sessions, newest first.
  final List<Session> log;

  final ValueChanged<Session> onOpen;
  final MassUnit massUnit;

  /// Injected so "this week" is testable.
  final DateTime? now;

  /// For the mark on a session not backed up yet. Null is a build with no
  /// server.
  final ValueListenable<BackupStatus>? backup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = now ?? DateTime.now();
    final weeks = <DateTime, List<Session>>{};
    for (final s in log) {
      weeks.putIfAbsent(_weekOf(s.startedAt), () => <Session>[]).add(s);
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      // The same glass header the library has, over the same quiet photograph.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: const GlassSurface.bar(child: SizedBox.expand()),
        leading: AppIconButton(
          icon: Icons.arrow_back,
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Every session'),
      ),
      body: PhotoBackdrop(
        image: 'assets/images/backgrounds/hero_home.webp',
        scrim: ScrimStrength.quiet,
        child: log.isEmpty
            ? Center(
                child: Text(
                  'Nothing logged yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            // Read inside the body: the scaffold adds the bar's height to the
            // top inset for its body only, and the screen's own context, above
            // the scaffold, never sees it — the first week sat under the bar.
            : Builder(
                builder: (context) => ListView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    MediaQuery.paddingOf(context).top + AppSpacing.sm,
                    AppSpacing.lg,
                    MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
                  ),
                  children: <Widget>[
                    for (final (w, entry) in weeks.entries.indexed) ...<Widget>[
                      if (w > 0) const SizedBox(height: AppSpacing.lg),
                      SectionLabel(_weekLabel(entry.key, today)),
                      const SizedBox(height: AppSpacing.sm),
                      for (final (i, session) in entry.value.indexed)
                        Entrance(
                          index: w == 0 ? i : 0,
                          child: _SessionRow(
                            session: session,
                            massUnit: massUnit,
                            onTap: () => onOpen(session),
                            backup: backup,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  /// Monday of [d]'s week, at midnight.
  static DateTime _weekOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  static String _weekLabel(DateTime monday, DateTime today) {
    final thisWeek = _weekOf(today);
    if (monday == thisWeek) return 'This week';
    if (monday == DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 7)) {
      return 'Last week';
    }
    final year = monday.year == today.year ? '' : ' ${monday.year}';
    return 'Week of ${monday.day} ${_months[monday.month - 1]}$year';
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.massUnit,
    required this.onTap,
    required this.backup,
  });

  final Session session;
  final MassUnit massUnit;
  final VoidCallback onTap;
  final ValueListenable<BackupStatus>? backup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sets = session.completedSets;
    final volume = session.volumeKg;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    session.name,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    <String>[
                      '${_days[session.startedAt.weekday - 1]} '
                          '${session.startedAt.day} '
                          '${_months[session.startedAt.month - 1]}',
                      '$sets ${sets == 1 ? 'set' : 'sets'}',
                      if (volume > 0) Mass.kilograms(volume).label(massUnit),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // Only for somebody signed in, for whom it is news.
            if (backup case final backup?)
              ValueListenableBuilder<BackupStatus>(
                valueListenable: backup,
                builder: (context, status, _) =>
                    status.state == BackupState.signedOut ||
                        status.isBackedUp(session.id)
                    ? const SizedBox.shrink()
                    : const Padding(
                        padding: EdgeInsets.only(right: AppSpacing.xs),
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
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

const List<String> _days = <String>[
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', //
];

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
