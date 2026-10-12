import type { CSSProperties } from "react";
import { Bar } from "./bar";
import { type App, apps, facts, help, pages, questions, reasons, type Screen, terms } from "./content";
import { Phone } from "./device";
import { Foot } from "./foot";
import { Mark } from "./mark";
import type { Key } from "./storyboard";
import { Stores } from "./stores";

/** A screen that is simply shown, outside the film. */
const always = { "--in": -1 } as CSSProperties;

/** The store pictures' screens, the size they were drawn at. */
const size: [number, number] = [1290, 2796];

/**
 * One of the film's stills, laid behind what is over it: the wide still on a
 * wide screen and the tall one on an upright screen, as the film itself does.
 * It says nothing a reader needs, so it has no words of its own.
 */
function Still({ at, first }: { at: Key; first?: boolean }) {
  return (
    <picture className="still">
      <source media="(max-aspect-ratio: 1 / 1)" srcSet={`/film/tall/keys/${at}-940.webp`} />
      <img
        src={`/film/wide/keys/${at}-1920.webp`}
        srcSet={`/film/wide/keys/${at}-960.webp 960w, /film/wide/keys/${at}-1920.webp 1920w`}
        sizes="100vw"
        alt=""
        loading={first ? "eager" : "lazy"}
        fetchPriority={first ? "high" : "auto"}
        decoding="async"
      />
    </picture>
  );
}

/** A phone showing one screen, standing still. */
function Shows({ screen, time, lazy }: { screen: Screen; time: string; lazy?: boolean }) {
  return <Phone screens={[{ ...screen, style: always }]} size={size} time={time} lazy={lazy} />;
}

/**
 * One app's own page. Its head stands in the app's place in the film, with
 * the app's home screen; then what it does, screen by screen, each on its own
 * stage; one line over another of the film's stills; what is free and what
 * the coach adds; why the coach; the other app; and the questions people
 * ask, folded away until they are wanted.
 */
export function AppPage({ app }: { app: App }) {
  const { name, what } = apps[app];
  const page = pages[app];
  const other: App = app === "run" ? "lift" : "run";

  return (
    <>
      <Bar />

      <main className={`page app-page ${app}`}>
        <header className="hero">
          <Still at={page.still} first />
          <div className="words">
            <h1>
              {name.toUpperCase()}
              <Mark of={app} />
            </h1>
            <p className="lede">{what}</p>
            <Stores app={app} />
          </div>
          <div className="lead">
            <Shows screen={page.head} time={page.time} />
          </div>
        </header>

        <section className="features">
          <span className="tag">What it does</span>
          <ul>
            {page.features.map((feature) => (
              <li key={feature.src}>
                <div className="plinth">
                  <Shows screen={feature} time={page.time} lazy />
                </div>
                <div className="words">
                  <span className="tag">{feature.tag}</span>
                  <h3>
                    {feature.lines[0]} <span>{feature.lines[1]}</span>
                  </h3>
                  <p>{feature.more}</p>
                </div>
              </li>
            ))}
          </ul>
        </section>

        <section className="interlude">
          <Still at={page.interlude.still} />
          <p>
            {page.interlude.line[0]} <span>{page.interlude.line[1]}</span>
          </p>
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
            <div className="paid">
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
              <Shows screen={page.coach} time={page.time} lazy />
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
          <a className={`other ${other}`} href={`/${other}`}>
            <Still at={pages[other].still} />
            <b>
              {apps[other].name.toUpperCase()}
              <Mark of={other} />
            </b>
            <span>
              {apps[other].what} <span aria-hidden="true">→</span>
            </span>
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
