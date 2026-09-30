import '../../../core/brand.dart';
import 'legal_document.dart';

/// The in-app legal copy. **Mirrors `docs/`** — see [LegalDocument] for the
/// drift rule. Change the doc and this file together, in one commit.

/// `docs/privacy-policy.md`. Reachable from Settings and from the sign-in
/// screen, and required to be linked in-app before submission.
const LegalDocument privacyPolicy = LegalDocument(
  title: 'Privacy policy',
  lead:
      '$kProductName is a strength-training log with an optional AI coach. '
      'Your sessions live on your phone and tracking works with no account at '
      'all. Signing in stores them on our servers. To coach you it sends '
      'your training '
      'context, and what you say in the conversation, to an AI provider. We do '
      'not sell your data. You can delete everything at any time.',
  sections: <LegalSection>[
    LegalSection(
      heading: 'What we collect',
      bullets: <String>[
        'Account data — your email address and an account identifier. If you '
            'sign in with Apple or Google, that is what they pass us too: an '
            'email address and an identifier, and nothing else. We do not ask '
            "either for your name or photograph. With Apple's Hide My Email, "
            'the address is one Apple forwards to yours, and we never see the '
            'real one.',
        'Training data — the sessions you log: exercise names, sets, reps, '
            'weight, set type, and for cardio work its duration and distance. '
            'Session and exercise notes are free text you wrote, so they hold '
            'whatever you chose to put there.',
        'Progress photos — the photos you take, the week and pose you filed '
            'them under, and any note against them. Part of the paid tier.',
        'Plan data — the answers you give when you ask for a plan: your goal, '
            'how many weeks and days a week you can train, which days those '
            'are, the equipment you have, and your injury notes if you gave '
            'any.',
        'What you say to your coach — your messages, the replies, and a short '
            'rolling summary of what matters across a conversation. This is '
            'free text you wrote, so it may contain anything you chose to tell '
            'it, including how you feel and where you hurt. Treat it as the '
            'most personal thing here, because it is.',
        'Usage records — for each AI request, which part of the coach it came '
            'from, how many tokens it used and what it cost. Needed to enforce '
            'fair-use limits and keep the service affordable; it holds no '
            'training or message content.',
        'Subscription status — if you subscribe: which tier you hold, whether '
            "it is active, and the store's record of the purchase (the "
            "product, its dates and the store's transaction identifier). It "
            'reaches us from RevenueCat, below. We never see your card or '
            'payment details.',
      ],
      paragraphs: <String>[
        'We collect only what the training product needs (data minimisation).',
      ],
    ),
    LegalSection(
      heading: 'Health data',
      paragraphs: <String>[
        'Your training, your injury notes, and what you tell your coach about '
            'your body are health data — special-category data under UK GDPR. '
            'We process it to provide the logging and coaching service you '
            'request (the lawful basis is your consent, which you can withdraw '
            'by deleting your data).',
      ],
    ),
    LegalSection(
      heading: 'Who we share it with',
      bullets: <String>[
        'Supabase — hosts our database, authentication, and server functions.',
        'Apple and Google — only if you sign in with them. They confirm who '
            'you are and pass us an email address and an identifier; we tell '
            'them nothing about your training. On an iPhone, deleting an '
            'account made with Apple asks Apple to confirm first, so that when '
            "the login goes we can also end the app's access to your Apple ID.",
        'OpenRouter — routes our AI requests to the model provider that serves '
            'the model we have selected. Requests are made by our server, not '
            'your device, so the provider never sees your IP address or '
            'device. To build or adapt a plan we send your plan answers: goal, '
            'weeks, days available, equipment, and your injury notes if you '
            'gave any. To hold a conversation we send a written summary of '
            'your recent training and the messages in that conversation, as '
            'you wrote them — so if you told your coach about an injury, a '
            'symptom or how you are feeling, that text is sent. We never send '
            'your name, email, or account identifier, and we never send your '
            'progress photos. But we will not pretend the rest is anonymous: '
            'taken together it is health information about one person, and if '
            'you would rather it did not leave the app, turn the coach off in '
            'Settings or do not use it.',
        'RevenueCat — handles subscription purchases on the App Store and '
            'Google Play, and tells our server whether yours is active. We '
            'send it your account identifier and nothing else: no training, no '
            'photos, and nothing you said to your coach. Like any purchase SDK '
            'it also collects technical information of its own about the '
            'install, such as a device-scoped identifier, your store country '
            'and your app version.',
        'SMTP2GO — sends the emails your account needs: the link to confirm '
            'your address when you sign up, the link to reset your password, '
            'and a note when your password changes. It receives your email '
            'address and the email itself, through its servers in the EU, and '
            'nothing about your training. Its open and click tracking are '
            'turned off.',
      ],
      paragraphs: <String>[
        'We do not sell personal data, and we do not use it for third-party '
            'advertising.',
      ],
    ),
    LegalSection(
      heading: 'The coach is optional and can be turned off',
      paragraphs: <String>[
        'The coach is the only part of the app that sends anything to an AI '
            'provider. Turning off Use the AI coach in Settings stops that '
            'entirely: no message, no training summary and no plan answer '
            'leaves the app for OpenRouter. Logging, plans you already have, '
            'photos and syncing all keep working. Nothing you have already '
            'said is un-sent by turning it off, but you can erase what the '
            'coach remembers from the same screen.',
      ],
    ),
    LegalSection(
      heading: 'Progress photos',
      paragraphs: <String>[
        'Progress photos are part of the paid tier. They are stored on your '
            'phone and copied to a private storage bucket in our Supabase '
            'project, where only your account can read them.',
        'They are never sent to the coach or to any AI provider. That is the '
            'one promise on this page we would have to change code to break, '
            'and it is the reason the photos and the coach are kept apart in '
            'the first place.',
        'Deleting a photo removes it from both, immediately. If your '
            'subscription ends the photos you already have stay, and you can '
            'still look at them and delete them; only taking new ones stops. '
            'Delete account removes them from our servers along with '
            'everything else, the picture files included.',
      ],
    ),
    LegalSection(
      heading: 'Where data is stored',
      paragraphs: <String>[
        'Your sessions live on your device, which is the copy the app actually '
            'works from — it logs, reads and plans with no network at all. '
            'Signing in copies your sessions to our Supabase project in '
            'eu-west-1 (Ireland). Data in transit is encrypted with HTTPS/TLS.',
      ],
    ),
    LegalSection(
      heading: 'Your account',
      paragraphs: <String>[
        'You do not need an account to track your training, and with no '
            'account nothing leaves your phone at all. Signing in stores your '
            'sessions on our servers under your $kPlatformName account, which '
            'is the same account $kPlatformName: Run uses. There is no '
            'separate switch — signing in is the switch.',
        'You can sign in with Apple, with Google, or with an email address '
            'and a password. Choosing Hide My Email with Apple starts a '
            'separate account, because the address Apple gives us is not one '
            'any other account uses.',
      ],
    ),
    LegalSection(
      heading: 'Your rights',
      paragraphs: <String>[
        'Under UK GDPR you can access, correct, export, or delete your data, '
            'and withdraw consent. Delete account removes every record we hold '
            'for you — your sessions, exercises and sets, your plans, your '
            'coach conversations and your usage records. Your phone keeps its '
            'own copy until you uninstall.',
        'Deletion asks how much, because your login is your $kPlatformName '
            'account and it is shared with $kPlatformName: Run. Delete this '
            'app only, and we erase everything this app holds; your account '
            'survives so Run keeps working. Delete your whole account, and '
            'everything Run holds goes too, along with the login itself.',
        'One thing the narrow choice cannot promise: if Run holds no data, '
            'there is nothing left for the account to be for, so it is removed '
            'as well. We tell you which happened rather than leaving you to '
            'find out.',
      ],
    ),
    LegalSection(
      heading: 'Retention',
      paragraphs: <String>[
        'We keep your data while your account is active, and deletion removes '
            'it immediately, except where we must retain limited records to '
            'meet legal obligations. Two things expire on their own without '
            'you asking: usage records are pruned after 31 days, long enough '
            'for the monthly fair-use window and no longer; and coach '
            'conversations are kept so your coach remembers you between '
            'sessions, then pruned after 180 days. The short rolling summary '
            'is what survives.',
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

/// `docs/terms-of-use.md`. Required to be linked wherever an account can be
/// created, which is why the sign-in screen carries it as well as Settings.
const LegalDocument termsOfUse = LegalDocument(
  title: 'Terms of use',
  lead:
      '$kProductName is a strength-training log with an optional AI coach, '
      'provided by MGKCodes Ltd. Using the app means you accept these terms. '
      'If you do not accept them, do not use the app.',
  sections: <LegalSection>[
    LegalSection(
      heading: 'Not medical advice',
      paragraphs: <String>[
        'The app provides general fitness information and generates '
            'strength-training plans. It is not medical advice and is not a '
            'substitute for professional medical care.',
      ],
      bullets: <String>[
        'Consult a physician before starting any training programme, '
            'especially if you have a heart condition, injury, are pregnant, '
            'or have any medical concern.',
        'Stop and seek medical attention if you experience chest pain, '
            'dizziness, shortness of breath, or any unusual pain during or '
            'after exercise.',
        'Plans are generated from the information you provide and general '
            'principles. They cannot account for your full medical history and '
            'may not be appropriate for you.',
        'Loads, volumes and estimates shown in the app are guidance, not '
            'measurements.',
        'You are responsible for training within your own limits and for your '
            'own safety.',
      ],
    ),
    LegalSection(
      paragraphs: <String>[
        'By using the app you acknowledge that you exercise at your own risk '
            'and that MGKCodes Ltd is not liable for injury or health issues '
            'arising from use of the app.',
      ],
    ),
    LegalSection(
      heading: 'The coach is a language model',
      paragraphs: <String>[
        'The coach is powered by a third-party AI model and can be wrong. It '
            'may misremember, invent detail, or give advice that does not suit '
            'you. Treat it as a knowledgeable training partner rather than an '
            'authority, and do not rely on it for anything medical.',
      ],
    ),
    LegalSection(
      heading: 'Your account',
      paragraphs: <String>[
        'You do not need an account to track your training. If you make one, '
            'you are responsible for keeping your password secret and for what '
            'happens under your account. Tell us at hello@mgkcodes.com if you '
            'think someone else has access to it. You must be 16 or over to '
            'create an account.',
      ],
    ),
    LegalSection(
      heading: 'Acceptable use',
      paragraphs: <String>[
        'Do not use the app to break the law, to harass anyone, to attack or '
            'overload our servers, or to extract our content in bulk. Do not '
            'attempt to use the coach to generate content that is illegal or '
            'that we would be obliged to remove. We can suspend an account '
            'that does these things.',
      ],
    ),
    LegalSection(
      heading: 'Subscriptions',
      paragraphs: <String>[
        'The coach, training plans and progress photos are sold as an '
            'auto-renewing subscription, in two tiers, Coach and Premium '
            'Coach, described in the app at the point of purchase. Tracking, '
            'saved workouts, history and stats are free and stay free.',
      ],
      bullets: <String>[
        'The price you pay is the one your store shows you, in your own '
            'currency, at the time of purchase. Prices may change; a change '
            'never applies to a period you have already paid for, and your '
            'store will tell you before a renewal at a new price.',
        'Payment is charged to your Apple ID or Google Play account at '
            'confirmation of purchase. The store takes the payment, not us, '
            'and we never see your card details.',
        'Your subscription automatically renews each month unless auto-renew '
            'is turned off at least 24 hours before the end of the current '
            'period. Your account is charged for renewal within 24 hours '
            'before the end of the current period.',
        'Manage or cancel it through your store, not through us: App Store '
            'subscriptions in your Apple ID settings, Play subscriptions in the '
            'Google Play app under Payments and subscriptions. We cannot cancel '
            'a subscription for you, because we are not the party taking the '
            'money.',
        'Cancelling stops the next renewal. It does not end the period you '
            'have paid for, and you keep the paid features until that period '
            'runs out.',
      ],
    ),
    LegalSection(
      paragraphs: <String>[
        'The coach costs us money for every answer, so each tier carries '
            'fair-use limits on how much it will talk, set well above what '
            'somebody training seriously would use. Premium Coach holds the '
            'same features as Coach, with far more room to talk.',
        "Refunds are the store's decision, not ours. Apple and Google each run "
            'their own refund process and their own rules, and we cannot '
            'issue, refuse or speed up a refund. If something we did caused '
            'the problem, email hello@mgkcodes.com and we will help you make '
            'the case.',
        'If a subscription lapses, your training stays on your device and in '
            'your account, and so do the progress photos you already took. '
            'Nothing is deleted because you stopped paying: you lose access to '
            'the coach, your plan and taking new photos, not your training.',
      ],
    ),
    LegalSection(
      heading: 'Your content, and ours',
      paragraphs: <String>[
        'Your training, notes, photos and messages are yours. You give us only '
            'the permission we need to run the service for you — to store your '
            'data, sync it between your devices, and send what the privacy '
            'policy describes to our AI provider so the coach can answer.',
        'The app itself, its design and its content are ours or our '
            'licensors. The exercise illustrations and typeface are used under '
            'their own licences, listed in the app under Settings, Credits.',
      ],
    ),
    LegalSection(
      heading: 'Ending it',
      paragraphs: <String>[
        'You can stop using the app at any time and delete your account from '
            'within it. We can end your access if you break these terms, or if '
            'we stop offering the app — in which case we will give you what '
            'notice we reasonably can so you can export or keep your training.',
      ],
    ),
    LegalSection(
      heading: 'Liability',
      paragraphs: <String>[
        'Nothing here limits liability for death or personal injury caused by '
            'our negligence, for fraud, or anything else that cannot be '
            'limited by law. Subject to that, the app is provided as-is: we do '
            'not promise it will be uninterrupted or error-free, and we are '
            'not liable for indirect or consequential loss, or for loss of '
            'data where you had the means to back it up and did not.',
      ],
    ),
    LegalSection(
      heading: 'Changes',
      paragraphs: <String>[
        'We may change these terms. If a change matters we will say so in the '
            'app before it takes effect, and the date above will change.',
      ],
    ),
    LegalSection(
      heading: 'Governing law',
      paragraphs: <String>[
        'These terms are governed by the law of England and Wales, and the '
            'courts of England and Wales have exclusive jurisdiction. If you '
            'are a consumer, this does not take away rights you have under the '
            'law of the country you live in.',
      ],
    ),
    LegalSection(
      heading: 'Contact',
      paragraphs: <String>['MGKCodes Ltd — hello@mgkcodes.com.'],
    ),
  ],
  footnote: 'Provider: MGKCodes Ltd. We note the date these terms change.',
);

/// `docs/ai-disclosure.md`. Guideline 5.1.2(i): a person has to know their data
/// is going to a third-party AI service before it goes. Reachable from the
/// coach itself, not only from Settings, because the point of use is where a
/// disclosure has to be to be one.
const LegalDocument aiDisclosure = LegalDocument(
  title: 'How your coach uses AI',
  lead:
      'Your coach is a large language model, not a person and not something we '
      'wrote. We send your request to OpenRouter, which routes it to the '
      'provider that serves the model we have selected, and that provider '
      'generates the reply.',
  sections: <LegalSection>[
    LegalSection(
      paragraphs: <String>[
        'The request is made by our server, not by your phone. The provider '
            'never sees your IP address, your device, your name, your email or '
            'your account identifier.',
      ],
    ),
    LegalSection(
      heading: 'What we send',
      bullets: <String>[
        'The messages in the conversation, as you wrote them.',
        'A short written summary of your recent training — the sessions you '
            'logged, what you lifted, and how much.',
        'When you ask for a plan: your goal, how many weeks and days a week '
            'you can train, which days those are, the equipment you have, and '
            'your injury notes if you gave any.',
      ],
    ),
    LegalSection(
      heading: 'What we never send',
      bullets: <String>[
        'Your name, email address, or account identifier.',
        'Your progress photos.',
        'Any part of the app you use without the coach — logging a session '
            'sends nothing.',
      ],
    ),
    LegalSection(
      heading: 'Say it plainly',
      paragraphs: <String>[
        'Your messages are free text. If you tell your coach about an injury, '
            'a symptom, your weight or how you are feeling, that text is sent '
            'to a third-party AI provider. We do not send anything that names '
            'you, but we will not pretend the rest is anonymous: taken '
            'together it is health information about one person.',
      ],
    ),
    LegalSection(
      heading: 'Turning it off',
      paragraphs: <String>[
        'Use the AI coach in Settings turns this off completely. With it off, '
            'nothing in this document happens — no message, no training '
            'summary and no plan answer leaves the app for OpenRouter. '
            'Logging, plans you already have, your photos and syncing all '
            'keep working.',
        'Turning it off does not un-send what you have already said. You can '
            'erase what the coach remembers under Settings, Coach, and Delete '
            'account removes your conversations along with everything else.',
      ],
    ),
    LegalSection(
      heading: 'How long it is kept',
      paragraphs: <String>[
        'Coach conversations are kept so your coach remembers you between '
            'sessions, then pruned after 180 days. The short rolling summary '
            'is what survives. Usage records — which part of the coach a '
            'request came from, its tokens and its cost, with no message '
            'content — are pruned after 31 days.',
      ],
    ),
    LegalSection(
      heading: 'Contact',
      paragraphs: <String>['MGKCodes Ltd — hello@mgkcodes.com.'],
    ),
  ],
);
