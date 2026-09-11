import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/settings/domain/profile_photo.dart';

/// **Three states, none of them a failure.**
///
/// A photo if one was chosen, initials if a name was given, and the generic
/// mark if neither. The intro accepts any name and accepts none — "I would
/// rather you did not use a name" is a reachable answer that `updateName`
/// exists to honour — and the photo is optional by construction. So the
/// fallbacks are ordinary, and the generic icon has to look like a choice
/// rather than a hole.
///
/// These tests are about [initialsFor], which is the half with rules in it.
void main() {
  group('initials come off a name, at most two', () {
    test('one word gives one letter', () {
      expect(initialsFor('Sam'), 'S');
    });

    test('two words give two', () {
      expect(initialsFor('Sam Kay'), 'SK');
    });

    test('a long name still gives two', () {
      // Four initials are unreadable in a 40px circle, which is the size this
      // renders at in the settings header.
      expect(initialsFor('Anna Maria Luisa de Medici'), 'AM');
    });

    test('they are upper case whatever was typed', () {
      expect(initialsFor('sam kay'), 'SK');
    });

    test('extra whitespace is not a word', () {
      expect(initialsFor('  Sam   Kay  '), 'SK');
    });
  });

  group('no name is not a failure', () {
    test('null, empty and whitespace all yield nothing to draw', () {
      // Null is the signal the avatar reads to draw the generic mark. An empty
      // string would be a third state, and `AuthRepository.updateName` already
      // refuses to store one for exactly that reason.
      expect(initialsFor(null), isNull);
      expect(initialsFor(''), isNull);
      expect(initialsFor('   '), isNull);
    });
  });

  group('a name is not a format', () {
    test('non-Latin scripts take the same path', () {
      // The intro accepts any name on the grounds that every rule which
      // rejects one rejects somebody real. Initials are the first character of
      // each of the first two words, whatever those characters are.
      expect(initialsFor('Ελένη'), 'Ε');
      expect(initialsFor('Юрий Гагарин'), 'ЮГ');
    });

    test('an emoji is a character like any other', () {
      // Grapheme clusters, not code units: `String.characters` is why this
      // yields one emoji rather than half of one, which would render as the
      // replacement glyph.
      expect(initialsFor('🏃 Runner'), '🏃R');
    });

    test('a hyphenated name is one word', () {
      expect(initialsFor('Jean-Luc Picard'), 'JP');
    });
  });
}
