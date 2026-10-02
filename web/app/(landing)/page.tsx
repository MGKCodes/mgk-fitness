import type { CSSProperties, ReactNode } from "react";
import { Bar } from "./bar";
import { Phone } from "./device";
import { Film } from "./film";
import { source } from "./links";
import { Mark } from "./mark";
import { Stores } from "./stores";
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

/**
 * A way into the source: a link once the repository is public, and a place
 * held for it until then. `links.ts` says which.
 */
function Source({ to, title, note }: { to: string; title: string; note: string }) {
  const inside = (
    <>
      <small>{source.open ? "On GitHub" : "Opening soon"}</small>
      {title}
      <span>{note}</span>
    </>
  );
  return source.open ? (
    <a className="repo" href={to}>
      {inside}
    </a>
  ) : (
    <span className="repo held">{inside}</span>
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

// Why somebody would pay for the coach: what goes wrong without one, and what
// the coach does about it. The left of each pair is a trouble a reader will
// recognise; the right is something the listings already say the coach does,
// so the answer is never bigger than the product. Nothing here promises a
// result, and the prices beside it are the stores' own (Run's ADR-0029).
const reasons: [string, string][] = [
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

// What makes the two apps one suite, each as something that is true of them.
// The last is marked as coming because it is not built: `core.activities`
// holds every run and workout so that each app *can* show the other's, and
// neither app reads it yet. The page says so rather than claiming it.
const facts: [string, string, boolean?][] = [
  [
    "One account",
    "The account you make in Run is your account in Lift. Sign in to either with it.",
  ],
  [
    "One design",
    "Both are built from the same parts, so the second app already feels like the first.",
  ],
  [
    "Free to track",
    "Recording a run and logging a workout are free in both, with no account needed to start.",
  ],
  [
    "One history",
    "Your runs in Lift and your lifting in Run, at no extra cost. It is what the suite is for.",
    true,
  ],
];

/** A screen that is simply shown, outside the film. */
const always = { "--in": -1 } as CSSProperties;

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
  time,
  bare,
}: {
  shot: string;
  app: "run" | "lift";
  steps: Step[];
  size: [number, number];
  /** What the phone's clock says. It should agree with what the screens show. */
  time: string;
  bare?: { ground: string };
}) {
  return (
    <Beat from={shot} className={`app ${app}`}>
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
      <Phone
        screens={steps.map((step, i) => ({
          src: `/screens/${step.screen}.png`,
          alt: step.alt,
          style: during(i),
        }))}
        size={size}
        time={time}
        bare={bare}
      />
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
      <Bar />

      <main id="top">
        <Film places={{ run: "track", lift: "room" }}>
          <Beat from="above" className="above">
            <h1>MGKFitness</h1>
            <p className="lede">
              Run and Lift. <span>One account, made to be used together.</span>
            </p>
            <p>
              Run is a running tracker and training coach. Lift is a strength log
              with a coach of its own.
            </p>
            <p className="soon">Coming to iPhone and Android</p>
          </Beat>

          {/* 14:41 is the time Run's store screens were drawn at: the coach
              screen greets the afternoon. */}
          <App shot="track" app="run" steps={run} size={[1290, 2796]} time="14:41" />

          {/* What is true of the two apps today is the account. Neither shows
              the other's training yet, so the line does not say that it does. */}
          <Beat from="s3" className="line">
            <p>
              One account. <span>From the track to the weight room.</span>
            </p>
          </Beat>

          {/* Lift's session started at 6:30pm and is 34 minutes in. Its
              captures leave no room for a status bar, so they sit under it. */}
          <App
            shot="room"
            app="lift"
            steps={lift}
            size={[1170, 2532]}
            time="19:04"
            bare={{ ground: "#1f1f1f" }}
          />
        </Film>

        <section className="suite">
          <span className="tag">MGKFitness</span>
          <h2>
            Two apps, made as one. <span>Use either on its own, or both on one account.</span>
          </h2>
          <ul className="facts">
            {facts.map(([name, what, soon]) => (
              <li key={name}>
                <h3>
                  {name}
                  {soon && <span className="tag">Coming</span>}
                </h3>
                <p>{what}</p>
              </li>
            ))}
          </ul>
        </section>

        <section className="coach">
          <span className="tag">The coach &middot; &pound;0.99 a month</span>
          <h2>
            A personal trainer costs too much and is never free when you are.{" "}
            <span>The coach is &pound;0.99 a month, and there whenever you train.</span>
          </h2>

          <div className="case">
            <ol className="reasons">
              {reasons.map(([trouble, answer]) => (
                <li key={trouble}>
                  <p>{trouble}</p>
                  <p>{answer}</p>
                </li>
              ))}
            </ol>
            {/* The coach itself, in both apps, saying something only a coach
                that has read the log could say. */}
            <div className="pair">
              <Phone
                screens={[
                  {
                    src: "/screens/run-coach.png",
                    alt: "Run's coach, asked what a half marathon could be run in, answering from a recent 5k.",
                    style: always,
                  },
                ]}
                size={[1290, 2796]}
                time="14:41"
              />
              <Phone
                screens={[
                  {
                    src: "/screens/lift-coach.png",
                    alt: "Lift's coach saying: your bench has not moved in three weeks. Want to look at it?",
                    style: always,
                  },
                ]}
                size={[1170, 2532]}
                time="19:04"
                bare={{ ground: "#1f1f1f" }}
              />
            </div>
          </div>

          <dl className="tiers">
            <div>
              <dt>Coach</dt>
              <dd>
                <b>&pound;0.99</b> a month
              </dd>
              <dd>A training plan, adjusted every week, and a coach to ask.</dd>
            </div>
            <div>
              <dt>Premium Coach</dt>
              <dd>
                <b>&pound;2.99</b> a month
              </dd>
              <dd>The same coach, with far more room to talk.</dd>
            </div>
          </dl>
          <p className="small">
            UK prices. Run and Lift each have their own subscription, which renews
            monthly until you cancel it. Tracking stays free either way. The coach is
            an AI model, not a person, and it is not medical advice.
          </p>
        </section>

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
        </section>

        <section className="open">
          <span className="tag">Open source</span>
          <h2>
            Built in the open. <span>Made with the people who use it.</span>
          </h2>
          {/* Said in the present only once it is true. Until the repository is
              public the code cannot be read, whatever its licence says. */}
          {source.open ? (
            <p>
              Run and Lift are open source, under the AGPL. The code that records
              your training and talks to the coach is there to be read, questioned
              and improved, and contributions are encouraged: an idea, a bug, a fix,
              a feature.
            </p>
          ) : (
            <p>
              Run and Lift are going open source, under the AGPL. The code that
              records your training and talks to the coach will be there to be read,
              questioned and improved, and contributions will be encouraged: an
              idea, a bug, a fix, a feature.
            </p>
          )}
          <div className="repos">
            <Source to={source.run} title="Run" note="The running app" />
            <Source to={source.lift} title="Lift" note="The strength app" />
            <Source to={source.contributing} title="Contribute" note="How to send a change" />
          </div>
          {!source.open && (
            <p className="small">The repository opens to everybody soon.</p>
          )}
        </section>

        <section className="waiting" id="waiting-list">
          <h2>Get an email when Run and Lift are live.</h2>
          <WaitingList />
          {/* Where the apps will be got from. Held for the store links, which
              `links.ts` turns on. */}
          <dl className="get">
            <div>
              <dt>Run</dt>
              <dd>
                <Stores app="run" />
              </dd>
            </div>
            <div>
              <dt>Lift</dt>
              <dd>
                <Stores app="lift" />
              </dd>
            </div>
          </dl>
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
          MGKFitness is made by MGKCodes Ltd.{" "}
          <a href="mailto:hello@mgkcodes.com">hello@mgkcodes.com</a>
        </p>
      </footer>
    </>
  );
}
