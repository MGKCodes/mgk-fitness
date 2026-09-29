import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../purchases/presentation/restore_button.dart';

import '../domain/progress_photo.dart';
import 'photo_sheets.dart';
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
///
/// ## Paid, and what that means when it lapses
///
/// The whole feature is behind the entitlement, alongside the coach and the
/// plan: taking a photo needs [isEntitled], not just a camera. Storing
/// photographs of somebody's body costs real money in a way that text rows do
/// not, which is the one place in this app where a storage gate is an economic
/// fact rather than a paywall looking for a home.
///
/// **A lapse takes the camera, not the photos.** Somebody who stops paying
/// keeps everything they shot: they can look at it, play it back, and delete
/// it. Only adding stops. That is the same rule `main.dart` already applies to
/// coach memory — *"somebody who has stopped paying must still be able to read
/// what was stored about them and delete it"* — and here it matters more,
/// because a progress photo is the one thing in this app that cannot be
/// recreated from anything else.
///
/// So the two unentitled states are different screens. Nothing shot yet is the
/// offer; photos already there is the library, read-only, with a line saying
/// why the camera has gone.
class PhotosSurface extends StatefulWidget {
  const PhotosSurface({
    super.key,
    required this.library,
    this.source,
    this.isEntitled = false,
    this.onSubscribe,
    this.onRestore,
    this.poses = Pose.defaults,
    this.now,
  });

  final PhotoLibrary library;

  /// Null disables adding — right for a build with no camera plugin, and for a
  /// preview. The screen still shows what is there.
  final PhotoSource? source;

  /// Whether this account has the paid tier. **Defaults to false**, matching
  /// [PlanSurface]: a default that silently hands over the paid half is the one
  /// mistake worth making impossible.
  final bool isEntitled;

  /// Opens the store. Null when there is none, which the offer says out loud
  /// rather than showing a button that does nothing.
  final VoidCallback? onSubscribe;

  /// Restore purchases, required of any app selling a subscription
  /// (Guideline 3.1.1) and the only route back for somebody reinstalling.
  /// Null hides the affordance rather than disabling it.
  final Future<void> Function()? onRestore;

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

  /// Whether a photo can be taken at all.
  ///
  /// Two conditions, and the entitlement is the one that carries meaning: a
  /// missing [PhotoSource] is a build without a camera plugin, which is a
  /// developer's problem, while a missing entitlement is a person's state and
  /// the screen has to explain it.
  bool get _canAdd => widget.isEntitled && widget.source != null;

  Future<void> _add(Pose pose) async {
    final source = widget.source;
    if (source == null || !widget.isEntitled) return;

    final path = await _chooseSource(source);
    if (path == null) return;

    await widget.library.put(
      pose: pose,
      weekStart: _thisWeek,
      sourcePath: path,
    );
    await _load();
  }

  /// Camera or gallery, then the path it produced.
  ///
  /// The sheet itself lives in [showPhotoSourceSheet]; what stays here is the
  /// part that is this screen's business, which is what to do with the answer.
  Future<String?> _chooseSource(PhotoSource source) async {
    final fromCamera = await showPhotoSourceSheet(context);
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
                            onFinish: !_canAdd || done == series.length
                                ? null
                                : () => _add(
                                    series
                                        .firstWhere((s) => !s.hasPhotoFor(week))
                                        .pose,
                                  ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          for (final s in series)
                            _PoseCard(
                              series: s,
                              thisWeek: week,
                              onOpen: () => _open(s),
                              onAdd: !_canAdd ? null : () => _add(s.pose),
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
                          // Why the camera went, for somebody who had it
                          // yesterday. Without this the screen simply loses a
                          // button and reads as broken rather than as lapsed.
                          if (!widget.isEntitled) ...<Widget>[
                            const SizedBox(height: AppSpacing.lg),
                            _Lapsed(
                              onSubscribe: widget.onSubscribe,
                              onRestore: widget.onRestore,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            // Says where they are, because "are my photos on a
                            // server" is the first question anyone sensible
                            // asks about photographs of their own body.
                            //
                            // **This sentence is a promise and it is
                            // load-bearing.** It used to read "Photos stay on
                            // this device. Nothing is uploaded", which was true
                            // until the commit that added the bucket — and that
                            // commit changed this line, the privacy policy and
                            // the behaviour together, which is the whole reason
                            // the note was here.
                            //
                            // The second sentence is the one that still costs
                            // something to keep. `ai-disclosure.md` promises
                            // the same thing from the other side.
                            'Stored on this phone and in your $kPlatformName '
                            'account. Never sent to the coach or any AI '
                            'provider.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ] else if (!widget.isEntitled)
                          // Nothing shot and nothing bought: the offer, not an
                          // empty state with a disabled button.
                          _Offer(
                            onSubscribe: widget.onSubscribe,
                            onRestore: widget.onRestore,
                          )
                        else
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
          onAdd: !_canAdd ? null : () => _add(series.pose),
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
            AppTextButton(label: 'Finish it', onPressed: onFinish),
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
                  ? ColoredBox(
                      color: AppColors.elevated,
                      child: Center(
                        child: Icon(
                          // An invitation only when it can be accepted. With
                          // no way to add — no camera, or no entitlement — the
                          // add-a-photo icon was a card that looked tappable,
                          // did nothing, and gave no reason. A plain empty
                          // frame says "nothing here", which is true.
                          onAdd == null
                              ? Icons.photo_outlined
                              : Icons.add_a_photo_outlined,
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
                        Text(
                          series.pose.label,
                          style: theme.textTheme.titleSmall,
                        ),
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
                    AppTextButton(
                      label: series.photos.isEmpty ? 'Start' : 'This week',
                      onPressed: onAdd,
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

/// Nothing shot, nothing bought: what the feature is and what it costs.
///
/// An offer rather than an empty state with a dead button. Somebody who has
/// never had this cannot miss it, so the screen has to say what it would be —
/// and the pitch is the same one the feature actually delivers, which is the
/// only kind worth making.
class _Offer extends StatelessWidget {
  const _Offer({required this.onSubscribe, required this.onRestore});

  final VoidCallback? onSubscribe;
  final Future<void> Function()? onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: <Widget>[
          Text(
            'Same spot, same light, once a week',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'The scale moves for reasons that have nothing to do with '
            'training. A photo a week does not.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          const _OfferPoint(
            icon: Icons.grid_on_outlined,
            title: 'One stream per pose',
            body:
                'Front and back to start, sides when you want them. One '
                'photo a week each, so a year is fifty-two frames rather '
                'than four hundred.',
          ),
          const _OfferPoint(
            icon: Icons.play_circle_outline,
            title: 'Play it back',
            body:
                'Months of the same angle, in sequence. A bad week can be '
                'skipped without deleting it.',
          ),
          const _OfferPoint(
            icon: Icons.lock_outline,
            title: 'Yours alone',
            body:
                'Never sent to the coach or any AI provider, and deletable '
                'one at a time or all at once.',
            isLast: true,
          ),
          const SizedBox(height: AppSpacing.xl),
          if (onSubscribe != null) ...<Widget>[
            PrimaryButton(label: 'Unlock photos', onPressed: onSubscribe),
            RestorePurchasesButton(onRestore: onRestore),
          ] else
            Text(
              // Honest about the state rather than showing a button that does
              // nothing. Payments do not exist yet (Phase 3), and a dead
              // "Subscribe" is worse than a sentence.
              'Part of the paid tier, alongside the coach and your plan. '
              'Subscriptions are not open yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

class _OfferPoint extends StatelessWidget {
  const _OfferPoint({
    required this.icon,
    required this.title,
    required this.body,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Photos already here, subscription gone.
///
/// Says what still works before it says what does not. Everything the lifter
/// already shot is theirs, and the screen leading with the loss would misstate
/// what has actually happened.
class _Lapsed extends StatelessWidget {
  const _Lapsed({required this.onSubscribe, required this.onRestore});

  final VoidCallback? onSubscribe;
  final Future<void> Function()? onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Your photos are still here',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Look at them, play them back, delete them — all of that keeps '
            'working. Taking new ones is part of the paid tier.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          if (onSubscribe != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            AppOutlinedButton(
              label: 'Resubscribe',
              onPressed: onSubscribe,
              expand: true,
            ),
            RestorePurchasesButton(onRestore: onRestore),
          ],
        ],
      ),
    );
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
///
/// **On the web there is no file system, so every photo is that state.** The
/// app does not ship to a browser; the preview harness compiles there so
/// screens can be reviewed without a device, and `File.existsSync` throws
/// `UnsupportedError` rather than answering false. That threw before the first
/// frame, so the photo screens rendered nothing but a spinner and could not be
/// reviewed at all. Answering "gone" is both what keeps them drawable and what
/// is actually true of a browser.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({super.key, required this.path, this.fit = BoxFit.cover});

  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const _MissingFile();
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
      child: Icon(
        Icons.image_not_supported_outlined,
        color: AppColors.textTertiary,
      ),
    ),
  );
}
