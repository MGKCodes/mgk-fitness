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
        'Turning it back off deletes your training data from our servers',
      ]) {
        expect(app, contains(phrase));
        expect(doc, contains(phrase));
      }
    });

    test('does not claim to collect what it has never asked for', () {
      // The 2026-09-10 audit found this policy over-declaring in three places,
      // which is the less obvious direction and still wrong: a form filled from
      // an over-declaring policy is a false declaration, and on Apple's labels
      // it drags the app into a stricter review bracket for nothing.
      //
      // Date of birth and weight are Liftio's columns and this app has never
      // asked for either. Cadence and estimated calories have columns that are
      // never written. Elevation is deliberately absent until there is a
      // barometric source (ADR-0024), so a trace records none.
      for (final text in <String>[doc, app]) {
        expect(text, isNot(contains('date of birth, weight')));
        expect(text, isNot(contains('cadence')));
        expect(text, isNot(contains('estimated calories')));
      }
    });

    test('does not describe a HealthKit write that never happens', () {
      // `kHealthReadAccess` is READ throughout. The purpose string in
      // Info.plist survives only because Apple's static SDK scan rejects the
      // upload without it (error 90683) — it is never shown, because write
      // authorisation is never requested. The policy said otherwise.
      for (final text in <String>[doc, app]) {
        expect(text, isNot(contains('written back as workouts')));
        expect(text, contains('never write anything to Health'));
      }
    });

    test('discloses the two things backup consent does not gate', () {
      // An email is what an account IS, and a unit preference has to follow
      // the runner to a new phone for the account to be worth having. Both are
      // written whatever the switch says, so "nothing leaves your phone" was
      // false as an unqualified claim. Narrowed to training, and the carve-out
      // is stated rather than left to be discovered.
      for (final text in <String>[doc, app]) {
        expect(text, contains('Nothing about your training'));
        expect(text, contains('unit preference'));
      }
    });

    test('discloses the shared cross-app activity feed', () {
      // `core.sync_activity_from_run` copies a run summary into a feed shared
      // with Lift. Small, RLS-scoped and cascade-deleted — but undisclosed,
      // while the policy said each app's data lives in its own area.
      for (final text in <String>[doc, app]) {
        expect(text, contains('shared activity feed'));
      }
    });

    test('is honest that usage records survive a deletion', () {
      // They do, by design: they are the spend ledger, and erasing them would
      // let a deletion reset a rate limit. The policy previously listed them
      // among what Delete account removes — which became false the moment the
      // client started asking for an app-scoped deletion.
      for (final text in <String>[doc, app]) {
        expect(text, contains('usage records survive'));
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

    test('says the coach asks first, and where that is taken back', () {
      // App Store 5.1.2(i) and the Art. 9 basis this policy names: permission
      // before anything reaches a third-party AI, and a way to withdraw it
      // that is not deleting the account.
      for (final text in <String>[doc, app]) {
        expect(text, contains('asks your permission'));
        expect(text, contains('Settings › Privacy & legal'));
        expect(text, contains('explicit consent'));
      }
    });

    test('names the older messages the coach recalls, not only the last '
        'twenty', () {
      // `recollectionsFrom` adds up to four of the runner's own past turns to
      // the brief when they match what is being asked. "Up to your last
      // twenty messages" alone understated what a conversation sends.
      for (final text in <String>[doc, app]) {
        expect(text, contains('up to four older messages'));
      }
    });

    test('says the coach sends whether or not backup is on, in both', () {
      // The doc said so and the app did not. In the app the backup section
      // ended on "Nothing about your training leaves your phone for our
      // servers unless you turn on Back up my data", which reads as covering
      // the coach too; its requests go through our server either way.
      for (final text in <String>[doc, app]) {
        expect(text, contains('happen either way'));
        expect(text, contains('whether or not backup is on'));
      }
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

  /// **The list of what is collected, pinned across all three renderings.**
  ///
  /// Every test above pins a *claim* — the sub-processors, the lawful basis,
  /// what never leaves. None of them pinned the list itself, and that is the
  /// gap two separate drifts went through in one day:
  ///
  ///   * `c3d7df8`, whose entire subject was "the policy did not mention the
  ///     name it collects", edited `docs/privacy-policy.md` and the generated
  ///     page and **never touched `legal_copy.dart`**. The app went on
  ///     under-disclosing while the commit message said it had been fixed.
  ///   * The profile photo, the same day, the same way.
  ///
  /// Both shipped. Build 25 reached TestFlight and Play internal testing with
  /// an in-app policy that omitted two categories of data the published one
  /// declared — which is exactly the comparison a reviewer makes, and exactly
  /// what this file says at the top it exists to prevent.
  ///
  /// So the list is the thing pinned now, in all three places at once: the
  /// bundled copy the app renders, the markdown that is the source, and the
  /// bytes served at /run/privacy. Adding a category to one and not the others
  /// fails here.
  group('what we collect says the same thing in all three renderings', () {
    /// One phrase per category, chosen to be specific enough that a rewrite
    /// which drops the category fails, and loose enough that rewording the
    /// sentence around it does not.
    const categories = <String, String>{
      'the email address': 'email address',
      'the name given to the coach': 'name you give the coach',
      'the profile photo': 'profile photo',
      'the running profile': 'running profile',
      'the runs themselves': 'route points',
      'the training plan': 'generated plans',
      'the coach conversation': 'what you say to your coach',
      'a reported coach reply': 'if you report one of the coach',
      'the note written on a run': 'any note you write on a run',
      'the usage meter': 'how many tokens',
    };

    /// Lower case with runs of whitespace collapsed.
    ///
    /// The markdown wraps at 80 columns and the generated HTML keeps those
    /// newlines, so a phrase like "route points" is split across a line in two
    /// of the three sources and matches in none of them without this. The
    /// first version of this group failed on exactly that and it was the
    /// comparison at fault, not the policy.
    String flat(String text) =>
        text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    String appCopy() {
      final section = privacyPolicy.sections.firstWhere(
        (s) => s.heading == 'What we collect',
      );
      return flat(section.bullets.join(' '));
    }

    String markdown() =>
        flat(File('docs/privacy-policy.md').readAsStringSync());

    categories.forEach((name, phrase) {
      test('$name is declared in the app, the doc and the page', () {
        final needle = flat(phrase);
        expect(
          appCopy(),
          contains(needle),
          reason:
              'legal_copy.dart no longer declares $name. This is the copy the '
              'app renders, and under-disclosing here while the published page '
              'declares it is the drift this group exists for.',
        );
        expect(
          markdown(),
          contains(needle),
          reason: 'docs/privacy-policy.md no longer declares $name',
        );
        // The served bytes, read here rather than through the helper in the
        // group below -- this check is about the same list in three places,
        // and it should not depend on that group's order.
        final page = flat(
          File('../../web/public/run/privacy-policy.html').readAsStringSync(),
        );
        expect(
          page,
          contains(needle),
          reason:
              'the published page no longer declares $name. If the markdown '
              'has it, run `python tool/build_legal_pages.py`.',
        );
      });
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

    test('no page says not to publish it while it is published', () {
      // The generator printed "DO NOT PUBLISH until: the publication date"
      // into every page for three weeks after the policy was dated, because
      // the blocker outlived the token it named. It prints nothing now unless
      // something is on the list.
      for (final name in <String>[
        'privacy-policy.html',
        'medical-disclaimer.html',
        'terms-of-use.html',
      ]) {
        final raw = File('../../web/public/run/$name').readAsStringSync();
        expect(raw, isNot(contains('DO NOT PUBLISH')), reason: name);
      }
    });

    test('and the page makes the claims tonight added', () {
      final page = readPublished('privacy-policy.html');
      for (final phrase in <String>[
        'asks your permission',
        'up to four older messages',
        'if you report one of the coach',
      ]) {
        expect(page, contains(phrase), reason: 'the page lacks: $phrase');
      }
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
