import '../../../core/brand.dart';
import 'legal_document.dart';

/// The in-app legal copy. **Mirrors `docs/`** — see [LegalDocument] for the
/// drift rule. Change the doc and this file together, in one commit.

/// `docs/medical-disclaimer.md`. Runio prescribes physical load, so this is
/// surfaced at onboarding *before anything is generated* (the gate in
/// `CoachFlow`) and stays reachable from the legal screen.
const LegalDocument medicalDisclaimer = LegalDocument(
  title: 'Medical disclaimer',
  lead:
      '$kProductName provides general fitness and training information and '
      'generates running training plans. It is not medical advice and is '
      'not a substitute for professional medical care.',
  sections: <LegalSection>[
    LegalSection(
      bullets: <String>[
        'Consult a physician before starting any training programme, '
            'especially if you have a heart condition, injury, are pregnant, '
            'or have any medical concern.',
        'Stop and seek medical attention if you experience chest pain, '
            'dizziness, shortness of breath, or any unusual pain during or '
            'after exercise.',
        'Training plans are generated from the information you provide and '
            'general principles. They cannot account for your full medical '
            'history and may not be appropriate for you.',
        'Metrics such as calories and effort are estimates, not measurements.',
        'You are responsible for training within your own limits and for your '
            'own safety.',
      ],
    ),
  ],
  footnote:
      'By using the app you acknowledge that you exercise at your own risk '
      'and that MGKCodes Ltd is not liable for injury or health issues '
      'arising from use of the app.',
);

/// `docs/privacy-policy.md`. Reachable from the legal screen, and required to be
/// linked in-app before submission (`docs/compliance.md`).
const LegalDocument privacyPolicy = LegalDocument(
  title: 'Privacy policy',
  lead:
      '$kProductName is a running coach. Your runs and plans live on your '
      'phone; backing them up to our servers is optional and off until you '
      'ask. To coach you it sends your training context, and what you say '
      'in the conversation, to an AI provider. We do not sell your data. '
      'You can delete everything at any time.',
  sections: <LegalSection>[
    LegalSection(
      heading: 'What we collect',
      bullets: <String>[
        'Account data — email / auth identifier.',
        'Profile data — date of birth, weight, unit preference, and running '
            'profile (current volume, longest run, available days, a recent '
            'race or time trial, optional injury notes).',
        'Activity data — runs you record or that sync from Apple Health: '
            'route points, distance, duration, pace, elevation, heart rate, '
            'cadence, and estimated calories.',
        'Training data — generated plans, sessions, check-ins, and RPE, '
            'including the plans you have finished with, so your coach knows '
            'what you have already tried.',
        'What you say to your coach — your messages, the coach’s replies, '
            'and a short rolling summary of what matters across conversations. '
            'This is free text you wrote, so it may contain anything you chose '
            'to tell it, including how you feel and where you hurt. Treat it as '
            'the most personal thing here, because it is.',
        'Usage records — for each AI request, which part of the coach it came '
            'from, how many tokens it used and what it cost. Needed to enforce '
            'fair-use limits and keep the service affordable; it holds no '
            'training or message content.',
      ],
      paragraphs: <String>[
        'We collect only what the coaching product needs (data minimisation).',
      ],
    ),
    LegalSection(
      heading: 'Health data',
      paragraphs: <String>[
        'Activity, heart-rate, and profile data are health data — '
            'special-category data under UK GDPR. We process it to provide the '
            'coaching service you request (the lawful basis is your consent, '
            'which you can withdraw by deleting your data).',
        'Apple HealthKit data is read (and written back as workouts) only with '
            'your explicit permission, and is used solely to power your '
            'training. HealthKit data is never used for advertising and is not '
            'shared with third parties for their own purposes.',
      ],
    ),
    LegalSection(
      heading: 'Who we share it with',
      bullets: <String>[
        'Supabase — hosts our database, authentication, and server functions.',
        'OpenRouter — routes our AI requests to the model provider that serves '
            'the model we have selected. Requests are made by our server, not '
            'your device, so the provider never sees your IP address or '
            'device. To generate or adapt a plan we send your training profile '
            'and the plan itself: goals, volumes, available days, session '
            'history, and your injury notes if you gave any. To hold a '
            'conversation we send a written summary of your training and up to '
            'your last twenty messages, as you wrote them — so if you told '
            'your coach about an injury, a symptom or how you are feeling, '
            'that text is sent. We never send your name, email, or account '
            'identifier, and we never send raw GPS traces. But we will not '
            'pretend the rest is anonymous: taken together it is health '
            'information about one person, and if you would rather it did not '
            'leave the app, do not use the coach.',
        'MapTiler — serves the basemap tiles behind your route; receives '
            'approximate map viewport coordinates.',
      ],
      paragraphs: <String>[
        'We do not sell personal data, and we do not use it for third-party '
            'advertising.',
      ],
    ),
    LegalSection(
      heading: 'Where data is stored',
      paragraphs: <String>[
        'Your runs, plans and conversations live on your device, which is the '
            'copy the app actually works from — it records, reads and plans '
            'with no network at all. Data in transit is encrypted with '
            'HTTPS/TLS.',
      ],
    ),
    LegalSection(
      heading: 'Backing up is optional, and off until you ask',
      paragraphs: <String>[
        'Nothing above leaves your phone for our servers unless you turn on '
            'Back up my data in Settings. It starts off. With it off, your '
            'phone is the only copy, and an uninstall loses everything — which '
            'is the trade we let you make rather than make for you, because '
            'this is health information.',
      ],
      bullets: <String>[
        'Your runs, routes, heart rate, plans and coach conversations are '
            'copied to our Supabase project in eu-west-1 (Ireland).',
        'Signing in on a new phone pulls them back down, so a lost or replaced '
            'device does not lose your training. The restore only ever adds — '
            'it will not overwrite anything already on the new phone.',
        'Turning it back off deletes what we have stored. Your phone keeps its '
            'own copy.',
      ],
    ),
    LegalSection(
      heading: 'Your rights',
      paragraphs: <String>[
        'Under UK GDPR you can access, correct, export, or delete your data, '
            'and withdraw consent. Turning off Back up my data withdraws '
            'consent to storing your data on our servers and deletes what is '
            'already there; your phone keeps its copy. Delete account removes '
            'every record we hold for you — runs, route points, splits, '
            'plans, sessions, your runner profile, your coach conversations and '
            'your usage records.',
        'Your login is your $kPlatformName profile, shared with '
            '$kPlatformName: Lift. If the profile holds no data from Lift, '
            'deletion removes the profile itself. If it does, we delete '
            'everything this app holds and keep only the profile, so your '
            'data in Lift survives — email hello@mgkcodes.com to remove the '
            'profile as well.',
      ],
    ),
    LegalSection(
      heading: 'Retention',
      paragraphs: <String>[
        'We keep your data while your account is active, and deletion removes '
            'it immediately, except where we must retain limited records to '
            'meet legal obligations. Two things expire on their own without you '
            'asking: usage records are pruned after 31 days, long enough for '
            'the monthly fair-use window and no longer; and coach '
            'conversations are kept so your coach remembers you between '
            'sessions, then pruned after 180 days, or sooner once there are '
            'more than 1,000 messages. The short rolling summary is what '
            'survives.',
      ],
    ),
    LegalSection(
      heading: 'Children',
      paragraphs: <String>[
        'The app is not directed at children under 16 and we do not knowingly '
            'collect their data.',
      ],
    ),
    LegalSection(
      heading: 'Contact',
      paragraphs: <String>['MGKCodes Ltd — hello@mgkcodes.com.'],
    ),
  ],
  footnote: 'Controller: MGKCodes Ltd. We note the date this policy changes.',
);
