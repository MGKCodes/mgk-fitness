import Image from "next/image";
import type { ReactNode } from "react";
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

// One camera move, from above the track down to it, along the straight, under
// the stand and into the weight room. Run arrives where the camera lands on
// the track and Lift where it comes out of the tunnel. `design/landing/` has
// the idea and the brief for the stills; `storyboard.ts` has the pacing.
//
// The copy is the description this page already carried, laid out. It is a
// stand-in until the page's own words are written.
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
          </Beat>

          <Beat from="track" className="app">
            <h2>
              RUN
              <Mark app="run" />
            </h2>
            <p>A running tracker and training coach.</p>
            <Image
              className="phone"
              src="/screens/run-home.png"
              alt="Run's home screen: today's session, the week so far and the last run."
              width={786}
              height={1704}
            />
          </Beat>

          <Beat from="s3" className="line">
            <p>One account. Each app reads the other.</p>
          </Beat>

          <Beat from="room" className="app">
            <h2>
              LIFT
              <Mark app="lift" />
            </h2>
            <p>For the gym.</p>
            <Image
              className="phone"
              src="/screens/lift-track.png"
              alt="Lift's home screen: today's workout, the week so far and the last session."
              width={1170}
              height={2532}
            />
          </Beat>
        </Film>

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
