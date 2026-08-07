import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/photos/data/in_memory_photo_library.dart';
import 'package:mgk_lift/src/features/photos/domain/progress_photo.dart';
import 'package:mgk_lift/src/features/photos/presentation/photos_surface.dart';

final DateTime now = DateTime(2026, 8, 7);
final DateTime thisWeek = ProgressPhoto.weekOf(now);

ProgressPhoto photo(Pose pose, int weeksAgo) => ProgressPhoto(
  id: '${pose.stored}-$weeksAgo',
  weekStart: thisWeek.subtract(Duration(days: 7 * weeksAgo)),
  pose: pose,
  path: '/nonexistent/$weeksAgo.jpg',
  takenAt: now,
);

Widget wrap(Widget child) => MaterialApp(home: child);

/// Pumps on a viewport tall enough to hold the whole surface.
///
/// The default 800x600 is shorter than a phone, so controls near the bottom are
/// off-screen and `tap()` misses them silently - it warns rather than failing,
/// and the assertion afterwards is what breaks.
Future<void> pumpTall(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrap(child));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty library explains the habit rather than the feature', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        PhotosSurface(
          library: InMemoryPhotoLibrary(),
          source: FakePhotoSource('/tmp/x.jpg'),
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Same spot, same light, once a week'), findsOneWidget);
    // Names the pose, because tapping it makes that choice for the lifter.
    expect(find.text('Start with front'), findsOneWidget);
  });

  testWidgets('the week strip counts the poses done', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        PhotosSurface(
          library: InMemoryPhotoLibrary(<ProgressPhoto>[photo(Pose.front, 0)]),
          source: FakePhotoSource('/tmp/x.jpg'),
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 of 2 taken'), findsOneWidget);
  });

  testWidgets('a complete week says so instead of counting', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        PhotosSurface(
          library: InMemoryPhotoLibrary(<ProgressPhoto>[
            photo(Pose.front, 0),
            photo(Pose.back, 0),
          ]),
          source: FakePhotoSource('/tmp/x.jpg'),
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('a series reports weeks spanned, not just a photo count', (
    WidgetTester tester,
  ) async {
    // Two photos twelve weeks apart is twelve weeks of change. Reporting "2
    // photos" alone would describe the gap as no time at all.
    await tester.pumpWidget(
      wrap(
        PhotosSurface(
          library: InMemoryPhotoLibrary(<ProgressPhoto>[
            photo(Pose.front, 0),
            photo(Pose.front, 11),
          ]),
          source: FakePhotoSource('/tmp/x.jpg'),
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 photos over 12 weeks'), findsOneWidget);
  });

  testWidgets('a missing file renders as missing rather than crashing', (
    WidgetTester tester,
  ) async {
    // Paths point into the documents directory, which does not survive a
    // reinstall and can be cleared under storage pressure. The row outliving
    // its JPEG must not take the screen down.
    await tester.pumpWidget(
      wrap(
        PhotosSurface(
          library: InMemoryPhotoLibrary(<ProgressPhoto>[photo(Pose.front, 0)]),
          source: FakePhotoSource('/tmp/x.jpg'),
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.image_not_supported_outlined), findsWidgets);
  });

  testWidgets('with no camera the photos are readable but not addable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        PhotosSurface(
          library: InMemoryPhotoLibrary(<ProgressPhoto>[photo(Pose.front, 0)]),
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 of 2 taken'), findsOneWidget);
    expect(find.text('This week'), findsNothing);
  });

  testWidgets('the side poses can be turned on', (WidgetTester tester) async {
    // Pose declares four; the surface starts with two. Before this they were
    // storable, readable and playable, and reachable from nowhere at all.
    await pumpTall(
      tester,
      PhotosSurface(
        library: InMemoryPhotoLibrary(<ProgressPhoto>[photo(Pose.front, 0)]),
        source: FakePhotoSource('/tmp/x.jpg'),
        now: now,
      ),
    );

    expect(find.text('ALSO TRACK'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Right side'), findsOneWidget);

    await tester.tap(find.widgetWithText(ActionChip, 'Right side'));
    await tester.pumpAndSettle();

    expect(find.text('Right side'), findsOneWidget);
    expect(find.text('1 of 3 taken'), findsOneWidget);
  });

  testWidgets('an unfinished week offers to finish itself', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        PhotosSurface(
          library: InMemoryPhotoLibrary(<ProgressPhoto>[photo(Pose.front, 0)]),
          source: FakePhotoSource('/tmp/x.jpg'),
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Finish it'), findsOneWidget);
  });

  testWidgets('a finished week has nothing left to offer', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        PhotosSurface(
          library: InMemoryPhotoLibrary(<ProgressPhoto>[
            photo(Pose.front, 0),
            photo(Pose.back, 0),
          ]),
          source: FakePhotoSource('/tmp/x.jpg'),
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Finish it'), findsNothing);
  });

  testWidgets('says where the photos live', (WidgetTester tester) async {
    // "Is this on a server" is the first question anyone sensible asks about
    // photographs of their own body.
    await tester.pumpWidget(
      wrap(
        PhotosSurface(
          library: InMemoryPhotoLibrary(<ProgressPhoto>[photo(Pose.front, 0)]),
          source: FakePhotoSource('/tmp/x.jpg'),
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Below the fold in a test viewport, and a lazy ListView does not build
    // what it cannot show.
    final line = find.text('Photos stay on this device. Nothing is uploaded.');
    await tester.scrollUntilVisible(
      line,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(line, findsOneWidget);
  });
}
