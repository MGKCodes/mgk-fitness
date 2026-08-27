import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/progress_photo.dart';
import 'photo_sheets.dart';
import 'photos_surface.dart';
import 'series_playback_screen.dart';

/// One pose, every week of it.
///
/// A grid rather than a list: the comparison is the content, and thumbnails side
/// by side are the only layout where twelve weeks fit on one screen. Missed
/// weeks are drawn as empty slots rather than closed up, because a gap is
/// information — it is the week you did not take one.
class PoseSeriesScreen extends StatefulWidget {
  const PoseSeriesScreen({
    super.key,
    required this.series,
    required this.thisWeek,
    required this.library,
    this.onAdd,
    this.source,
  });

  final PoseSeries series;
  final DateTime thisWeek;
  final PhotoLibrary library;
  final VoidCallback? onAdd;

  /// Needed to fill a week other than this one. Null leaves past gaps
  /// read-only.
  final PhotoSource? source;

  @override
  State<PoseSeriesScreen> createState() => _PoseSeriesScreenState();
}

class _PoseSeriesScreenState extends State<PoseSeriesScreen> {
  late PoseSeries _series = widget.series;

  Future<void> _reload() async {
    final all = await widget.library.all();
    if (!mounted) return;
    setState(() {
      _series = PoseSeries(
        pose: _series.pose,
        photos: all.where((p) => p.pose == _series.pose).toList(),
      );
    });
  }

  /// Every week from the first photo to this one, newest first — including the
  /// ones with nothing in them.
  List<DateTime> get _weeks {
    if (_series.photos.isEmpty) return <DateTime>[widget.thisWeek];
    final oldest = _series.photos.last.weekStart;
    final weeks = <DateTime>[];
    for (
      var w = widget.thisWeek;
      !w.isBefore(oldest);
      w = w.subtract(const Duration(days: 7))
    ) {
      weeks.add(w);
    }
    return weeks;
  }

  ProgressPhoto? _photoFor(DateTime week) {
    for (final p in _series.photos) {
      if (p.weekStart == week) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _weeks;
    final canPlay = _series.sequence.length >= 2;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_series.pose.label),
            if (_series.photos.isNotEmpty)
              Text(
                // The span is the interesting number and it used to vanish at
                // exactly the moment you opened the sequence.
                '${_series.photos.length} over ${_series.spanWeeks} weeks',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
          ],
        ),
        actions: <Widget>[
          AppIconButton(
            // Two is the minimum for a comparison. One photo played back is a
            // photo, and offering it would be the app pretending.
            onPressed: canPlay
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SeriesPlaybackScreen(series: _series),
                    ),
                  )
                : null,
            icon: Icons.play_circle_outline,
            tooltip: canPlay
                ? 'Play the sequence'
                : 'Two photos are needed to compare',
          ),
        ],
      ),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.lg),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            // Portrait, matching how a body photo is actually taken. A square
            // cell crops the head or the feet out of every single one.
            childAspectRatio: 3 / 4,
          ),
          itemCount: weeks.length,
          itemBuilder: (context, i) {
            final week = weeks[i];
            final photo = _photoFor(week);
            return _Cell(
              week: week,
              photo: photo,
              isThisWeek: week == widget.thisWeek,
              // Any empty week can be filled, not only the current one.
              // Someone who took a photo in July and forgot to import it had
              // no route to put it in the slot - the gap was permanent.
              onTap: photo == null
                  ? (week == widget.thisWeek
                        ? widget.onAdd
                        : () => _backfill(week))
                  : () => _actions(photo),
              label: _weekLabel(week),
            );
          },
        ),
      ),
    );
  }

  /// Fills a week that has already passed, from the gallery.
  ///
  /// Gallery only, deliberately: a photo taken today cannot be a record of
  /// three weeks ago, so offering the camera here would invite exactly the
  /// wrong thing.
  Future<void> _backfill(DateTime week) async {
    final source = widget.source;
    if (source == null) return;
    final path = await source.pickFromGallery();
    if (path == null) return;
    await widget.library.put(
      pose: _series.pose,
      weekStart: week,
      sourcePath: path,
      takenAt: week,
    );
    await _reload();
  }

  String _weekLabel(DateTime week) {
    const months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${week.day} ${months[week.month - 1]}';
  }

  Future<void> _actions(ProgressPhoto photo) async {
    final action = await showPhotoActionsSheet(context, photo);

    if (action == 'exclude') {
      await widget.library.setExcluded(photo.id, excluded: !photo.isExcluded);
      await _reload();
    } else if (action == 'delete' && mounted) {
      await _confirmDelete(photo);
    }
  }

  Future<void> _confirmDelete(ProgressPhoto photo) async {
    final confirmed = await confirmPhotoDelete(context);
    if (confirmed != true) return;
    await widget.library.delete(photo.id);
    await _reload();
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.week,
    required this.photo,
    required this.isThisWeek,
    required this.onTap,
    required this.label,
  });

  final DateTime week;
  final ProgressPhoto? photo;
  final bool isThisWeek;
  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: photo == null
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      border: Border.all(
                        color: isThisWeek
                            ? AppColors.textSecondary
                            : AppColors.elevated,
                      ),
                    ),
                    child: Center(
                      // A gap is information - it is the week you did not take
                      // one. A faint dash on a dark card read as a rendering
                      // failure instead, so a missed week says so in words.
                      child: isThisWeek
                          ? const Icon(
                              Icons.add,
                              size: 20,
                              color: AppColors.textSecondary,
                            )
                          : Text(
                              'Missed',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                color: AppColors.textTertiary,
                              ),
                            ),
                    ),
                  )
                : PhotoThumb(path: photo!.path),
          ),

          // Date over the image rather than under it, so the cells stay the
          // same height whether or not there is a photo in them.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    AppColors.bg.withValues(alpha: 0),
                    AppColors.bg.withValues(alpha: 0.85),
                  ],
                ),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(AppRadius.chip),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (photo?.isExcluded ?? false) ...<Widget>[
                      const Icon(
                        Icons.visibility_off_outlined,
                        size: 11,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 2),
                    ],
                    Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: photo == null
                            ? AppColors.textTertiary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
