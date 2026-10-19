import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_auth/mgk_auth.dart';

void main() {
  group('what could be an address', () {
    test('an ordinary address is one', () {
      expect(looksLikeEmail('you@example.com'), isTrue);
      expect(looksLikeEmail(' you+run@mail.example.co.uk '), isTrue);
    });

    test('what plainly is not one is refused', () {
      for (final value in <String>[
        '',
        'you',
        'you@',
        '@example.com',
        'you@example',
        'you@@example.com',
        'you@.com',
        'you@example.',
        'y ou@example.com',
      ]) {
        expect(looksLikeEmail(value), isFalse, reason: value);
      }
    });
  });

  group('Did you mean …?', () {
    test('a slip in a common domain is suggested back', () {
      expect(suggestEmail('you@gmial.com'), 'you@gmail.com');
      expect(suggestEmail('you@gmail.con'), 'you@gmail.com');
      expect(suggestEmail('you@hotmial.co.uk'), 'you@hotmail.co.uk');
      expect(suggestEmail('you@outlok.com'), 'you@outlook.com');
      expect(suggestEmail('you@icloud.cm'), 'you@icloud.com');
    });

    test('what was typed before the @ is kept as it was', () {
      expect(suggestEmail('Sam.Smith@gmial.com'), 'Sam.Smith@gmail.com');
    });

    test('a common domain is never corrected', () {
      expect(suggestEmail('you@gmail.com'), isNull);
      expect(suggestEmail('you@me.com'), isNull);
      expect(suggestEmail('you@mac.com'), isNull);
    });

    test('a domain nowhere near a common one is left alone', () {
      expect(suggestEmail('you@mgkcodes.com'), isNull);
      expect(suggestEmail('you@example.org'), isNull);
    });

    test('two slips in a short domain are a different domain, not a typo', () {
      expect(suggestEmail('you@mx.co'), isNull);
    });

    test('nothing is suggested for something that is not an address', () {
      expect(suggestEmail('gmial.com'), isNull);
    });
  });
}
