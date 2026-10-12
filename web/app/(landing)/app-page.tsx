import type { CSSProperties } from "react";
import { Bar } from "./bar";
import { type App, apps, facts, help, questions, reasons, steps, terms } from "./content";
import { Phone } from "./device";
import { Foot } from "./foot";
import { Mark } from "./mark";
import { Stores } from "./stores";

/** A screen that is simply shown, outside the film. */
const always = { "--in": -1 } as CSSProperties;

/** Each app's phone, as the film draws it: its screen size, its clock, and Lift's bare captures. */
const phone: Record<App, { size: [number, number]; time: string; bare?: { ground: string } }> = {
  run: { size: [1290, 2796], time: "14:41" },
  lift: { size: [1170, 2532], time: "19:04", bare: { ground: "#1f1f1f" } },
};

/**
 * One app's own page: what it does, screen by screen; what is free and what
 * the coach adds; why the coach; what it shares with the other app; and the
 * questions people ask, folded away until they are wanted.
 */
export function AppPage({ app }: { app: App }) {
  const { name, what, coachScreen, coachAlt } = apps[app];
  const other: App = app === "run" ? "lift" : "run";
  const p = phone[app];

  return (
    <>
      <Bar />

      <main className={`page ${app}`}>
        <header className="page-head">
          <h1>
            {name.toUpperCase()}
            <Mark of={app} />
          </h1>
          <p className="lede">{what}</p>
          <Stores app={app} />
        </header>

        <section className="does">
          <span className="tag">What it does</span>
          <ul className="screens">
            {steps[app].map((step) => (
              <li key={step.screen}>
                <Phone
                  screens={[{ src: `/screens/${step.screen}.png`, alt: step.alt, style: always }]}
                  size={p.size}
                  time={p.time}
                  bare={p.bare}
                />
                <span className="tag">{step.tag}</span>
                <p>
                  {step.lines[0]} <span>{step.lines[1]}</span>
                </p>
              </li>
            ))}
          </ul>
        </section>

        <section className="terms">
          <h2>
            Tracking is free. <span>The coach is the part you pay for.</span>
          </h2>
          <div className="columns">
            <div>
              <h3>Free</h3>
              <ul>
                {terms[app].free.map((line) => (
                  <li key={line}>{line}</li>
                ))}
              </ul>
            </div>
            <div>
              <h3>
                The coach <span className="tag">Subscription</span>
              </h3>
              <ul>
                {terms[app].coach.map((line) => (
                  <li key={line}>{line}</li>
                ))}
              </ul>
            </div>
          </div>
          <p className="small">
            {terms[app].premium} {name} has its own subscription, separate from{" "}
            {apps[other].name}&rsquo;s, and its price is shown in the app and your store, in your
            own currency. It renews monthly until you cancel it.
          </p>
        </section>

        <section className="coach">
          <span className="tag">The coach</span>
          <h2>
            A personal trainer costs too much and is never free when you are.{" "}
            <span>The coach is there whenever you train.</span>
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
            <div className="pair">
              <Phone screens={[{ src: `/screens/${coachScreen}.png`, alt: coachAlt, style: always }]} size={p.size} time={p.time} bare={p.bare} />
            </div>
          </div>
          <p className="small">The coach is an AI model, not a person, and it is not medical advice.</p>
        </section>

        <section className="suite">
          <span className="tag">With {apps[other].name}</span>
          <h2>
            Two apps, made as one. <span>Use {name} on its own, or both on one account.</span>
          </h2>
          <ul className="facts">
            {facts.map(([fact, line, soon]) => (
              <li key={fact}>
                <h3>
                  {fact}
                  {soon && <span className="tag">Coming</span>}
                </h3>
                <p>{line}</p>
              </li>
            ))}
          </ul>
          <a className="more" href={`/${other}`}>
            {apps[other].name}: {apps[other].what.replace(/\.$/, "")} <span aria-hidden="true">→</span>
          </a>
        </section>

        <section className="faq" id="questions">
          <span className="tag">Questions</span>
          <h2>Before you start.</h2>
          <div className="answers">
            {questions[app].map(({ q, a, more }) => (
              <details key={q}>
                <summary>{q}</summary>
                <p>
                  {a}
                  {more && (
                    <>
                      {" "}
                      <a href={more.href}>{more.label}</a>
                    </>
                  )}
                </p>
              </details>
            ))}
          </div>
          <p className="small">
            Something else? <a href={help[app][0][1]}>Support</a> has more answers, and a way to
            reach us.
          </p>
        </section>
      </main>

      <Foot />
    </>
  );
}
