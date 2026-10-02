import Image from "next/image";
import type { CSSProperties, ReactNode } from "react";
import { Film } from "./film";
import { Mark } from "./mark";
import { WaitingList } from "./waiting-list";

/** Words or a screen laid over the film for the shots from `from` to `to`. */
function Beat({
  from,
  to = from,
  className,
  children,
}: {
  from: string;
  to?: string;
  className: string;
  children: ReactNode;
}) {
  return (
    <div className={`beat ${className}`} data-beat data-from={from} data-to={to}>
      {children}
    </div>
  );
}

/** One thing an app does: what it costs, two lines about it, and the screen. */
type Step = { tag: string; lines: [string, string]; screen: string; alt: string };

// Every line here is one the store listings already make, in
// `apps/mgk_run/docs/app-store-listing.md` and `apps/mgk_lift/docs/store-listing.md`,
// and each says whether it is free or the subscription, as the listings must.
// A page that promised more than the listing would be the one place the apps
// are oversold.
const run: Step[] = [
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
];

const lift: Step[] = [
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
];

// When each of three steps is on screen, as shares of its hold. The phone
// takes the first fifth to arrive, so the first step is given longest.
const turns = [0.44, 0.72];
const during = (i: number) =>
  ({ "--in": i === 0 ? -1 : turns[i - 1], "--out": turns[i] ?? 2 }) as CSSProperties;

/** An app's name at the size of the page, and three of its screens in turn. */
function App({
  shot,
  app,
  steps,
  size,
}: {
  shot: string;
  app: "run" | "lift";
  steps: Step[];
  size: [number, number];
}) {
  return (
    <Beat from={shot} className="app">
      <h2>
        {app.toUpperCase()}
        <Mark app={app} />
      </h2>
      <ol className="steps">
        {steps.map((step, i) => (
          <li key={step.screen} style={during(i)}>
            <span className="tag">{step.tag}</span>
            <p>
              {step.lines[0]} <span>{step.lines[1]}</span>
            </p>
          </li>
        ))}
      </ol>
      <div className="ticks" aria-hidden="true">
        {steps.map((step, i) => (
          <i key={step.screen} style={during(i)} />
        ))}
      </div>
      <div className="phone">
        {steps.map((step, i) => (
          <Image
            key={step.screen}
            style={during(i)}
            src={`/screens/${step.screen}.png`}
            alt={step.alt}
            width={size[0]}
            height={size[1]}
            sizes="(max-width: 760px) 70vw, 40svh"
            priority={i === 0 && app === "run"}
          />
        ))}
      </div>
    </Beat>
  );
}

// One camera move, from above the track down to it, along the straight, into
// the players' tunnel and out in the weight room under the seats. Run arrives
// where the camera lands on the track and Lift where it comes out of the
// tunnel. `design/landing/` has the idea and the brief for the stills;
// `storyboard.ts` has the pacing.
export default function Home() {
  return (
    <>
      <header className="bar">
        <a className="wordmark" href="#top">
          MGKFITNESS
        </a>
        <a className="pill" href="#waiting-list">
          Waiting list
        </a>
      </header>

      <main id="top">
        <Film>
          <Beat from="above" className="above">
            <h1>
              Two apps.
              <br />
              One coach.
            </h1>
            <p>
              Run is a running tracker and training coach. Lift is for the gym.
              Use either on its own, or both, and they read each other.
            </p>
            <p className="soon">Coming to iPhone and Android</p>
          </Beat>

          <App shot="track" app="run" steps={run} size={[1290, 2796]} />

          <Beat from="s3" className="line">
            <p>
              One account. <span>Each app reads the other.</span>
            </p>
          </Beat>

          <App shot="room" app="lift" steps={lift} size={[1170, 2532]} />
        </Film>

        <section className="terms">
          <h2>
            Tracking is free. <span>The coach is the part you pay for.</span>
          </h2>
          <div className="columns">
            <div>
              <h3>Free</h3>
              <dl>
                <dt>Run</dt>
                <dd>Track every run, with no account.</dd>
                <dd>Every run, kept on your phone.</dd>
                <dd>Your year, at a glance.</dd>
                <dt>Lift</dt>
                <dd>Log a set in one tap, with last time&rsquo;s numbers already in.</dd>
                <dd>A rest timer that buzzes with your phone locked.</dd>
                <dd>Works with no signal, and needs no account.</dd>
              </dl>
            </div>
            <div>
              <h3>
                The coach <span className="tag">Subscription</span>
              </h3>
              <dl>
                <dt>Run</dt>
                <dd>Know what to run today.</dd>
                <dd>A real plan, adjusted weekly.</dd>
                <dd>Ask the coach about any run.</dd>
                <dt>Lift</dt>
                <dd>A training plan built around your goal and the days you can train.</dd>
                <dd>A coach you can talk to about your training. It reads your log.</dd>
                <dd>Progress photos, one a week per pose.</dd>
              </dl>
            </div>
          </div>
          <p className="small">
            The coach is an AI model, not a person, and it is not medical advice.
          </p>
        </section>

        <section className="waiting" id="waiting-list">
          <h2>Get an email when Run and Lift are live.</h2>
          <WaitingList />
        </section>
      </main>

      <footer className="foot">
        <nav aria-label="Run">
          <h3>Run</h3>
          <a href="/run/privacy">Privacy policy</a>
          <a href="/run/medical-disclaimer">Medical disclaimer</a>
          <a href="/run/terms">Terms of use</a>
          <a href="/run/support">Support</a>
          <a href="/run/delete-account">Delete your account</a>
        </nav>
        <nav aria-label="Lift">
          <h3>Lift</h3>
          <a href="/lift/privacy">Privacy policy</a>
          <a href="/lift/terms">Terms of use</a>
          <a href="/lift/ai-disclosure">How the AI coach uses your data</a>
          <a href="/lift/support">Support</a>
          <a href="/lift/delete-account">Delete your account</a>
        </nav>
        <p>
          MGKCodes Ltd. <a href="mailto:hello@mgkcodes.com">hello@mgkcodes.com</a>
        </p>
      </footer>
    </>
  );
}
