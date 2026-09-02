import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/legal/domain/legal_copy.dart';
import 'package:mgk_run/src/features/legal/domain/legal_document.dart';

/// The in-app legal copy is a second copy of `docs/` — two files that must say
/// the same thing. These tests are the tripwire: they fail if a doc is reworded
/// without the screen following, or if the app ships wording the doc never had.
///
/// Only **load-bearing** phrases are checked, not whole paragraphs, so ordinary
/// editing does not fight the suite while a substantive change still trips it.
/// Docs wrap and use markdown emphasis; the app copy does neither. Normalise
/// both to bare words on one line before comparing.
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

  group('the medical disclaimer matches docs/medical-disclaimer.md', () {
    late String doc;
    late String app;

    setUp(() {
      doc = readDoc('medical-disclaimer.md');
      app = flatten(medicalDisclaimer);
    });

    test('carries every load-bearing sentence', () {
      const required = <String>[
        'It is not medical advice and is not a substitute for professional '
            'medical care.',
        'Consult a physician before starting any training programme',
        'Stop and seek medical attention if you experience chest pain, '
            'dizziness, shortness of breath',
        'cannot account for your full medical history',
        'Metrics such as calories and effort are estimates, not measurements.',
        'You are responsible for training within your own limits',
        'MGKCodes Ltd is not liable for injury',
      ];
      for (final phrase in required) {
        expect(
          app,
          contains(phrase),
          reason: 'the in-app disclaimer dropped: $phrase',
        );
        expect(
          doc,
          contains(phrase),
          reason: 'docs/medical-disclaimer.md no longer says: $phrase',
        );
      }
    });

    test('names the situations that need a physician', () {
      for (final risk in <String>['heart condition', 'injury', 'pregnant']) {
        expect(app, contains(risk));
        expect(doc, contains(risk));
      }
    });
  });

  group('the privacy policy matches docs/privacy-policy.md', () {
    late String doc;
    late String app;

    setUp(() {
      doc = readDoc('privacy-policy.md');
      app = flatten(privacyPolicy);
    });

    test('names the current sub-processors and not the old one', () {
      // The provider swap to an OpenRouter gateway (ADR-0007) has to be visible
      // in both. A policy naming the wrong processor is a compliance defect.
      //
      // All four are pinned, not just the interesting ones. A sub-processor
      // added to the architecture and not to the policy is the same defect as
      // one named after it was dropped, and it is the more likely direction:
      // RevenueCat (ADR-0028) arrived as a purchase decision, and remembering
      // that a purchase decision is also a disclosure is exactly what nobody
      // does at the time.
      for (final text in <String>[doc, app]) {
        expect(text, contains('Supabase'));
        expect(text, contains('OpenRouter'));
        expect(text, contains('RevenueCat'));
        expect(text, contains('MapTiler'));
        expect(
          text,
          isNot(contains('Anthropic')),
          reason: 'Anthropic is no longer the sub-processor',
        );
      }
    });

    test('states the special-category basis and the HealthKit limits', () {
      for (final phrase in <String>[
        'special-category',
        'HealthKit',
        'never used for advertising',
      ]) {
        expect(app, contains(phrase));
        expect(doc, contains(phrase));
      }
    });

    test('is honest that the runner\'s own words go to the model', () {
      // The claim this replaced was "structured training context (goals,
      // volumes, session history)". True while only the planning surfaces
      // existed; false from the moment the coach could hold a conversation,
      // because `chat` sends up to twenty turns of free text — the field most
      // likely to carry a symptom. A policy that kept the old wording would
      // have been a misrepresentation about special-category data.
      for (final phrase in <String>[
        'last twenty messages',
        'as you wrote them',
      ]) {
        expect(app, contains(phrase));
        expect(doc, contains(phrase));
      }
      // And no retreat to the comfortable version.
      expect(
        app,
        isNot(contains('structured training context')),
        reason: 'the understated claim is back in the app copy',
      );
      expect(doc, isNot(contains('structured training context')));
    });

    test('says what never leaves, without overclaiming anonymity', () {
      for (final phrase in <String>[
        'never send raw GPS traces',
        'not pretend the rest is anonymous',
      ]) {
        expect(app, contains(phrase));
        expect(doc, contains(phrase));
      }
    });

    test('states that backup is optional and starts off', () {
      // Explicit consent is the Art. 9 basis and it is a real switch, so the
      // policy has to say the switch exists and which way it starts.
      for (final phrase in <String>[
        'off until you ask',
        'It starts off',
        'Turning it back off deletes what we have stored',
      ]) {
        expect(app, contains(phrase));
        expect(doc, contains(phrase));
      }
    });

    test('names the restore path and its one-way guarantee', () {
      for (final phrase in <String>[
        'Signing in on a new phone pulls them back down',
        'only ever adds',
      ]) {
        expect(app, contains(phrase));
        expect(doc, contains(phrase));
      }
    });

    test('does not let consent look like it gates the AI calls too', () {
      // It does not: the coach cannot answer without sending context. Leaving
      // that to be inferred from "backing up is optional" would be the most
      // likely way for a reader to be misled by this policy.
      expect(app, contains('do not use the coach'));
      expect(doc, contains('do not use the coach'));
    });

    test('promises the deletion path the app actually implements', () {
      expect(app, contains('delete'));
      expect(app, contains('Lift'));
      expect(doc, contains('Lift'));
      expect(app, contains('hello@mgkcodes.com'));
      expect(doc, contains('hello@mgkcodes.com'));
    });

    test('carries no unresolved draft placeholders', () {
      // `[region]`, `[N]` days, and friends must not reach a user.
      expect(
        app,
        isNot(matches(RegExp(r'\[[^\]]+\]'))),
        reason: 'the in-app policy still has a draft placeholder',
      );
    });
  });

  test('every document has a title and some content', () {
    for (final document in <LegalDocument>[medicalDisclaimer, privacyPolicy]) {
      expect(document.title, isNotEmpty);
      expect(document.allText, isNotEmpty);
      for (final line in document.allText) {
        expect(line.trim(), isNotEmpty);
      }
    }
  });

  /// The third rendering, and the only one App Review actually opens.
  ///
  /// Everything above pins `legal_copy.dart` against `docs/*.md`. The published
  /// page is generated from the same markdown by `tool/build_legal_pages.py`
  /// and served verbatim out of `web/public/run/`, so in principle it cannot
  /// drift. In practice **"generated" is a property of whether somebody ran the
  /// generator**, and the failure is silent: a doc edited without regenerating
  /// leaves a live page saying something the app does not, which is exactly the
  /// comparison a reviewer makes.
  ///
  /// This reads the bytes `web/next.config.ts` rewrites `/run/privacy` to, not
  /// a copy of them. Liftio's pages became 1,414 lines of hand-typed prose that
  /// nothing checked; this is the check that stops it happening twice.
  group('the published pages say what the app says', () {
    String readPublished(String name) {
      final file = File('../../web/public/run/$name');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'web/public/run/$name is missing. Run '
            '`python tool/build_legal_pages.py` from apps/mgk_run; the page is '
            'committed because Vercel builds from the repo and cannot run it.',
      );
      // Strip the generator's banner comment and its stylesheet before the
      // tags, or CSS property names end up in the compared text.
      final text = file
          .readAsStringSync()
          .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ')
          .replaceAll(RegExp(r'<style.*?</style>', dotAll: true), ' ')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll('&middot;', '·')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&amp;', '&');
      // Stripping an inline tag leaves a space where the markup was, so
      // `<em>estimates</em>,` normalises to `estimates ,` and stops matching a
      // sentence that is in fact present. Close the gap before punctuation
      // rather than loosening every phrase in the list to compensate.
      return _normalise(
        text,
      ).replaceAllMapped(RegExp(r'\s+([,.;:!?])'), (m) => m.group(1)!);
    }

    test('the medical disclaimer carries its load-bearing sentences', () {
      final page = readPublished('medical-disclaimer.html');
      for (final phrase in <String>[
        'It is not medical advice and is not a substitute for professional '
            'medical care.',
        'Consult a physician before starting any training programme',
        'cannot account for your full medical history',
        'Metrics such as calories and effort are estimates, not measurements.',
        'MGKCodes Ltd is not liable for injury',
      ]) {
        expect(
          page,
          contains(phrase),
          reason:
              'the published disclaimer no longer says: $phrase. Regenerate, '
              'or the page and the app disagree in front of a reviewer.',
        );
      }
    });

    test('the privacy policy names the same four sub-processors', () {
      final page = readPublished('privacy-policy.html');
      for (final processor in <String>[
        'Supabase',
        'OpenRouter',
        'RevenueCat',
        'MapTiler',
      ]) {
        expect(page, contains(processor));
      }
      expect(
        page,
        isNot(contains('Anthropic')),
        reason: 'the published page still names a dropped sub-processor',
      );
    });

    test('and makes the same claims about health data and the model', () {
      final page = readPublished('privacy-policy.html');
      for (final phrase in <String>[
        'special-category',
        'HealthKit',
        'never used for advertising',
        'last twenty messages',
        'as you wrote them',
        'never send raw GPS traces',
      ]) {
        expect(
          page,
          contains(phrase),
          reason: 'the published policy no longer says: $phrase',
        );
      }
      expect(
        page,
        isNot(contains('structured training context')),
        reason: 'the understated claim is back on the live page',
      );
    });

    test('neither page has been edited by hand', () {
      // The banner is the only thing distinguishing a generated file from one
      // somebody opened and fixed a typo in. Losing it is not itself a defect;
      // it is the signal that the file stopped being an artifact and became a
      // fourth copy.
      for (final name in <String>[
        'privacy-policy.html',
        'medical-disclaimer.html',
      ]) {
        final raw = File('../../web/public/run/$name').readAsStringSync();
        expect(
          raw,
          contains('GENERATED by tool/build_legal_pages.py'),
          reason: '$name lost its generated banner, so it was hand-edited',
        );
      }
    });
  });
}
