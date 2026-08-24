import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/progress_photo.dart';
import 'photos_surface.dart';

/// The sequence, played back.
///
/// **In-app playback, not a video export.** Liftio encoded an MP4 through a
/// native module so the result could be shared; that is a real feature and a
/// whole platform channel per OS. This is the part that does the actual work —
/// showing a lifter their own change — without any of that. Sharing can come
/// later and does not block seeing it.
///
/// Excluded frames are already gone by the time this screen has the series; see
/// [PoseSeries.sequence].
class SeriesPlaybackScreen extends StatefulWidget {
  const SeriesPlaybackScreen({super.key, required this.series});

  final PoseSeries series;

  @override
  State<SeriesPlaybackScreen> createState() => _SeriesPlaybackScreenState();
}

class _SeriesPlaybackScreenState extends State<SeriesPlaybackScreen> {
  late final List<ProgressPhoto> _frames = widget.series.sequence;

  int _index = 0;
  Timer? _timer;
  bool _playing = false;

  /// Fast enough to read as change rather than a slideshow, slow enough to see
  /// each week. Adjustable, because a two-photo series and a fifty-photo one
  /// want very different speeds.
  Duration _frameFor(double speed) =>
      Duration(milliseconds: (600 / speed).round());

  double _speed = 1;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (_playing) {
      _timer?.cancel();
      setState(() => _playing = false);
      return;
    }
    // Restart from the beginning if it is sitting on the last frame — pressing
    // play on a finished sequence means "again", not "nothing".
    if (_index >= _frames.length - 1) _index = 0;
    setState(() => _playing = true);
    _timer = Timer.periodic(_frameFor(_speed), (t) {
      if (_index >= _frames.length - 1) {
        t.cancel();
        setState(() => _playing = false);
        return;
      }
      setState(() => _index++);
    });
  }

  void _scrub(double value) {
    _timer?.cancel();
    setState(() {
      _playing = false;
      _index = value.round().clamp(0, _frames.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frame = _frames[_index];
    final first = _frames.first;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(widget.series.pose.label)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  PhotoThumb(path: frame.path, fit: BoxFit.contain),

                  // Where in the run this frame is. Over the image because the
                  // image should have the whole screen.
                  Positioned(
                    left: AppSpacing.lg,
                    top: AppSpacing.lg,
                    child: _Chip(text: _label(frame)),
                  ),
                  if (_index > 0)
                    Positioned(
                      right: AppSpacing.lg,
                      top: AppSpacing.lg,
                      child: _Chip(text: '+${_weeksFrom(first, frame)} weeks'),
                    ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: <Widget>[
                  // Scrubbing beats autoplay for actually looking at something.
                  // Playback is the demo; the slider is how anyone compares two
                  // specific weeks.
                  Slider(
                    value: _index.toDouble(),
                    max: (_frames.length - 1).toDouble(),
                    divisions: _frames.length - 1,
                    onChanged: _scrub,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        '${_index + 1} of ${_frames.length}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                      IconButton.filled(
                        onPressed: _toggle,
                        icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                        tooltip: _playing ? 'Pause' : 'Play',
                      ),
                      _SpeedButton(
                        speed: _speed,
                        onChanged: (s) {
                          setState(() => _speed = s);
                          if (_playing) {
                            _timer?.cancel();
                            _playing = false;
                            _toggle();
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static int _weeksFrom(ProgressPhoto a, ProgressPhoto b) =>
      (b.weekStart.difference(a.weekStart).inDays / 7).round();

  static String _label(ProgressPhoto p) {
    const months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${p.weekStart.day} ${months[p.weekStart.month - 1]} '
        '${p.weekStart.year}';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.bg.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(AppRadius.chip),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    ),
  );
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.speed, required this.onChanged});

  final double speed;
  final ValueChanged<double> onChanged;

  static const List<double> _steps = <double>[0.5, 1, 2];

  /// `0.5x`, not `0.5.0x`. A raw double renders its trailing zero.
  static String _label(double v) =>
      v == v.roundToDouble() ? '${v.round()}x' : '${v}x';

  @override
  Widget build(BuildContext context) {
    final next = _steps[(_steps.indexOf(speed) + 1) % _steps.length];
    // Labelled with the current speed, which is what a lifter needs to read
    // mid-playback; the tooltip carries what tapping does. The tooltip wraps
    // the button rather than the label, because AppTextButton owns its own
    // Text — which is the trade for the press feel, and a fair one here.
    return Tooltip(
      message: 'Switch to ${_label(next)}',
      child: AppTextButton(
        label: _label(speed),
        onPressed: () => onChanged(next),
        style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
      ),
    );
  }
}
