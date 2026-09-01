import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/legal/domain/legal_copy.dart';
import 'package:mgk_lift/src/features/legal/domain/legal_document.dart';

/// The in-app legal copy is a second copy of `docs/` — two files that must say
/// the same thing. These tests are the tripwire: they fail if a doc is reworded
/// without the screen following, or if the app ships wording the doc never had.
///
/// Only **load-bearing** phrases are checked, not whole paragraphs, so ordinary
/// editing does not fight the suite while a substantive change still trips it.
/// Docs wrap and use markdown emphasis; the app copy does neither. Normalise
/// both to bare words on one line before comparing.
///
/// Deliberately the same shape as run's `test/legal/legal_copy_test.dart`. The
/// two apps ship different documents but they drift the same way.
String _normalise(String text) => text
    .replaceAll(RegExp(r'[*_`]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

void main() {
  String readDoc(String name) {
    final file = File('docs/$name');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'docs/$name is the source of truth for the in-app copy',
    );
    return _normalise(file.readAsStringSync());
  }

  String flatten(LegalDocument document) =>
      _normalise(document.allText.join(' '));

  /// Asserts a phrase is in both halves, naming which half lost it. Checking
  /// only the app would let a doc be quietly rewritten; checking only the doc
  /// would let the screen ship something nobody approved.
  void bothCarry(String app, String doc, String source, List<String> phrases) {
    for (final phrase in phrases) {
      expect(app, contains(phrase), reason: 'the in-app copy dropped: $phrase');
      expect(doc, contains(phrase), reason: '$source no longer says: $phrase');
    }
  }

  group('the privacy policy matches docs/privacy-policy.md', () {
    late String doc;
    late String app;

    setUp(() {
      doc = readDoc('privacy-policy.md');
      app = flatten(privacyPolicy);
    });

    test('carries every load-bearing sentence', () {
      bothCarry(app, doc, 'docs/privacy-policy.md', <String>[
        'We do not sell your data. You can delete everything at any time.',
        'Signing in backs them up.',
        'special-category data under UK GDPR',
        'we never send your progress photos',
        'taken together it is health information about one person',
        'We collect only what the training product needs (data minimisation).',
        'We do not sell personal data, and we do not use it for third-party '
            'advertising.',
        'The app is not directed at children under 16',
      ]);
    });

    test('names every processor it sends data to', () {
      // A processor added to the code and not to this list is the failure this
      // catches: the policy is what makes the sharing lawful, so a new name in
      // the pipeline has to reach the reader before it reaches the wire.
      bothCarry(app, doc, 'docs/privacy-policy.md', <String>[
        'Supabase',
        'OpenRouter',
        'eu-west-1 (Ireland)',
      ]);
    });

    test('says the coach can be turned off, and what that stops', () {
      bothCarry(app, doc, 'docs/privacy-policy.md', <String>[
        'The coach is the only part of the app that sends anything to an AI '
            'provider.',
        'no message, no training summary and no plan answer leaves the app for '
            'OpenRouter',
      ]);
    });

    test('describes progress photos as they actually behave', () {
      // The one claim in this policy that a code change can silently falsify:
      // photos are local because nothing uploads them, not because anything
      // enforces it. If a sync path ever reaches them, this sentence and the
      // screen's own line have to change in the same commit.
      bothCarry(app, doc, 'docs/privacy-policy.md', <String>[
        'Progress photos stay on this device.',
        'backing up your training does not include them',
      ]);
    });

    test('says what deletion removes, and what an account is shared with', () {
      bothCarry(app, doc, 'docs/privacy-policy.md', <String>[
        'Delete account removes every record we hold for you',
        'usage records are pruned after 31 days',
        'then pruned after 180 days',
      ]);
    });
  });

  group('the terms match docs/terms-of-use.md', () {
    late String doc;
    late String app;

    setUp(() {
      doc = readDoc('terms-of-use.md');
      app = flatten(termsOfUse);
    });

    test('carries every load-bearing sentence', () {
      bothCarry(app, doc, 'docs/terms-of-use.md', <String>[
        'It is not medical advice and is not a substitute for professional '
            'medical care.',
        'Consult a physician before starting any training programme',
        'Stop and seek medical attention if you experience chest pain, '
            'dizziness, shortness of breath',
        'They cannot account for your full medical history',
        'You are responsible for training within your own limits',
        'MGKCodes Ltd is not liable for injury',
        'You must be 16 or over to create an account.',
        'law of England and Wales',
      ]);
    });

    test('names the situations that need a physician', () {
      for (final risk in <String>['heart condition', 'injury', 'pregnant']) {
        expect(app, contains(risk));
        expect(doc, contains(risk));
      }
    });

    test('says the coach can be wrong', () {
      bothCarry(app, doc, 'docs/terms-of-use.md', <String>[
        'The coach is powered by a third-party AI model and can be wrong.',
        'do not rely on it for anything medical',
      ]);
    });

    test('promises nothing about billing while nothing can be billed', () {
      // Phase 3 has not landed. Until it does, the terms must not carry
      // subscription wording — a promise about renewal in front of somebody who
      // cannot be charged is worse than a gap, and Guideline 3.1.2(a) wants the
      // full auto-renew disclosure rather than a fragment of one.
      expect(
        app,
        contains('Everything the app does today is available without paying.'),
      );
      for (final premature in <String>[
        'auto-renew',
        'automatically renews',
        'per month',
        'free trial',
      ]) {
        expect(
          app,
          isNot(contains(premature)),
          reason:
              'the terms mention "$premature" but payments do not exist — '
              'finish Phase 3 and write the disclosure in full, together',
        );
      }
    });
  });

  group('the AI disclosure matches docs/ai-disclosure.md', () {
    late String doc;
    late String app;

    setUp(() {
      doc = readDoc('ai-disclosure.md');
      app = flatten(aiDisclosure);
    });

    test('names the provider and what reaches it', () {
      bothCarry(app, doc, 'docs/ai-disclosure.md', <String>[
        'Your coach is a large language model, not a person',
        'We send your request to OpenRouter',
        'The messages in the conversation, as you wrote them.',
        'your injury notes if you gave any',
      ]);
    });

    test('is explicit about what never leaves', () {
      bothCarry(app, doc, 'docs/ai-disclosure.md', <String>[
        'Your name, email address, or account identifier.',
        'Your progress photos.',
        'The request is made by our server, not by your phone.',
      ]);
    });

    test('tells the reader how to stop it', () {
      bothCarry(app, doc, 'docs/ai-disclosure.md', <String>[
        'Use the AI coach in Settings turns this off completely.',
        'Turning it off does not un-send what you have already said.',
      ]);
    });
  });

  group('every document is renderable', () {
    // Cheap structural guard. A document with an empty section renders as a
    // heading over nothing, which reads as a bug rather than as a short
    // section, and no phrase check above would catch it.
    for (final entry in <String, LegalDocument>{
      'privacy policy': privacyPolicy,
      'terms of use': termsOfUse,
      'AI disclosure': aiDisclosure,
    }.entries) {
      test('the ${entry.key} has a title, a lead and no empty section', () {
        final document = entry.value;
        expect(document.title, isNotEmpty);
        expect(document.lead, isNotNull);
        expect(document.sections, isNotEmpty);
        for (final section in document.sections) {
          expect(
            section.paragraphs.isNotEmpty || section.bullets.isNotEmpty,
            isTrue,
            reason: 'section "${section.heading}" has a heading and no body',
          );
          for (final text in <String>[
            ...section.paragraphs,
            ...section.bullets,
          ]) {
            expect(text.trim(), isNotEmpty);
          }
        }
      });
    }
  });
}
