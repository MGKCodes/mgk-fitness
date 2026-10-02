import { stores } from "./links";

/**
 * One store's button for one app: a link once the app is on sale there, and a
 * place held for it until then.
 *
 * These are plain buttons, not the stores' own badges. Apple and Google both
 * allow their badge only on an app that is in their store, so the badges
 * replace these when the links arrive, to each store's own artwork and rules.
 */
function Button({ store, href }: { store: "App Store" | "Google Play"; href?: string }) {
  if (!href) {
    return (
      <span className="store held">
        <small>Coming soon to</small>
        {store}
      </span>
    );
  }
  return (
    <a className="store" href={href}>
      <small>{store === "App Store" ? "Download on the" : "Get it on"}</small>
      {store}
    </a>
  );
}

/** Where to get an app: both stores, side by side. */
export function Stores({ app }: { app: "run" | "lift" }) {
  return (
    <div className="stores">
      <Button store="App Store" href={stores[app].apple} />
      <Button store="Google Play" href={stores[app].google} />
    </div>
  );
}
