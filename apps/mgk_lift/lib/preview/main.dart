import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../src/features/auth/data/fake_auth.dart';
import '../src/features/auth/domain/account.dart';
import '../src/features/auth/presentation/sign_in_screen.dart';
import '../src/features/coaching/presentation/plan_surface.dart';
import '../src/features/home/presentation/lift_shell.dart';
import '../src/features/photos/data/in_memory_photo_library.dart';
import '../src/features/photos/domain/progress_photo.dart';
import '../src/features/photos/presentation/photos_surface.dart';
import '../src/features/photos/presentation/pose_series_screen.dart';
import '../src/features/settings/domain/unit_preferences.dart';
import '../src/features/settings/presentation/credits_screen.dart';
import '../src/features/settings/presentation/settings_screen.dart';
import '../src/features/sync/domain/sync_status.dart';
import '../src/features/tracking/domain/session.dart';
import '../src/features/tracking/presentation/active_session_screen.dart';
import 'fakes.dart';

/// A web harness for reviewing screens, driven by Playwright.
///
/// Same idea as `mgk_run`'s preview: every screen is addressable by URL
/// (`?screen=track`), because Playwright cannot reliably tap a Flutter canvas
/// to navigate. Screens are built over in-memory fakes, so no database, no
/// network, and no emulator — the thing under review is the layout.
///
/// Run it with:
///
///     flutter run -d web-server --web-port 5310 -t lib/preview/main.dart
void main() => runApp(const PreviewApp());

/// One fixed "now", so a screenshot taken today and one taken next week show
/// the same streak. A harness whose output changes with the wall clock is
/// useless for comparing before and after.
final DateTime previewNow = DateTime(2026, 8, 6, 18, 30);

class PreviewApp extends StatelessWidget {
  const PreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    final screens = <String, WidgetBuilder>{
      'track': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(sampleLog(previewNow)),
      ),
      'track-open': (_) => LiftShell(
        recorder: FakeSessionRecorder(_openSession()),
        history: FakeHistory(sampleLog(previewNow)),
      ),
      'plan': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(sampleLog(previewNow)),
        initialTab: 1,
      ),
      'plan-entitled': (_) => const Scaffold(
        body: PlanSurface(isEntitled: true),
      ),
      'profile': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(sampleLog(previewNow)),
        initialTab: 2,
      ),
      'profile-empty': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: const FakeHistory(<Session>[]),
        initialTab: 2,
      ),
      'session-empty': (_) => ActiveSessionScreen(
        recorder: FakeSessionRecorder(_emptySession()),
        session: _emptySession(),
      ),
      'session': (_) {
        final s = _openSession();
        return ActiveSessionScreen(
          recorder: FakeSessionRecorder(s),
          session: s,
        );
      },
      // A six-movement template, three of them finished. The case the collapse
      // exists for: expanded throughout, this is ~2,000px and the movement you
      // are on is off screen.
      'session-long': (_) {
        final s = _longSession();
        return ActiveSessionScreen(
          recorder: FakeSessionRecorder(s),
          session: s,
        );
      },
      // Mid-rest, with the bar showing. The fixture ticks a set on open, which
      // is the only way to reach this state — rest is never restored from disk.
      'session-resting': (_) {
        final s = _openSession();
        return ActiveSessionScreen(
          recorder: FakeSessionRecorder(s),
          session: s,
          startRestOnOpen: true,
        );
      },
      'photos': (_) => const _PhotosPreview(),
      'photo-series': (_) => const _PhotosPreview(openSeries: true),
      'photos-empty': (_) => PhotosSurface(
        library: InMemoryPhotoLibrary(),
        source: FakePhotoSource(null),
        now: previewNow,
      ),
      'settings': (_) => SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
      ),
      // The two states that matter: signed out with training that exists in
      // one place, and signed in with everything up to date.
      'settings-signed-in': (_) => SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
        isSignedIn: true,
        email: 'matt@example.com',
        pending: const SyncPending(workouts: 0, lastSyncedAt: null),
        onSignOut: () {},
        onSyncNow: () {},
      ),
      'backup-signed-out': (_) => SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
        pending: const SyncPending(workouts: 9, lastSyncedAt: null),
        onSignIn: () {},
      ),
      'backup-synced': (_) => SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
        isSignedIn: true,
        pending: SyncPending(
          workouts: 0,
          lastSyncedAt: previewNow.subtract(const Duration(minutes: 3)),
        ),
        onSyncNow: () {},
      ),
      'sign-in': (_) => SignInScreen(auth: FakeAuth(), pendingWorkouts: 9),
      'sign-in-error': (_) => SignInScreen(
        auth: FakeAuth(failWith: AuthFailure.wrongCredentials),
      ),
      'credits': (_) => const CreditsScreen(),
      'coach-mark': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(sampleLog(previewNow)),
        onOpenCoach: () {},
        hasCoachNote: true,
      ),
    };

    // Web: addressable by URL, because Playwright cannot tap a Flutter canvas.
    // Android: there is no URL, so the index is the entry point and each screen
    // is pushed — which is also what makes `adb shell input tap` predictable,
    // since a plain list has stable row positions.
    final key = Uri.base.queryParameters['screen'];
    final direct = screens[key];

    return MaterialApp(
      title: 'Lift — preview',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: direct != null
          ? Builder(builder: direct)
          : _Index(screens: screens),
    );
  }
}

Session _emptySession() => Session(
  id: 'preview',
  name: 'Evening session',
  startedAt: previewNow.subtract(const Duration(minutes: 2)),
);

/// A session mid-flow: some sets done, one in progress, one movement untouched.
/// The state a lifter is actually looking at, rather than a tidy finished one.
Session _openSession() => Session(
  id: 'preview',
  name: 'Push',
  startedAt: previewNow.subtract(const Duration(minutes: 34)),
  exercises: <SessionExercise>[
    const SessionExercise(
      id: 'e1',
      name: 'Barbell Bench Press',
      orderIndex: 0,
      sets: <SessionSet>[
        SessionSet(
          id: 's1',
          setNumber: 1,
          weightKg: 60,
          reps: 10,
          isCompleted: true,
          setType: SetType.warmup,
        ),
        SessionSet(
          id: 's2',
          setNumber: 2,
          weightKg: 80,
          reps: 8,
          isCompleted: true,
        ),
        SessionSet(
          id: 's3',
          setNumber: 3,
          weightKg: 85,
          reps: 6,
          isCompleted: true,
        ),
        SessionSet(id: 's4', setNumber: 4, weightKg: 85, reps: 6),
      ],
    ),
    const SessionExercise(
      id: 'e2',
      name: 'Dumbbell Shoulder Press',
      orderIndex: 1,
      sets: <SessionSet>[
        SessionSet(
          id: 's5',
          setNumber: 1,
          weightKg: 26,
          reps: 10,
          isCompleted: true,
        ),
        SessionSet(id: 's6', setNumber: 2, weightKg: 26, reps: 10),
      ],
    ),
    const SessionExercise(
      id: 'e3',
      name: 'Cable Tricep Pushdown',
      orderIndex: 2,
    ),
  ],
);

/// A push day most of the way through: three movements done, one in progress,
/// two not started.
Session _longSession() {
  SessionSet done(String id, int n, double kg, int reps) => SessionSet(
    id: id,
    setNumber: n,
    weightKg: kg,
    reps: reps,
    isCompleted: true,
  );

  return Session(
    id: 'preview-long',
    name: 'Push',
    startedAt: previewNow.subtract(const Duration(minutes: 52)),
    exercises: <SessionExercise>[
      SessionExercise(
        id: 'l1',
        name: 'Barbell Bench Press',
        orderIndex: 0,
        sets: <SessionSet>[
          done('l1s1', 1, 80, 8),
          done('l1s2', 2, 85, 6),
          done('l1s3', 3, 85, 6),
        ],
      ),
      SessionExercise(
        id: 'l2',
        name: 'Incline Dumbbell Press',
        orderIndex: 1,
        sets: <SessionSet>[done('l2s1', 1, 30, 10), done('l2s2', 2, 30, 9)],
      ),
      SessionExercise(
        id: 'l3',
        name: 'Dumbbell Shoulder Press',
        orderIndex: 2,
        sets: <SessionSet>[done('l3s1', 1, 26, 10), done('l3s2', 2, 26, 8)],
      ),
      SessionExercise(
        id: 'l4',
        name: 'Cable Tricep Pushdown',
        orderIndex: 3,
        sets: <SessionSet>[
          done('l4s1', 1, 35, 12),
          const SessionSet(id: 'l4s2', setNumber: 2, weightKg: 35, reps: 12),
        ],
      ),
      const SessionExercise(
        id: 'l5',
        name: 'Cable Overhead Tricep Extension',
        orderIndex: 4,
      ),
      // Deliberately not in the catalogue, so the review set covers the
      // typed-it-yourself case. The movement above is the opposite case: it is
      // in the catalogue under the other word order, and resolves anyway.
      const SessionExercise(
        id: 'l6',
        name: 'Cable Lateral Raise',
        orderIndex: 5,
      ),
    ],
  );
}

/// Photos over **real files**, because the surface renders images from disk.
///
/// Pointing the fixture at paths that do not exist made every thumbnail the
/// missing-file placeholder, which is a state worth having but not the one to
/// review the screen in. This writes a bundled asset out to the temp directory
/// first, so the preview exercises the same `Image.file` path production does.
class _PhotosPreview extends StatefulWidget {
  const _PhotosPreview({this.openSeries = false});

  /// Opens straight into one pose's grid, which is the screen with the missed
  /// weeks in it and the harder layout to get right.
  final bool openSeries;

  @override
  State<_PhotosPreview> createState() => _PhotosPreviewState();
}

class _PhotosPreviewState extends State<_PhotosPreview> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final bytes = await rootBundle.load(
      'assets/images/backgrounds/hero_profile.webp',
    );
    final file = File('${Directory.systemTemp.path}/preview-photo.webp');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    if (!mounted) return;
    setState(() => _path = file.path);
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    if (path == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final library = InMemoryPhotoLibrary(_samplePhotos(path));
    if (!widget.openSeries) {
      return PhotosSurface(
        library: library,
        source: FakePhotoSource(null),
        now: previewNow,
      );
    }
    final week = ProgressPhoto.weekOf(previewNow);
    return FutureBuilder<List<ProgressPhoto>>(
      future: library.all(),
      builder: (context, snapshot) {
        final all = snapshot.data;
        if (all == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return PoseSeriesScreen(
          series: PoseSeries(
            pose: Pose.front,
            photos: all.where((p) => p.pose == Pose.front).toList(),
          ),
          thisWeek: week,
          library: library,
        );
      },
    );
  }
}

/// Twelve weeks of front and back shots, with two weeks missed in the middle.
List<ProgressPhoto> _samplePhotos(String path) {
  final thisWeek = ProgressPhoto.weekOf(previewNow);
  final photos = <ProgressPhoto>[];
  for (var w = 0; w < 12; w++) {
    if (w == 4 || w == 5) continue; // a fortnight nobody took one
    final week = thisWeek.subtract(Duration(days: 7 * w));
    for (final pose in Pose.defaults) {
      photos.add(
        ProgressPhoto(
          id: '\${pose.stored}-\$w',
          weekStart: week,
          pose: pose,
          path: path,
          takenAt: week,
        ),
      );
    }
  }
  return photos;
}

/// Every screen, tappable.
///
/// **A two-column grid, not a list.** The capture script taps by computed
/// position and cannot reach a row below the fold, so a single column put a
/// ceiling on how many screens the harness could reach — and every time that
/// ceiling was hit, the run failed silently by screenshotting this index under
/// the missing screen's name. Two columns doubles the ceiling and halves how
/// often the row height has to be argued about.
class _Index extends StatelessWidget {
  const _Index({required this.screens});

  final Map<String, WidgetBuilder> screens;

  /// Height of one cell, in logical pixels. **Mirrored in
  /// `tool/capture_screens.ps1`; change both or every tap lands on the wrong
  /// cell.**
  static const double cellHeight = 72;

  /// **Mirrored in the capture script too.**
  static const int columns = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keys = screens.keys.toList();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: cellHeight,
          ),
          itemCount: keys.length,
          itemBuilder: (context, i) => InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: screens[keys[i]]!),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
              ),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 26,
                    child: Text(
                      '${i + 1}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      keys[i],
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

