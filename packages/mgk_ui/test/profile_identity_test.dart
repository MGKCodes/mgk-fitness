import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// A 1x1 transparent PNG, so an image can be drawn without an asset bundle.
final Uint8List _onePixel = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(
    body: Center(child: SizedBox(width: 360, child: child)),
  ),
);

void main() {
  group('ProfileHeader', () {
    testWidgets('names the account for the suite, and the app it also opens', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const ProfileHeader(line: 'Welcome back', otherApp: 'Lift')),
      );
      await tester.pumpAndSettle();

      expect(find.text('$kPlatformName Account'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.textContaining('One account for every'), findsOneWidget);
      expect(find.textContaining('works in Lift'), findsOneWidget);
    });

    testWidgets('shows which app this is above the account', (tester) async {
      await tester.pumpWidget(
        _host(
          const ProfileHeader(
            line: 'Create your account',
            otherApp: 'Run',
            app: Text('the app'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('the app')).dy,
        lessThan(tester.getTopLeft(find.text('$kPlatformName Account')).dy),
      );
    });
  });

  testWidgets('AppIdentity is the icon with the name under it', (tester) async {
    await tester.pumpWidget(
      _host(AppIdentity(icon: MemoryImage(_onePixel), name: 'Lift')),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Lift'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(Image)).dy,
      lessThan(tester.getTopLeft(find.text('Lift')).dy),
    );
    // One name for a screen reader, not the picture and the name.
    expect(find.bySemanticsLabel('Lift'), findsOneWidget);
  });

  testWidgets('keeps the name on one line on a narrow phone', (tester) async {
    // "MGKFitness Account" is wider than "MGKFitness Profile", and wrapped
    // over two lines on a 375-point phone before it was allowed to shrink.
    Future<double> heightAt(double width) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: const ProfileHeader(
                  line: 'Welcome back',
                  otherApp: 'Run',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .getRect(
            find.ancestor(
              of: find.text('$kPlatformName Account'),
              matching: find.byType(FittedBox),
            ),
          )
          .height;
    }

    final wide = await heightAt(600);
    final narrow = await heightAt(260);
    expect(narrow, lessThanOrEqualTo(wide));
  });

  group('initialsFor', () {
    test('one or two initials, from at most two words', () {
      expect(initialsFor('Sam'), 'S');
      expect(initialsFor('sam kay'), 'SK');
      expect(initialsFor('Anna Maria Luisa'), 'AM');
      expect(initialsFor('  '), isNull);
      expect(initialsFor(null), isNull);
    });
  });

  group('ProfileCard', () {
    testWidgets('signed in: the title, the address, and the plan', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        _host(
          ProfileCard(
            avatar: const InitialsAvatar(initials: 'S', size: 64),
            title: 'Sam',
            email: 'sam@example.com',
            plan: 'Coach',
            onTap: () => opened++,
          ),
        ),
      );

      expect(find.text('S'), findsOneWidget);
      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('sam@example.com'), findsOneWidget);
      expect(find.text('Coach'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      await tester.tap(find.text('Sam'));
      expect(opened, 1);
    });

    testWidgets('with no account: where things stand, and no chevron when it '
        'goes nowhere', (tester) async {
      await tester.pumpWidget(
        _host(
          const ProfileCard.withoutAccount(
            avatar: InitialsAvatar(initials: null, size: 64),
            title: 'Not signed in',
            note: 'Your training is on this phone only.',
          ),
        ),
      );

      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(find.text('Your training is on this phone only.'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });
  });
}
