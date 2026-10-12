import { stores } from "./links";

type Store = "App Store" | "Google Play";

/**
 * The two stores' own marks, as Simple Icons 16.33.0 draws them (CC0), on a 24
 * by 24 canvas, for the bar, where a badge has no room. Flat and in one colour,
 * like the Instagram mark beside them.
 */
export const storeGlyphs: Record<Store, string> = {
  "App Store":
    "M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701",
  "Google Play":
    "M22.018 13.298l-3.919 2.218-3.515-3.493 3.543-3.521 3.891 2.202a1.49 1.49 0 0 1 0 2.594zM1.337.924a1.486 1.486 0 0 0-.112.568v21.017c0 .217.045.419.124.6l11.155-11.087L1.337.924zm12.207 10.065l3.258-3.238L3.45.195a1.466 1.466 0 0 0-.946-.179l11.04 10.973zm0 2.067l-11 10.933c.298.036.612-.016.906-.183l13.324-7.54-3.23-3.21z",
};

export function StoreGlyph({ store }: { store: Store }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d={storeGlyphs[store]} />
    </svg>
  );
}

// The stores' badges as Apple and Google supply them, unaltered (`public/badges/`:
// Apple's from its marketing toolbox, Google's from play.google.com with only
// its transparent margin trimmed). Both allow a badge only for an app that is on
// sale in their store, so an app not there yet has a held place instead.
const badges: Record<Store, { src: string; alt: string; width: number }> = {
  "App Store": { src: "/badges/app-store.svg", alt: "Download on the App Store", width: 120 },
  "Google Play": { src: "/badges/google-play.png", alt: "Get it on Google Play", width: 134 },
};

/** One store for one app: its badge once the app is on sale there, and a place held for it until then. */
function Badge({ store, href, name }: { store: Store; href?: string; name: string }) {
  if (!href) {
    return (
      <span className="store held">
        <small>Coming soon to</small>
        {store}
      </span>
    );
  }
  const badge = badges[store];
  return (
    <a className="badge" href={href} aria-label={`${name} on ${store === "App Store" ? "the App Store" : "Google Play"}`}>
      <img src={badge.src} alt={badge.alt} width={badge.width} height={40} />
    </a>
  );
}

/** Where to get an app: both stores, side by side. */
export function Stores({ app }: { app: "run" | "lift" }) {
  const name = app === "run" ? "Run" : "Lift";
  return (
    <div className="stores">
      <Badge store="App Store" href={stores[app].apple} name={name} />
      <Badge store="Google Play" href={stores[app].google} name={name} />
    </div>
  );
}
