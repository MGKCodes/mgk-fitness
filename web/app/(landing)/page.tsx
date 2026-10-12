import type { CSSProperties, ReactNode } from "react";
import { Bar } from "./bar";
import { apps, steps, type Step } from "./content";
import { Phone } from "./device";
import { Film } from "./film";
import { Foot } from "./foot";
import { availability, social } from "./links";
import { Mark } from "./mark";
import { SocialGlyph } from "./social";
import { Stores } from "./stores";

/** The suite's Instagram, once it has an address in `links.ts`. */
const instagram = social.find((account) => account.name === "Instagram" && account.url);

/** A post on the suite's Instagram, as the studio's posting service keeps it. */
type Post = { id: string; title: string; cover?: string; coverAlt?: string; links: { platform: string; url: string }[] };

/**
 * The latest posts on the suite's Instagram, from the service that posts them
 * (mgkcodes-social's `/recent?brand=mgkfitness`), so the site keeps no list of
 * its own. Read again at most every half hour. If it can't be read the
 * section shows the account alone, never an error.
 */
async function recentPosts(): Promise<Post[]> {
  try {
    const response = await fetch("https://social.mgkcodes.com/recent?brand=mgkfitness", { next: { revalidate: 1800 } });
    if (!response.ok) return [];
    const { posts } = (await response.json()) as { posts: Post[] };
    return posts.filter((post) => post.cover && post.links.some((link) => link.platform === "instagram")).slice(0, 6);
  } catch {
    return [];
  }
}

/** The suite's Instagram: its latest posts, each a way to that post, and the account. */
async function Recent() {
  if (!instagram) return null;
  const posts = await recentPosts();
  return (
    <section className="recent" id="instagram">
      <span className="tag">Instagram</span>
      <h2>
        See our recent posts. <span>One word, a picture, and something worth keeping.</span>
      </h2>
      {posts.length > 0 && (
        <ul className="posts">
          {posts.map((post) => (
            <li key={post.id}>
              <a href={post.links.find((link) => link.platform === "instagram")?.url} target="_blank" rel="noopener">
                <img src={post.cover} alt={post.coverAlt ?? post.title} width={540} height={675} loading="lazy" />
              </a>
            </li>
          ))}
        </ul>
      )}
      <a className="follow" href={instagram.url} target="_blank" rel="noopener">
        <SocialGlyph name="Instagram" />
        Follow {instagram.handle}
      </a>
    </section>
  );
}

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

// When each of three steps is on screen, as shares of its hold. The phone
// takes the first fifth to arrive, so the first step is given longest.
const turns = [0.44, 0.72];
const during = (i: number) =>
  ({ "--in": i === 0 ? -1 : turns[i - 1], "--out": turns[i] ?? 2 }) as CSSProperties;

/** An app's name at the size of the page, its stores, and three of its screens in turn. */
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
        <Mark of={app} />
      </h2>
      <Stores app={app} />
      <a className="more" href={`/${app}`}>
        More about {apps[app].name} <span aria-hidden="true">→</span>
      </a>
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

/** Where the rest of the site is: each app's page, and the source. */
const pages: [string, string, string][] = [
  ["/run", "Run", apps.run.what],
  ["/lift", "Lift", apps.lift.what],
  ["/open-source", "Open source", "Every line of both apps and their backend, there to read."],
];

// One camera move, from above the track down to it, along the straight, into
// the players' tunnel and out in the weight room under the seats. Run arrives
// where the camera lands on the track and Lift where it comes out of the
// tunnel. `design/landing/` has the idea and the brief for the stills;
// `storyboard.ts` has the pacing. The film is the home page; what each app
// does in full, the coach, the questions and the source are pages of their own.
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
            <p className="soon">{availability()}</p>
          </Beat>

          {/* 14:41 is the time Run's store screens were drawn at: the coach
              screen greets the afternoon. */}
          <App shot="track" app="run" steps={steps.run} size={[1290, 2796]} time="14:41" />

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
            steps={steps.lift}
            size={[1170, 2532]}
            time="19:04"
            bare={{ ground: "#1f1f1f" }}
          />
        </Film>

        <nav className="onward" aria-label="More">
          {pages.map(([href, name, line]) => (
            <a key={href} href={href}>
              <b>
                {name} <span aria-hidden="true">→</span>
              </b>
              <span>{line}</span>
            </a>
          ))}
        </nav>

        <Recent />
      </main>

      <Foot />
    </>
  );
}
