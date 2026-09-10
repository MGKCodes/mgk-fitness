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
        'Account data — your email address and the account identifier it is '
            'keyed to. Only if you create an account; the app works without '
            'one.',
        'Profile data — your unit preference, and your running profile: '
            'current volume, longest run, available days, a recent race or '
            'time trial, and any injury notes you choose to give. We do not '
            'ask for your date of birth or your weight.',
        'Activity data — the runs you record, and any you add by hand: route '
            'points, distance, duration and pace. If you give Apple Health '
            'permission we also read your step count for the run. A heart rate '
            'is stored only if you type one in; we do not read heart rate from '
            'a watch or a chest strap.',
        'Training data — generated plans and sessions, whether each session '
            'was marked done or skipped, your rating of how hard it felt '
            '(RPE), and the plans you have finished with, so your coach knows '
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
        'Activity and profile data are health data — special-category data '
            'under UK GDPR. We process it to provide the coaching service you '
            'request (the lawful basis is your consent, which you can withdraw '
            'by deleting your data).',
        'Apple HealthKit data is read only with your explicit permission, and '
            'we never write anything to Health. We ask for two things: your '
            'workouts, which we read to show you how many Health has recorded '
            'and then discard without storing, and your step count for a run, '
            'which we do store alongside that run. HealthKit data is never '
            'used for advertising and is not shared with third parties for '
            'their own purposes.',
        'On Android the app requests no health permissions at all.',
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
            'identifier, and we never send raw GPS traces — with one honest '
            'qualification on the first of those: your messages go as you '
            'wrote them, so if you type your own name into the conversation, '
            'you have sent it. We do not add it. But we will not '
            'pretend the rest is anonymous: taken together it is health '
            'information about one person, and if you would rather it did not '
            'leave the app, do not use the coach. What we control, and what we '
            'do not: every request we make asks OpenRouter to route only to '
            'providers that do not keep or train on what we send. That setting '
            'is on for all of them, and it is the strongest control available '
            'to us. What we cannot do is audit the provider that ultimately '
            'serves a request, so treat that as a control we apply rather than '
            'a promise we can make for them. We will say so here if that ever '
            'changes.',
        'RevenueCat — handles subscription purchases and tells our server '
            'whether yours is active. We send it your account identifier and '
            'nothing else: no runs, no training data, and nothing you said to '
            'your coach. Like any purchase SDK it also collects technical '
            'information of its own about the install, such as a device-scoped '
            'identifier, your store country and your app version.',
        'MapTiler — serves the basemap tiles behind your route while you run; '
            'receives the map coordinates being displayed and, like any web '
            'request, your IP address. This happens whether or not you have an '
            'account.',
      ],
      paragraphs: <String>[
        'We do not sell personal data, and we do not use it for third-party '
            'advertising. The app contains no analytics, no advertising SDK '
            'and no crash reporter, and reads no advertising identifier.',
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
        'Nothing about your training leaves your phone for our servers unless '
            'you turn on Back up my data in Settings. It starts off. With it '
            'off, your phone is the only copy, and an uninstall loses '
            'everything — which is the trade we let you make rather than make '
            'for you, because this is health information.',
        'Two things are not covered by that switch, because they are what an '
            'account is rather than something it stores: your email address, '
            'which we need to sign you in, and your unit preference, which '
            'follows you to a new phone so the app opens in miles if that is '
            'how you left it. Both are written when you sign in and change, '
            'whatever the backup switch says. Neither is training data.',
      ],
      bullets: <String>[
        'Your runs, routes, plans and coach conversations are copied to our '
            'Supabase project in eu-west-1 (Ireland).',
        'Signing in on a new phone pulls them back down, so a lost or replaced '
            'device does not lose your training. The restore only ever adds — '
            'it will not overwrite anything already on the new phone.',
        'Turning it back off deletes your training data from our servers. Your '
            'phone keeps its own copy. Your account itself, and the usage '
            'records described under Retention, are not part of that — use '
            'Delete account for those.',
      ],
    ),
    LegalSection(
      heading: 'Sharing with our lifting app',
      paragraphs: <String>[
        'Our Supabase project is shared with our lifting app '
            '$kPlatformName: Lift, and one login serves both. Each app’s own '
            'data lives in its own area, separated per user by row-level '
            'security, and neither app can read the other’s.',
        'One thing does cross, and it is worth naming: when a run is backed '
            'up, a short summary of it — the date, how long it lasted, how far '
            'it went, and how hard it felt — is copied into a shared activity '
            'feed on your account, alongside your lifting sessions. It exists '
            'so that one app can show you a complete picture of a week’s '
            'training. It is readable only by you, holds no route and no '
            'conversation, and is deleted with the run it came from.',
      ],
    ),
    LegalSection(
      heading: 'Your rights',
      paragraphs: <String>[
        'Under UK GDPR you can access, correct, export, or delete your data, '
            'and withdraw consent. Turning off Back up my data withdraws '
            'consent to storing your training on our servers and deletes what '
            'is already there; your phone keeps its copy. Delete account '
            'removes every record this app holds for you — runs, route points, '
            'splits, plans, sessions, your runner profile, and your coach '
            'conversations and their summary.',
        'Two deliberate exceptions. Your usage records survive, because they '
            'are the meter that enforces fair-use limits and erasing them '
            'would let a deletion reset a spend cap; they hold no training '
            'data and nothing you wrote, and they are pruned after 31 days '
            'regardless. And your login survives if our lifting app still '
            'holds data on it.',
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
