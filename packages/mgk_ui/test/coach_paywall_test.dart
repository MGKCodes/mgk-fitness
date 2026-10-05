import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// The coach's paywall, as both apps show it.
void main() {
  // A 1x1 transparent PNG, for the app icon, that actually decodes: the
  // bytes copied from profile_identity_test.dart carry a bad checksum, which
  // only shows once a later test finds the failed image in the cache.
  final icon = MemoryImage(
    Uint8List.fromList(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00,
      0x00, 0x05, 0x00, 0x01, 0x7A, 0x5E, 0xAB, 0x3F, 0x00, 0x00, 0x00, 0x00,
      0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]),
  );

  const tiers = <PaywallTier>[
    PaywallTier(
      id: 'coach',
      name: 'Coach',
      price: '£0.99',
      period: 'month',
      line: 'Everything above',
      recommended: true,
    ),
    PaywallTier(
      id: 'premium',
      name: 'Premium Coach',
      price: '£2.99',
      period: 'month',
      line: '3× the coaching, sharper model',
    ),
  ];

  const benefits = <PaywallBenefit>[
    PaywallBenefit(
      icon: Icons.event_note_outlined,
      title: 'Your own training plan',
      detail: 'Built from your goal and the days you can train.',
    ),
    PaywallBenefit(
      icon: Icons.forum_outlined,
      title: 'A coach on call',
      detail: 'It reads your recent training before it answers.',
    ),
    PaywallBenefit(
      icon: Icons.photo_camera_outlined,
      title: 'Weekly progress photos',
      detail: 'One a week per pose, kept privately.',
    ),
    PaywallBenefit(
      icon: Icons.swap_horiz,
      title: 'Smart exercise swaps',
      detail: 'When a machine is taken, a swap that trains the same thing.',
    ),
  ];

  Future<List<PaywallTier>> pump(
    WidgetTester tester, {
    List<PaywallTier> offered = tiers,
    String? note,
    bool signedOut = false,
    TargetPlatform platform = TargetPlatform.iOS,
  }) async {
    final bought = <PaywallTier>[];
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          // An iPhone's own bands, which a test surface does not have.
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 47, bottom: 34),
          ),
          child: CoachPaywall(
            appIcon: icon,
            appName: 'MGKFitness: Lift',
            photo: 'assets/none.webp',
            headline: 'A plan built for you, and a coach to ask',
            benefits: benefits,
            tiers: offered,
            note: note,
            signedOut: signedOut,
            platform: platform,
            onSubscribe: bought.add,
            onRestore: () {},
            onClose: () {},
            onTerms: () {},
            onPrivacy: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    return bought;
  }

  testWidgets('fits a 390 by 844 phone without scrolling', (tester) async {
    await pump(tester);

    final scroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(CoachPaywall),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scroll.position.maxScrollExtent, 0);
  });

  testWidgets('recommends one tier, and says so on its card alone', (
    tester,
  ) async {
    await pump(tester);

    // Recommended, never "Most popular": that would be a claim about other
    // people's purchases, made with no data behind it.
    expect(find.text('Recommended'), findsOneWidget);
    expect(find.text('Most popular'), findsNothing);
    final label = tester.getCenter(find.text('Recommended'));
    final coach = tester.getRect(find.text('Coach').first);
    final premium = tester.getRect(find.text('Premium Coach'));
    expect((label.dx - coach.left).abs(), lessThan(premium.left - coach.left));
    expect(label.dy, lessThan(coach.top));
  });

  testWidgets("shows the coach's own C, the mark that opens it", (
    tester,
  ) async {
    await pump(tester);

    // So what is for sale is plainly the thing the C at the foot of every
    // tab opens. Drawn, not tappable: here it has nowhere to go.
    expect(find.byType(CoachMarkGlyph), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(CoachMarkGlyph),
        matching: find.byType(IgnorePointer),
      ),
      findsWidgets,
    );
  });

  testWidgets('says which app is charging', (tester) async {
    await pump(tester);

    expect(find.text('MGKFitness: Lift'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is Image && w.image == icon),
      findsOneWidget,
    );
  });

  testWidgets('starts on the first tier and buys what is chosen', (
    tester,
  ) async {
    final bought = await pump(tester);

    expect(find.text('Subscribe · £0.99/month'), findsOneWidget);
    await tester.tap(find.text('Premium Coach'));
    await tester.pump();
    expect(find.text('Subscribe · £2.99/month'), findsOneWidget);

    await tester.tap(find.text('Subscribe · £2.99/month'));
    expect(bought.single.id, 'premium');
  });

  testWidgets('each tier shows its price as its largest figure', (
    tester,
  ) async {
    await pump(tester);

    for (final price in <String>['£0.99', '£2.99']) {
      expect(find.textContaining(price, findRichText: true), findsWidgets);
    }
    expect(find.text('3× the coaching, sharper model'), findsOneWidget);
  });

  testWidgets('a benefit opens the sentence behind it', (tester) async {
    await pump(tester);

    expect(find.text('A coach on call'), findsOneWidget);
    expect(find.textContaining('reads your recent training'), findsNothing);

    await tester.tap(find.text('A coach on call'));
    await tester.pumpAndSettle();
    expect(find.textContaining('reads your recent training'), findsOneWidget);
  });

  testWidgets('carries what Guideline 3.1.2 asks for', (tester) async {
    await pump(tester);

    expect(find.text('Restore'), findsOneWidget);
    expect(find.text('Terms'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.textContaining('every month until you cancel'), findsOneWidget);
    expect(find.textContaining('Tracking stays free'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets('names the right store on Android', (tester) async {
    await pump(tester, platform: TargetPlatform.android);

    expect(find.textContaining('Google Play'), findsOneWidget);
    expect(find.textContaining('Apple ID'), findsNothing);
  });

  testWidgets('says when an account comes first', (tester) async {
    await pump(tester, signedOut: true);

    expect(find.textContaining("You'll sign in first"), findsOneWidget);
  });

  testWidgets('shows a note when there is one', (tester) async {
    await pump(tester, note: 'Your payment is pending with the App Store.');

    expect(
      find.text('Your payment is pending with the App Store.'),
      findsOneWidget,
    );
  });

  testWidgets('with nothing on sale, says so and buys nothing', (tester) async {
    await pump(tester, offered: const <PaywallTier>[]);

    expect(find.text('Not available to buy yet'), findsOneWidget);
    final button = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
    expect(button.onPressed, isNull);
  });
}
