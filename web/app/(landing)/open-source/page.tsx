import type { Metadata } from "next";
import { Bar } from "../bar";
import { Foot } from "../foot";
import { source } from "../links";

export const metadata: Metadata = {
  title: { absolute: "Open source · MGKFitness" },
  description:
    "Run and Lift are open source under the AGPL: both apps, the design system they share, the database and the coach's server code, in one public repository.",
  openGraph: { title: "Open source · MGKFitness", url: "/open-source" },
};

// Every fact on this page is one the repository says of itself: README.md,
// CONTRIBUTING.md, SECURITY.md, NOTICE.md, CODE_OF_CONDUCT.md and
// LICENSE-EXCEPTION.md. Change it there first.

/** The repository as GitHub counts it, read at most hourly. Nothing is shown if it can't be read. */
async function counts(): Promise<{ stars: number; forks: number; issues: number; pushed: string } | undefined> {
  try {
    const response = await fetch("https://api.github.com/repos/MGKCodes/mgk-fitness", {
      headers: { accept: "application/vnd.github+json" },
      next: { revalidate: 3600 },
    });
    if (!response.ok) return undefined;
    const repo = (await response.json()) as {
      stargazers_count: number;
      forks_count: number;
      open_issues_count: number;
      pushed_at: string;
    };
    return { stars: repo.stargazers_count, forks: repo.forks_count, issues: repo.open_issues_count, pushed: repo.pushed_at };
  } catch {
    return undefined;
  }
}

const tree: [string, string][] = [
  ["apps/mgk_run", "Run, the running tracker and training coach."],
  ["apps/mgk_lift", "Lift, the strength log."],
  ["packages/mgk_ui", "The design system both apps are built from."],
  ["packages/mgk_auth", "The one account, shared by both."],
  ["packages/mgk_units", "Distances stored in metric and shown in km or miles."],
  ["supabase/", "The database, as migrations, with its tests; and the server functions: the coach, account deletion, subscriptions and the daily summary."],
  ["scripts/store", "The tools that send each release to the stores."],
  ["web/", "This website. It is not under the AGPL."],
];

const built: [string, string][] = [
  ["Flutter and Dart", "Both apps and their shared packages, as one workspace."],
  ["Supabase", "Postgres, with row-level security as the boundary between one person's data and another's; sign-in, storage, and server functions in Deno."],
  ["The coach, server-side", "Every AI request goes from the app to a server function and on to the model's provider. No key is ever in the app, and a validator checks what the model says before you see it."],
  ["Codemagic", "Builds, tests and sends every store build."],
];

const rules = [
  "No provider key in an app.",
  "Row-level security on every table, and a user on every row that belongs to one.",
  "Offline first: the apps work with no signal.",
  "Distances stored in metric.",
  "Health data treated as special-category data.",
];

/** A way into the source. */
function Repo({ to, title, note }: { to: string; title: string; note: string }) {
  return (
    <a className="repo" href={to}>
      <small>On GitHub</small>
      {title}
      <span>{note}</span>
    </a>
  );
}

export default async function OpenSource() {
  const github = await counts();
  const day = github ? new Date(github.pushed).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "";

  return (
    <>
      <Bar />

      <main className="page open-page">
        <header className="page-head">
          <span className="tag">Open source</span>
          <h1>Built in the open.</h1>
          <p className="lede">
            Run and Lift are open source, under the AGPL. The code that records your training and
            talks to the coach is there to be read, questioned and improved.
          </p>
          <div className="repos">
            <Repo to={source.repository} title="MGKFitness" note="Both apps, the parts they share, and the backend" />
            <Repo to={source.contributing} title="Contribute" note="How to send a change, and the rules" />
          </div>
          {github && (
            <dl className="counts">
              <div>
                <dt>Stars</dt>
                <dd>{github.stars}</dd>
              </div>
              <div>
                <dt>Forks</dt>
                <dd>{github.forks}</dd>
              </div>
              <div>
                <dt>Open issues</dt>
                <dd>{github.issues}</dd>
              </div>
              <div>
                <dt>Last change</dt>
                <dd>{day}</dd>
              </div>
            </dl>
          )}
        </header>

        <section className="tree">
          <span className="tag">What is in it</span>
          <h2>
            All of it, in one repository. <span>Both apps, what they share, and the backend.</span>
          </h2>
          <dl className="rows">
            {tree.map(([path, what]) => (
              <div key={path}>
                <dt>
                  <code>{path}</code>
                </dt>
                <dd>{what}</dd>
              </div>
            ))}
          </dl>
        </section>

        <section className="built">
          <span className="tag">How it is built</span>
          <h2>
            The same code as the stores. <span>Every build sent to a store is tagged with its commit.</span>
          </h2>
          <ul className="facts">
            {built.map(([name, what]) => (
              <li key={name}>
                <h3>{name}</h3>
                <p>{what}</p>
              </li>
            ))}
          </ul>
          <p className="small">
            A build is tagged on the commit it came from, as <code>run/build-29</code> or{" "}
            <code>lift/build-45</code>, so you can read exactly what you are running. Work happens on{" "}
            <code>develop</code>; <code>main</code> holds what went to review. This website is Next.js,
            on Vercel.
          </p>
        </section>

        <section className="licence">
          <span className="tag">The licence</span>
          <h2>
            Read it, run it, change it, share it. <span>And share your changes too.</span>
          </h2>
          <ul className="facts">
            <li>
              <h3>AGPL-3.0</h3>
              <p>
                The apps and the backend are under the <a href={source.licence}>GNU AGPL v3</a>. Run a
                changed version for other people, over the internet too, and you share your changes.
              </p>
            </li>
            <li>
              <h3>Through the stores</h3>
              <p>
                An added permission lets anyone ship a version through the app stores, as long as
                they publish its full source.
              </p>
            </li>
            <li>
              <h3>Licences of their own</h3>
              <p>
                This website is not open source. The exercise drawings are CC BY-SA 4.0, adapted
                from Everkinetic, and credited in the app. The Inter typeface is under the OFL.
              </p>
            </li>
          </ul>
        </section>

        <section className="contribute">
          <span className="tag">Contributing</span>
          <h2>
            An idea, a bug, a fix, a feature. <span>Every change is read before it is merged.</span>
          </h2>
          <ol className="how">
            <li>
              <a href={source.issues}>Open an issue</a> for a bug or an idea. For anything large,
              open one before you start, so the work isn&rsquo;t wasted.
            </li>
            <li>Fork the repository and branch from <code>develop</code>.</li>
            <li>Make the change, with its tests.</li>
            <li>
              Sign off each commit (<code>git commit -s</code>): a Developer Certificate of Origin,
              no contributor agreement.
            </li>
            <li>Open a pull request into <code>develop</code>. It is read, then checked, then merged.</li>
          </ol>
          <h3 className="rules-head">The rules that don&rsquo;t bend</h3>
          <ul className="rules">
            {rules.map((rule) => (
              <li key={rule}>{rule}</li>
            ))}
          </ul>
        </section>

        <section className="yourself">
          <span className="tag">Run it yourself</span>
          <h2>
            The apps and the whole backend, on your own machine. <span>With Flutter, Docker and the Supabase CLI.</span>
          </h2>
          <pre>
            <code>{`git clone ${source.repository}.git
cd mgk-fitness
flutter pub get
supabase start
supabase db reset

cd apps/mgk_run
dart run build_runner build --delete-conflicting-outputs
flutter run --dart-define-from-file=config/app_config.json`}</code>
          </pre>
          <p className="small">
            Before the last line, copy <code>config/app_config.example.json</code> beside it and fill
            in your own Supabase project&rsquo;s address and key; a local one from{" "}
            <code>supabase start</code> works. <a href={source.readme}>The README</a> has every step,
            and the tests.
          </p>
        </section>

        <section className="trust">
          <ul className="facts">
            <li>
              <h3>Security, privately</h3>
              <p>
                Found a way to see somebody else&rsquo;s data? Tell us through the repository&rsquo;s{" "}
                <a href={source.security}>Security tab</a>, not an issue, and test only on your own
                or a local copy. Reporters are credited if they want to be.
              </p>
            </li>
            <li>
              <h3>A code of conduct</h3>
              <p>
                The Contributor Covenant 2.1. Reports go to hello@mgkcodes.com, and are acted on.
              </p>
            </li>
          </ul>
        </section>
      </main>

      <Foot />
    </>
  );
}
