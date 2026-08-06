import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/shape_question.dart';

/// "What are you after?" — the first step of the plan flow.
///
/// These assertions were written against the pre-account intro script, where
/// this question used to live. They moved here with the question itself
/// (ADR-0019); what they check has not changed, because the reason for chips
/// over a text field has not changed either.
void main() {
  group('the shapes are offered in the runner\'s words', () {
    test('every plan shape is reachable, plus not knowing', () {
      final offered = shapeOptions.map((o) => o.shape).toSet();
      for (final shape in PlanShape.values) {
        expect(
          offered,
          contains(shape),
          reason: 'a runner who wants $shape must be able to say so',
        );
      }
      expect(
        offered,
        contains(null),
        reason: '"not sure yet" is a real answer, and the coach can resolve it',
      );
    });

    test('and never in the vocabulary of the shape system', () {
      // Nobody has ever thought "I am a horizon".
      for (final option in shapeOptions) {
        for (final jargon in <String>['block', 'horizon', 'rhythm', 'log']) {
          expect(
            option.label.toLowerCase(),
            isNot(contains(jargon)),
            reason: '"${option.label}" leaks the internal name',
          );
        }
      }
    });

    test('no two options say the same thing', () {
      final labels = shapeOptions.map((o) => o.label).toSet();
      expect(labels, hasLength(shapeOptions.length));
    });
  });

  group('what the coach asks', () {
    test('uses the name the intro gathered', () {
      expect(shapeQuestion(name: 'Sam'), contains('Sam'));
    });

    test('and does not invent one where the runner skipped it', () {
      final said = shapeQuestion();
      expect(said, isNot(contains('null')));
      expect(said, contains('What are you after?'));
    });
  });

  /// `PERSONA` says the coach never uses an em dash. This screen is scripted,
  /// and the intake on the very next screen is not, so a seam here is a seam a
  /// runner sees mid-conversation.
  test('the coach never uses an em dash, scripted or not', () {
    final everything = <String>[
      shapeQuestion(),
      shapeQuestion(name: 'Sam'),
      shapeUnparsed,
      for (final o in shapeOptions) o.label,
      for (final o in shapeOptions) o.detail,
    ];
    for (final line in everything) {
      expect(line, isNot(contains('—')), reason: 'em dash in: $line');
    }
  });
}
