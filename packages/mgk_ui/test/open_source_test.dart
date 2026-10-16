import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

void main() {
  group('sourceCodeUri', () {
    test("opens the app's own folder on main, never a build's tag", () {
      expect(
        sourceCodeUri('mgk_run').toString(),
        'https://github.com/MGKCodes/mgk-fitness/tree/main/apps/mgk_run',
      );
      expect(
        sourceCodeUri('mgk_lift').toString(),
        'https://github.com/MGKCodes/mgk-fitness/tree/main/apps/mgk_lift',
      );
    });
  });

  group('problemReportUri', () {
    final Uri uri = problemReportUri(
      to: 'run@mgkfitness.mgkcodes.com',
      product: 'MGKFitness: Run',
      version: '1.0.1',
      system: 'ios 18.1',
    );

    test('is an email to the support address', () {
      expect(uri.scheme, 'mailto');
      expect(uri.path, 'run@mgkfitness.mgkcodes.com');
    });

    test('names the app and version in the subject and the body', () {
      expect(
        uri.queryParameters['subject'],
        'A problem with MGKFitness: Run 1.0.1',
      );
      final String body = uri.queryParameters['body']!;
      expect(body, startsWith('What happened:'));
      expect(body, contains('What you expected instead:'));
      expect(body, endsWith('MGKFitness: Run 1.0.1 on ios 18.1'));
    });

    test('writes spaces as %20, not +, which some mail apps show as is', () {
      final String raw = uri.toString();
      expect(raw, contains('A%20problem%20with'));
      expect(raw, isNot(contains('+')));
    });
  });
}
