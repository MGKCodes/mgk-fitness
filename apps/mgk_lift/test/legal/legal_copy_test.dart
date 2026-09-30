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
        'Signing in stores them on our servers.',
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
        'RevenueCat',
        'eu-west-1 (Ireland)',
      ]);
    });

    test('names Apple and Google, and what signing in with them passes on', () {
      // The redesign's Phase 1 added both. What they hand over is the claim
      // that makes them lawful here: an address and an identifier (O1), and
      // the revocation Apple requires when an account made with it goes.
      bothCarry(app, doc, 'docs/privacy-policy.md', <String>[
        'If you sign in with Apple or Google, that is what they pass us too: '
            'an email address and an identifier, and nothing else.',
        'Apple and Google — only if you sign in with them.',
        "end the app's access to your Apple ID",
        'You can sign in with Apple, with Google, or with an email address '
            'and a password.',
      ]);
    });

    test('says what a purchase tells RevenueCat, and what it tells us', () {
      // RevenueCat reached the pipeline on 2026-09-29 and this is the sentence
      // that makes that lawful: what goes to it is an identifier and nothing
      // from the training log.
      bothCarry(app, doc, 'docs/privacy-policy.md', <String>[
        'We send it your account identifier and nothing else: no training, no '
            'photos, and nothing you said to your coach.',
        'We never see your card or payment details.',
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
      // This test used to pin "Progress photos stay on this device", and it did
      // its job: the commit that added the bucket could not land without coming
      // through here. Now it pins what replaced it.
      bothCarry(app, doc, 'docs/privacy-policy.md', <String>[
        'Progress photos are part of the paid tier.',
        'copied to a private storage bucket in our Supabase project',
        'They are never sent to the coach or to any AI provider.',
        'Delete account removes them from our servers along with everything '
            'else, the picture files included.',
      ]);
    });

    test('no longer claims photos never leave the phone', () {
      // The specific way this page could rot: a sentence that was true for
      // three weeks and is now the opposite of what the code does. Naming the
      // dead phrasing is cheaper than trusting a reader to notice its absence.
      for (final stale in <String>[
        'Progress photos stay on this device',
        'They are not uploaded',
        'backing up your training does not include them',
      ]) {
        expect(
          app,
          isNot(contains(stale)),
          reason: 'the policy still says photos do not leave the phone: $stale',
        );
      }
    });

    test('says what deletion removes, and what an account is shared with', () {
      bothCarry(app, doc, 'docs/privacy-policy.md', <String>[
        'Delete account removes every record we hold for you',
        'usage records are pruned after 31 days',
        'then pruned after 180 days',
      ]);
    });

    test(
      'says deletion is a choice, and what the narrow one cannot promise',
      () {
        // The policy describes a shape the screen has to keep. If deletion ever
        // stops asking, or starts promising the profile survives, this is what
        // notices.
        bothCarry(app, doc, 'docs/privacy-policy.md', <String>[
          'Deletion asks how much',
          'Delete this app only, and we erase everything this app holds',
          'if Run holds no data, there is nothing left for the account to be '
              'for, so it is removed as well',
        ]);
      },
    );
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

    test('carries the auto-renew disclosure in full', () {
      // This case used to insist the terms said NOTHING about billing, because
      // nothing could be billed and Guideline 3.1.2(a) wants the disclosure
      // whole or not at all. Payments landed on 2026-09-29, so it now insists
      // on the whole of it: what is sold, who charges, when it renews, how
      // much notice cancelling needs, and where to do it.
      bothCarry(app, doc, 'docs/terms-of-use.md', <String>[
        'sold as an auto-renewing subscription, in two tiers, Coach and '
            'Premium Coach',
        'Tracking, saved workouts, history and stats are free and stay free.',
        'Payment is charged to your Apple ID or Google Play account at '
            'confirmation of purchase.',
        'Your subscription automatically renews each month unless auto-renew '
            'is turned off at least 24 hours before the end of the current '
            'period.',
        'Your account is charged for renewal within 24 hours before the end of '
            'the current period.',
        'Manage or cancel it through your store',
        'Cancelling stops the next renewal.',
        "Refunds are the store's decision, not ours.",
      ]);
      // The sentence the disclosure replaced, which is now false.
      expect(
        app,
        isNot(
          contains('Everything the app does today is available without paying'),
        ),
      );
      // No trial is sold. A disclosure that mentioned one would owe the reader
      // its length and what it converts to, and none of that exists.
      expect(app, isNot(contains('free trial')));
      expect(doc, isNot(contains('free trial')));
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

  group('the published pages say what the app says', () {
    // web/public/lift/*.html is what App Review and Play read at the URLs in
    // the listings, and it is generated from docs/ by
    // tool/build_legal_pages.py. A page that is missing, stale, or carrying a
    // repo note fails here rather than in a review.
    String page(String name) {
      final file = File('../../web/public/lift/$name');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'web/public/lift/$name is missing. Run '
            '`python tool/build_legal_pages.py` from apps/mgk_lift.',
      );
      final text = file
          .readAsStringSync()
          .replaceAll(
            RegExp(r'<(style|script)[^>]*>.*?</\1>', dotAll: true),
            ' ',
          )
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&middot;', '·');
      return _normalise(text);
    }

    String dated(String doc) =>
        RegExp(r'Last updated: (\d+ \w+ \d{4})').firstMatch(doc)!.group(1)!;

    for (final (source, served, phrases) in <(String, String, List<String>)>[
      (
        'privacy-policy.md',
        'privacy-policy.html',
        <String>[
          'We do not sell your data. You can delete everything at any time.',
          'special-category data under UK GDPR',
          'RevenueCat',
          'They are never sent to the coach or to any AI provider.',
        ],
      ),
      (
        'terms-of-use.md',
        'terms-of-use.html',
        <String>[
          'Your subscription automatically renews each month unless '
              'auto-renew is turned off at least 24 hours before the end of '
              'the current period.',
          'MGKCodes Ltd is not liable for injury',
        ],
      ),
      (
        'ai-disclosure.md',
        'ai-disclosure.html',
        <String>['We send your request to OpenRouter'],
      ),
    ]) {
      test('$served is current with docs/$source', () {
        final doc = readDoc(source);
        final html = page(served);
        for (final phrase in phrases) {
          expect(html, contains(phrase), reason: '$served lost: $phrase');
        }
        // Stale is the likelier failure than wrong: an edit to the doc with
        // no regeneration. The date moves with every substantive edit.
        if (doc.contains('Last updated:')) {
          expect(
            html,
            contains('Last updated: ${dated(doc)}'),
            reason: '$served predates docs/$source. Regenerate it.',
          );
        }
      });

      test('$served carries no repo notes', () {
        final html = page(served);
        for (final note in <String>[
          'NOT FOR PUBLICATION',
          'legal_copy.dart',
          'legal_copy_test',
        ]) {
          expect(html, isNot(contains(note)), reason: '$served shows: $note');
        }
      });
    }
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
