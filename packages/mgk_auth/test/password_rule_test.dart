import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_auth/mgk_auth.dart';

void main() {
  test('eight characters, a number and a symbol pass', () {
    expect(PasswordCheck.of('Password1!').passes, isTrue);
  });

  test("iOS's suggested passwords pass as they come", () {
    // Letters in groups joined by hyphens, with one digit somewhere.
    expect(PasswordCheck.of('hukvo1-qedgos-Bykzyx').passes, isTrue);
  });

  test('a space counts as a symbol', () {
    expect(PasswordCheck.of('correct horse 7').passes, isTrue);
  });

  test('each missing part is named on its own', () {
    final short = PasswordCheck.of('Ab1!');
    expect(short.longEnough, isFalse);
    expect(short.hasNumber, isTrue);
    expect(short.hasSymbol, isTrue);

    final noNumber = PasswordCheck.of('Password!!');
    expect(noNumber.hasNumber, isFalse);
    expect(noNumber.passes, isFalse);

    final noSymbol = PasswordCheck.of('Password12');
    expect(noSymbol.hasSymbol, isFalse);
    expect(noSymbol.passes, isFalse);
  });

  test('length is counted in characters, not bytes', () {
    // Seven characters, more than eight bytes in UTF-8.
    expect(PasswordCheck.of('éééé1!é').longEnough, isFalse);
    expect(PasswordCheck.of('éééé1!éé').longEnough, isTrue);
  });

  test('letters in any script, with their marks, are letters', () {
    // `e` and a combining acute: a letter, not a symbol.
    expect(PasswordCheck.of('passéword1').hasSymbol, isFalse);
    expect(PasswordCheck.of('пароль12').hasSymbol, isFalse);
  });

  test('numbers in any script are numbers', () {
    expect(PasswordCheck.of('password٣!').hasNumber, isTrue);
  });

  test('an empty password fails every part', () {
    final empty = PasswordCheck.of('');
    expect(empty.longEnough, isFalse);
    expect(empty.hasNumber, isFalse);
    expect(empty.hasSymbol, isFalse);
  });
}
