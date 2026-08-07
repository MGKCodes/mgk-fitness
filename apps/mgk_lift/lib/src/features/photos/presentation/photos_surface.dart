import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/progress_photo.dart';
import 'pose_series_screen.dart';

/// **Progress photos** — one stream per pose, one photo per week.
///
/// The scale is the point. A body does not change between Tuesday and Wednesday,
/// so a daily log produces hundreds of near-identical frames and a comparison
/// over months becomes scrubbing. Weekly is the shortest interval over which a
/// change is legible, and it makes the whole feature a habit with a clear
/// definition of done: two photos, once a week.
///
/// Which is why the first thing on the screen is whether this week is done.
class PhotosSurface extends StatefulWidget {
  const PhotosSurface({
    super.key,
    required this.library,
    this.source,
    this.poses = Pose.defaults,
    this.now,
  });

  final PhotoLibrary library;

  /// Null disables adding — right for a build with no camera plugin, and for a
  /// preview. The screen still shows what is there.
  final PhotoSource? source;

  /// Which poses this account tracks, as it starts. The lifter can add the
  /// others from the screen.
  final List<Pose> poses;

  /// Injected so a test can pin the week.
  final DateTime? now;

  @override
  State<PhotosSurface> createState() => _PhotosSurfaceState();
}

class _PhotosSurfaceState extends State<PhotosSurface> {
  List<ProgressPhoto> _photos = const <ProgressPhoto>[];
  bool _loading = true;

  /// Poses turned on beyond the starting two.
  ///
  /// Held here for the session rather than persisted, which is the honest
  /// half-measure: `core.user_settings.progress_pose_set` is the column this
  /// belongs in and there is no settings write path to it yet. Without this
  /// the side poses existed in the enum, in the database and in playback, and
  /// were reachable from nowhere at all.
  final Set<Pose> _added = <Pose>{};

  List<Pose> get _tracked => <Pose>[
    ...widget.poses,
    ...Pose.values.where(
      (p) => !widget.poses.contains(p) && _added.contains(p),
    ),
  ];

  List<Pose> get _untracked =>
      Pose.values.where((p) => !_tracked.contains(p)).toList();

  DateTime get _thisWeek => ProgressPhoto.weekOf(widget.now ?? DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final photos = await widget.library.all();
    if (!mounted) return;
    setState(() {
      _photos = photos;
      _loading = false;
    });
  }

  PoseSeries _seriesFor(Pose pose) => PoseSeries(
    pose: pose,
    photos: _photos.where((p) => p.pose == pose).toList(),
  );

  Future<void> _add(Pose pose) async {
    final source = widget.source;
    if (source == null) return;

    final path = await _chooseSource(source);
    if (path == null) return;

    await widget.library.put(
      pose: pose,
      weekStart: _thisWeek,
      sourcePath: path,
    );
    await _load();
  }

  /// Camera or gallery. Asked every time rather than remembered: the gallery is
  /// how you backfill a photo you already took, and the camera is how you do
  /// this week — both are normal and neither is the default.
  Future<String?> _chooseSource(PhotoSource source) async {
    final fromCamera = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from photos'),
              onTap: () => Navigator.of(sheetContext).pop(false),
            ),
          ],
        ),
      ),
    );
    if (fromCamera == null) return null;
    return fromCamera ? source.capture() : source.pickFromGallery();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final week = _thisWeek;
    final series = _tracked.map(_seriesFor).toList();
    final done = series.where((s) => s.hasPhotoFor(week)).length;
    final anyPhotos = series.any((s) => s.photos.isNotEmpty);

    return Scaffold(
      appBar: AppBar(title: const Text('Progress photos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              // Centred when the content is shorter than the screen, scrolling
              // when it is longer. The empty state otherwise sat in the top
              // third above a screen and a half of nothing - the same fault
              // the Plan surface had.
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: _padding,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - _padding.vertical,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: anyPhotos
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.center,
                      children: <Widget>[
                        if (anyPhotos) ...<Widget>[
                          _ThisWeek(
                            done: done,
                            total: series.length,
                            // The nudge does something. "1 of 2 taken" told you
                            // the state and left you to find the missing pose
                            // yourself.
                            onFinish: widget.source == null || done == series.length
                                ? null
                                : () => _add(
                                    series
                                        .firstWhere(
                                          (s) => !s.hasPhotoFor(week),
                                        )
                                        .pose,
                                  ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          for (final s in series)
                            _PoseCard(
                              series: s,
                              thisWeek: week,
                              onOpen: () => _open(s),
                              onAdd: widget.source == null
                                  ? null
                                  : () => _add(s.pose),
                            ),
                          if (_untracked.isNotEmpty) ...<Widget>[
                            const SizedBox(height: AppSpacing.sm),
                            const SectionLabel('Also track'),
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: AppSpacing.sm,
                              children: <Widget>[
                                for (final pose in _untracked)
                                  ActionChip(
                                    label: Text(pose.label),
                                    avatar: const Icon(Icons.add, size: 16),
                                    onPressed: () =>
                                        setState(() => _added.add(pose)),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            // Says where they are, because "are my photos on a
                            // server" is the first question anyone sensible
                            // asks about photographs of their own body.
                            //
                            // **This sentence is a promise, and it is
                            // load-bearing.** `core.progress_photos` and a
                            // private storage bucket both exist server-side
                            // already, so the day photos start syncing this
                            // line becomes a lie. It must change in the same
                            // commit that changes the behaviour, not after
                            // somebody notices.
                            'Photos stay on this device. Nothing is uploaded.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ] else
                          _Empty(
                            poses: _tracked,
                            onAdd: widget.source == null ? null : _add,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  static const EdgeInsets _padding = EdgeInsets.fromLTRB(
    AppSpacing.lg,
    AppSpacing.lg,
    AppSpacing.lg,
    AppSpacing.xxl,
  );

  Future<void> _open(PoseSeries series) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PoseSeriesScreen(
          series: series,
          thisWeek: _thisWeek,
          library: widget.library,
          source: widget.source,
          onAdd: widget.source == null ? null : () => _add(series.pose),
        ),
      ),
    );
    await _load();
  }
}

/// Whether this week is done. The whole nudge, in one line.
class _ThisWeek extends StatelessWidget {
  const _ThisWeek({
    required this.done,
    required this.total,
    required this.onFinish,
  });

  final int done;
  final int total;

  /// Starts the first pose still missing this week. Null once the week is done,
  /// or when there is no camera.
  final VoidCallback? onFinish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete = done == total;
    return AppCard(
      child: Row(
        children: <Widget>[
          Icon(
            complete ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20,
            color: complete ? AppColors.success : AppColors.textTertiary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SectionLabel('This week'),
                const SizedBox(height: 2),
                Text(
                  complete ? 'Done' : '$done of $total taken',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
          ),
          if (onFinish != null)
            TextButton(onPressed: onFinish, child: const Text('Finish it')),
        ],
      ),
    );
  }
}

/// One pose: its most recent photo, how far the series runs, and a way in.
class _PoseCard extends StatelessWidget {
  const _PoseCard({
    required this.series,
    required this.thisWeek,
    required this.onOpen,
    required this.onAdd,
  });

  final PoseSeries series;
  final DateTime thisWeek;
  final VoidCallback onOpen;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = series.latest;
    final needsThisWeek = !series.hasPhotoFor(thisWeek);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        padding: EdgeInsets.zero,
        onTap: series.photos.isEmpty ? onAdd : onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              // Portrait, matching the grid and matching how a body photo is
              // actually taken. At 16:9 with BoxFit.cover the card showed a
              // horizontal band of a standing person - head and legs cropped
              // out of every single one.
              aspectRatio: 4 / 3,
              child: latest == null
                  ? const ColoredBox(
                      color: AppColors.elevated,
                      child: Center(
                        child: Icon(
                          Icons.add_a_photo_outlined,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    )
                  : PhotoThumb(path: latest.path),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(series.pose.label, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle(series),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (needsThisWeek && onAdd != null)
                    TextButton(
                      onPressed: onAdd,
                      child: Text(
                        series.photos.isEmpty ? 'Start' : 'This week',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _subtitle(PoseSeries series) {
    if (series.photos.isEmpty) return 'Not started';
    final n = series.photos.length;
    final weeks = series.spanWeeks;
    final photos = '$n photo${n == 1 ? '' : 's'}';
    // Both numbers, because they differ the moment a week is missed and the gap
    // is the interesting part.
    return weeks <= 1 ? photos : '$photos over $weeks weeks';
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.poses, required this.onAdd});

  final List<Pose> poses;
  final void Function(Pose pose)? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        children: <Widget>[
          Text(
            'Same spot, same light, once a week',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'The scale moves for reasons that have nothing to do with training. '
            'A photo a week does not.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          if (onAdd != null)
            PrimaryButton(
              // Names the pose, because tapping this makes a choice on the
              // lifter's behalf and the button used to keep it to itself.
              label: 'Start with ${poses.first.label.toLowerCase()}',
              onPressed: () => onAdd!(poses.first),
            )
          else
            Text(
              'The camera is not available in this build.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }
}

/// A stored photo, or a placeholder if the file has gone.
///
/// **A missing file is a real state, not a bug to crash on.** Paths point into
/// the app's documents directory, which does not survive a reinstall and can be
/// cleared by the OS under storage pressure. The row outliving its JPEG has to
/// read as "this photo is gone" rather than taking the screen down.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({super.key, required this.path, this.fit = BoxFit.cover});

  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    if (!file.existsSync()) return const _MissingFile();
    return Image.file(
      file,
      fit: fit,
      errorBuilder: (_, _, _) => const _MissingFile(),
    );
  }
}

class _MissingFile extends StatelessWidget {
  const _MissingFile();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.elevated,
    child: Center(
      child: Icon(Icons.image_not_supported_outlined,
          color: AppColors.textTertiary),
    ),
  );
}
