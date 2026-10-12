import { stores } from "./links";
import type { Key } from "./storyboard";

/**
 * What the site says, in one place, so the film on the home page and each
 * app's own page say the same thing.
 *
 * Every line here is one the store listings or the support pages already make
 * (`apps/mgk_run/docs/app-store-listing.md`, `apps/mgk_lift/docs/store-listing.md`,
 * `(pages)/run/support`, `(pages)/lift/support`, the delete-account pages and
 * Lift's AI disclosure), and each thing an app does says whether it is free or
 * the subscription, as the listings must. **No prices**: the listings print
 * none ("shown in the app, in your own currency"), and the stores set them per
 * country, so a figure here would be wrong somewhere. Run's listing has a list
 * of what it may not claim (no heart rate, no watch, no audio cues, no
 * elevation, nothing written to Health); nothing here does.
 */

export type App = "run" | "lift";

/** One thing an app does: what it costs, two lines about it, and the screen. */
export type Step = { tag: string; lines: [string, string]; screen: string; alt: string };

export const steps: Record<App, Step[]> = {
  run: [
    {
      tag: "Free",
      lines: ["Track every run.", "Free. No account."],
      screen: "run-record",
      alt: "Run recording a run: the route drawn on a map, 4.28 km, the time and the pace.",
    },
    {
      tag: "Coach · Subscription",
      lines: ["A real plan,", "adjusted weekly."],
      screen: "run-plan",
      alt: "Run's plan for a marathon: this week's sessions, day by day.",
    },
    {
      tag: "AI coach · Subscription",
      lines: ["Ask the coach", "about any run."],
      screen: "run-coach",
      alt: "Run's coach answering what a half marathon could be run in.",
    },
  ],
  lift: [
    {
      tag: "Free",
      lines: ["Log a set in one tap.", "Last time’s numbers already in."],
      screen: "lift-log",
      alt: "Lift during a session: sets of bench press ticked off, the next one filled in.",
    },
    {
      tag: "Free",
      lines: ["A rest timer that buzzes", "with your phone locked."],
      screen: "lift-rest",
      alt: "Lift between sets: a rest timer counting down from 1:30.",
    },
    {
      tag: "Coach · Subscription",
      lines: ["A plan built around your goal", "and the days you can train."],
      screen: "lift-plan",
      alt: "Lift's plan: an upper and lower split across the week, with today's movements.",
    },
  ],
};

/** Each app in a line, and what it is called on its own page. */
export const apps: Record<App, { name: string; what: string }> = {
  run: { name: "Run", what: "A running tracker and training coach." },
  lift: { name: "Lift", what: "A strength log with a coach of its own." },
};

/** A screen as an app's page shows it, and what it does if the page says. */
export type Screen = { src: string; alt: string };
export type Feature = Screen & { tag: string; lines: [string, string]; more: string };

/**
 * Each app's own page, made from the six screens its store pictures are made
 * from (Run's `test/plates/store.dart`, Lift's `tool/capture_store_screens.mjs`,
 * copied into `public/screens/store/`), all drawn at one clock: one in the
 * head, four with their words, and the coach's beside the case for it. The two
 * lines on each are the store pictures' own (`design/store-shots/src/shots.ts`
 * in each app) and the sentence under them is the listing's. `still` and
 * `interlude.still` are the film's own stills (`public/film/`), so the
 * pages stand in the places the film goes: Run on the track and above it,
 * Lift in the weight room and the tunnel to it.
 */
export const pages: Record<
  App,
  { time: string; still: Key; head: Screen; features: Feature[]; coach: Screen; interlude: { still: Key; line: [string, string] } }
> = {
  run: {
    time: "09:41",
    still: "k2",
    head: {
      src: "/screens/store/run/1-home.png",
      alt: "Run's home screen in the morning: today's session, 5 km slower than feels natural, ready to start, with this week's sessions and the last run.",
    },
    features: [
      {
        tag: "Free",
        lines: ["Track every run.", "No account needed."],
        more: "Press start and it tracks your route, your splits and your pace. It keeps recording with the screen locked and the phone in a pocket, and without a signal.",
        src: "/screens/store/run/2-run.png",
        alt: "Run recording a run: the route on a map, 4.28 km, 26:30 and a pace of 6:06 per km.",
      },
      {
        tag: "Free",
        lines: ["Every run, kept", "on your phone."],
        more: "The run is written to your phone as it happens, not to a server: its route, its splits and your pace. Treadmill and manual entry cover the runs your phone did not see.",
        src: "/screens/store/run/3-finished.png",
        alt: "A finished run: 6.13 km in 37:42 at 6:09 per km, its route on the map, and its splits.",
      },
      {
        tag: "Coach · Subscription",
        lines: ["A real plan,", "adjusted weekly."],
        more: "Sessions arrive about a week ahead, so the plan reflects the running you actually did. When life gets in the way, say so: the week bends around it, and nothing changes until you say yes.",
        src: "/screens/store/run/4-plan.png",
        alt: "Run's plan for a marathon: this week's sessions from Monday to Sunday, with today's recovery run.",
      },
      {
        tag: "Free",
        lines: ["Your year,", "at a glance."],
        more: "Your whole log: every run, its route, its splits, your records, and your year at a glance. Kilometres or miles, your choice.",
        src: "/screens/store/run/6-year.png",
        alt: "Run's profile: the longest run and fastest pace, typical times, the year as a grid of days run, and the goal.",
      },
    ],
    coach: {
      src: "/screens/store/run/5-coach.png",
      alt: "Run's coach, asked what a half marathon could be run in, answering from a recent 5k.",
    },
    interlude: {
      still: "k1",
      line: ["No feed, no followers, no leaderboards, no kudos.", "It is a training tool, not a social network."],
    },
  },
  lift: {
    time: "18:41",
    still: "k5",
    head: {
      src: "/screens/store/lift/track-planned.png",
      alt: "Lift's home in the evening: today's upper session ready to start, with this week's sessions and the last one.",
    },
    features: [
      {
        tag: "Free",
        lines: ["Log a set in one tap.", "Last time’s numbers already in."],
        more: "Tick a set and the rest timer starts. It buzzes when rest is over, even with your phone locked, and counts on past zero so you know how long you actually rested.",
        src: "/screens/store/lift/session-resting.png",
        alt: "Lift during a push session: sets of bench press ticked off, and the rest timer counting down from 1:30.",
      },
      {
        tag: "Free",
        lines: ["Every session,", "kept on your phone."],
        more: "Every set is saved on your phone the moment you tick it, with no signal needed. Every session is there to open, fix or delete, grouped by week.",
        src: "/screens/store/lift/session-summary-pb.png",
        alt: "A finished push session: 2345 kg in 58 minutes, what was lifted, and a new best on the bench press.",
      },
      {
        tag: "Coach · Subscription",
        lines: ["A plan built", "around your week."],
        more: "A training plan built around your goal and the days you can train, which adjusts as you go.",
        src: "/screens/store/lift/plan-standing.png",
        alt: "Lift's upper and lower plan: the week's days, and today's movements with last time's numbers.",
      },
      {
        tag: "Free",
        lines: ["Your training,", "at a glance."],
        more: "Your saved workouts, your history and your stats. Save a session as a workout and start it again with every set laid out.",
        src: "/screens/store/lift/profile.png",
        alt: "Lift's profile: lifetime tonnage, sessions and streak, records, the most trained movements and the year.",
      },
    ],
    coach: {
      src: "/screens/store/lift/coach-resumed.png",
      alt: "Lift's coach explaining why a bench press has stalled, and keeping a sore shoulder in mind.",
    },
    interlude: {
      still: "k4",
      line: ["Built for the minute", "between sets."],
    },
  },
};

// Why somebody would pay for the coach: what goes wrong without one, and what
// the coach does about it. The answer is never bigger than the listings, and
// nothing here promises a result.
export const reasons: [string, string][] = [
  [
    "A plan off the internet was written for somebody else.",
    "Yours is built around your goal and the days you can train.",
  ],
  [
    "One missed week and the plan no longer fits.",
    "It is adjusted every week, around what you actually did.",
  ],
  [
    "Nobody to ask whether today still makes sense.",
    "Ask the coach. It reads what you have logged, so the answer is about you.",
  ],
  [
    "You open the app and have to work out what to do.",
    "Today’s session is already there, ready to start.",
  ],
];

/**
 * What the free half and the coach hold, per app. The Premium Coach lines are
 * each listing's own words: Run's answers with a better model, Lift's has more
 * room to talk.
 */
export const terms: Record<App, { free: string[]; coach: string[]; premium: string }> = {
  run: {
    free: [
      "Track every run, with no account.",
      "Records without a signal, and keeps going with the screen locked.",
      "Splits and pace, treadmill and manual runs.",
      "Every run kept on your phone, with your records and your year at a glance.",
    ],
    coach: [
      "Know what to run today.",
      "A real plan, adjusted weekly, with sessions set about a week ahead.",
      "Each run read against its session.",
      "Ask the coach about any run.",
    ],
    premium: "Premium Coach answers with a better AI model and has a bigger monthly allowance.",
  },
  lift: {
    free: [
      "Log a set in one tap, with last time’s numbers already in.",
      "A rest timer that buzzes with your phone locked.",
      "Your saved workouts, your history and your stats.",
      "Works with no signal, and needs no account.",
    ],
    coach: [
      "A training plan built around your goal and the days you can train.",
      "A coach you can talk to about your training. It reads your log.",
      "Progress photos, one a week per pose.",
    ],
    premium: "Coach and Premium Coach hold the same features; Premium Coach gives the coach far more room to talk.",
  },
};

// What makes the two apps one suite, each as something that is true of them.
// The last is marked as coming because it is not built: `core.activities`
// holds every run and workout so that each app *can* show the other's, and
// neither app reads it yet.
export const facts: [string, string, boolean?][] = [
  ["One account", "The account you make in Run is your account in Lift. Sign in to either with it."],
  ["One design", "Both are built from the same parts, so the second app already feels like the first."],
  ["Free to track", "Recording a run and logging a workout are free in both, with no account needed to start."],
  ["One history", "Your runs in Lift and your lifting in Run, at no extra cost. It is what the suite is for.", true],
];

/** A question and its answer, with where to read more if there is somewhere. */
export type Question = { q: string; a: string; more?: { label: string; href: string } };

const where = (app: App) => {
  const links = stores[app];
  if (links.apple && links.google) return "iPhone and Android.";
  if (links.google) return "Android now, and iPhone as soon as the App Store approves it.";
  return "iPhone now, and Android soon.";
};

export const questions: Record<App, Question[]> = {
  run: [
    {
      q: "Do I need an account?",
      a: "Not to record. Tracking a run needs no account and no sign-up. The coach does, because it lives on our server and has to follow you to a new phone. You can sign in with Apple, Google or email.",
    },
    {
      q: "Does it work without a signal?",
      a: "Yes. Run records without a signal and keeps recording with the screen locked. Every run is written to your phone, not a server. It needs your location while you use it, with precise location on.",
      more: { label: "Setting up location", href: "/run/support" },
    },
    {
      q: "What is free?",
      a: "Recording with GPS and a live map, splits and pace, treadmill and manual runs, and your whole log with your records and your year at a glance. That half is free, and always will be.",
    },
    {
      q: "What does the subscription add?",
      a: "The coach. A plan shaped around your goal, sessions set about a week ahead, each run read against its session, and a coach you can talk to. When your week changes it suggests how the plan should bend, and nothing changes until you say yes. Premium Coach answers with a better AI model and has a bigger monthly allowance.",
    },
    {
      q: "How much is it?",
      a: "The price is shown in the app and in your store, in your own currency. Run has its own subscription, separate from Lift's, and tracking stays free either way.",
    },
    {
      q: "Is the coach a person? What does it see?",
      a: "It is an AI model, and it asks before it sends anything. It sees your training profile, your plan, your recent runs (the date, distance, time and pace) and what you say to it, never your name, email or GPS routes. You can withdraw permission in Settings, and press and hold any reply to report it.",
    },
    {
      q: "Is it medical advice?",
      a: "No. Run is not a medical device, and the coach's plans are not medical advice.",
      more: { label: "Medical disclaimer", href: "/run/medical-disclaimer" },
    },
    {
      q: "How do I cancel, or get a refund?",
      a: "In the store you subscribed through. Apple and Google handle both, so we can't cancel or refund for you. Deleting your account doesn't cancel the subscription.",
      more: { label: "Support", href: "/run/support" },
    },
    {
      q: "Where are my runs, and can I delete everything?",
      a: "On your phone. Backup is off until you turn it on. You can delete your account in the app at any time, or by email if you have removed the app.",
      more: { label: "Delete your account", href: "/run/delete-account" },
    },
    { q: "Is there a feed?", a: "No feed, no followers, no leaderboards, no kudos. Just you and your running." },
    { q: "Which phones?", a: where("run") },
  ],
  lift: [
    {
      q: "Do I need an account?",
      a: "No. Tracking needs no account, and with no account nothing leaves your phone. Sign in with Apple, Google or email to back your workouts up.",
    },
    {
      q: "Does it work offline?",
      a: "Yes. Every set is saved on your phone the moment you tick it, with no signal needed. Backup runs when you open the app, finish a workout or change a saved workout, and never while you are lifting.",
    },
    {
      q: "What is free?",
      a: "Tracking, your saved workouts, your history and your stats. The coach, plans and progress photos are the subscription.",
    },
    {
      q: "What does the subscription add?",
      a: "A plan built around your goal and the days you can train, a coach you can talk to that reads your log, and progress photos. Coach and Premium Coach hold the same features; Premium Coach gives the coach far more room to talk.",
    },
    {
      q: "How much is it?",
      a: "The price is shown in the app and in your store, in your own currency. Lift has its own subscription, separate from Run's, and tracking stays free either way.",
    },
    {
      q: "Is the coach a person? What does it see?",
      a: "It is an AI model, not a person, and it is not medical advice. It sees your messages, a summary of your training and your plan answers, including any injury notes, never your name, email, account ID or photos. You can switch it off, and nothing is sent while it is off.",
      more: { label: "How the AI coach uses your data", href: "/lift/ai-disclosure" },
    },
    {
      q: "How do I cancel, or get a refund?",
      a: "In the store you subscribed through. Apple and Google handle both, so we can't cancel or refund for you. Deleting your account doesn't cancel the subscription.",
      more: { label: "Support", href: "/lift/support" },
    },
    {
      q: "Can I delete my data?",
      a: "Yes. In the app you choose between deleting your Lift data and deleting your whole MGKFitness account. If you have removed the app, you can ask by email.",
      more: { label: "Delete your account", href: "/lift/delete-account" },
    },
    {
      q: "I used Liftio. What happens now?",
      a: "Your account and history carry over. The old Liftio subscription doesn't, so cancel it in your store.",
    },
    {
      q: "The rest timer didn't buzz.",
      a: "It needs permission to send notifications. Check your Focus modes, and on Android, battery optimisation and Alarms & reminders.",
      more: { label: "Support", href: "/lift/support" },
    },
    { q: "Which phones?", a: where("lift") },
  ],
};

/** The help and legal pages for each app, as the foot lists them. */
export const help: Record<App, [string, string][]> = {
  run: [
    ["Support", "/run/support"],
    ["Privacy policy", "/run/privacy"],
    ["Medical disclaimer", "/run/medical-disclaimer"],
    ["Terms of use", "/run/terms"],
    ["Delete your account", "/run/delete-account"],
  ],
  lift: [
    ["Support", "/lift/support"],
    ["Privacy policy", "/lift/privacy"],
    ["Terms of use", "/lift/terms"],
    ["How the AI coach uses your data", "/lift/ai-disclosure"],
    ["Delete your account", "/lift/delete-account"],
  ],
};
