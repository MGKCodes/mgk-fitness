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

Future<void> pumpTall(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

Future<void> pumpSurface(
  WidgetTester tester, {
  required bool isEntitled,
  List<ProgressPhoto> photos = const <ProgressPhoto>[],
  VoidCallback? onSubscribe,
}) => pumpTall(
  tester,
  PhotosSurface(
    library: InMemoryPhotoLibrary(photos),
    source: FakePhotoSource('/tmp/x.jpg'),
    isEntitled: isEntitled,
    onSubscribe: onSubscribe,
    now: now,
  ),
);

void main() {
  group('never subscribed', () {
    testWidgets('meets the offer, not an empty state', (
      WidgetTester tester,
    ) async {
      // An empty state with a disabled button tells somebody who has never had
      // this feature nothing about what it would be.
      await pumpSurface(tester, isEntitled: false);

      expect(find.text('One stream per pose'), findsOneWidget);
      expect(find.text('Play it back'), findsOneWidget);
      // The empty state's call to action must not be here.
      expect(find.textContaining('Start with front'), findsNothing);
    });

    testWidgets('says photos never reach the coach', (
      WidgetTester tester,
    ) async {
      // The one promise worth making on a screen selling body photography, and
      // it is one the AI disclosure already makes in the other direction.
      await pumpSurface(tester, isEntitled: false);

      expect(
        find.textContaining('Never sent to the coach or any AI provider'),
        findsOneWidget,
      );
    });

    testWidgets('does not show a button that cannot do anything', (
      WidgetTester tester,
    ) async {
      // Payments do not exist yet. A dead "Unlock photos" is worse than a
      // sentence saying subscriptions are not open.
      await pumpSurface(tester, isEntitled: false);

      expect(find.text('Unlock photos'), findsNothing);
      expect(
        find.textContaining('Subscriptions are not open yet'),
        findsOneWidget,
      );
    });

    testWidgets('and shows one once there is a store to open', (
      WidgetTester tester,
    ) async {
      var opened = 0;
      await pumpSurface(tester, isEntitled: false, onSubscribe: () => opened++);

      await tester.tap(find.text('Unlock photos'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });
  });

  group('lapsed, with photos already taken', () {
    testWidgets('keeps the photos and loses the camera', (
      WidgetTester tester,
    ) async {
      // The rule main.dart already applies to coach memory: stopping paying
      // must not lock somebody out of what was stored about them. It matters
      // more here — a progress photo cannot be recreated from anything else.
      await pumpSurface(
        tester,
        isEntitled: false,
        photos: <ProgressPhoto>[photo(Pose.front, 0), photo(Pose.front, 3)],
      );

      // Still the library, not the offer.
      expect(find.text(Pose.front.label), findsOneWidget);
      expect(find.text('One stream per pose'), findsNothing);

      // And nothing anywhere offers to add one. The empty Back card in
      // particular must not keep the add-a-photo placeholder: it looks
      // tappable, does nothing, and gives no reason why.
      expect(find.byIcon(Icons.add_a_photo_outlined), findsNothing);
      expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
    });

    testWidgets('says what still works before what does not', (
      WidgetTester tester,
    ) async {
      // Leading with the loss would misstate what happened: everything they
      // shot is still theirs.
      await pumpSurface(
        tester,
        isEntitled: false,
        photos: <ProgressPhoto>[photo(Pose.front, 0)],
      );

      expect(find.text('Your photos are still here'), findsOneWidget);
      expect(
        find.textContaining('delete them — all of that keeps working'),
        findsOneWidget,
      );
    });

    testWidgets('offers a way back when there is a store', (
      WidgetTester tester,
    ) async {
      await pumpSurface(
        tester,
        isEntitled: false,
        photos: <ProgressPhoto>[photo(Pose.front, 0)],
        onSubscribe: () {},
      );

      expect(find.text('Resubscribe'), findsOneWidget);
    });

    testWidgets('and no dead button when there is not', (
      WidgetTester tester,
    ) async {
      await pumpSurface(
        tester,
        isEntitled: false,
        photos: <ProgressPhoto>[photo(Pose.front, 0)],
      );

      expect(find.text('Resubscribe'), findsNothing);
      // The reassurance still stands on its own.
      expect(find.text('Your photos are still here'), findsOneWidget);
    });
  });

  group('entitled', () {
    testWidgets('gets the camera back', (WidgetTester tester) async {
      await pumpSurface(
        tester,
        isEntitled: true,
        photos: <ProgressPhoto>[photo(Pose.front, 0)],
      );

      expect(find.text('Your photos are still here'), findsNothing);
      expect(find.text('One stream per pose'), findsNothing);
    });

    testWidgets('an entitled empty library is the habit, not the pitch', (
      WidgetTester tester,
    ) async {
      await pumpSurface(tester, isEntitled: true);

      expect(find.textContaining('Start with front'), findsOneWidget);
      expect(find.text('One stream per pose'), findsNothing);
    });
  });

  group('the default', () {
    testWidgets('is locked, not open', (WidgetTester tester) async {
      // The one mistake worth making impossible: a caller that forgets to pass
      // the entitlement must not hand over the paid half. Matches PlanSurface.
      await pumpTall(
        tester,
        PhotosSurface(
          library: InMemoryPhotoLibrary(),
          source: FakePhotoSource('/tmp/x.jpg'),
          now: now,
        ),
      );

      expect(find.text('One stream per pose'), findsOneWidget);
    });
  });
}
