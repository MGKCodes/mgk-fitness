import type { Metadata } from "next";

export const metadata: Metadata = {
  title: { absolute: "MGKFitness" },
  description:
    "Two fitness apps that share an account, a design system and a coach. Legal pages and support.",
};

// Deliberately not a marketing page. This subdomain exists today to serve the
// documents an App Store listing has to link to, and a hero making claims about
// an unreleased app would be the wrong kind of first thing to write. When there
// is a product to announce, it gets announced here.
export default function Home() {
  return (
    <main>
      <p className="eyebrow">MGKCodes Ltd</p>
      <h1>MGKFitness</h1>
      <p className="lede">
        Two fitness apps that share one account, one design system and one
        coach. Run is a running tracker and training coach. Lift is for the
        gym. Use either on its own, or both, and they read each other.
      </p>

      <h2>Run</h2>
      <ul>
        <li>
          <a href="/run/privacy">Privacy policy</a>
        </li>
        <li>
          <a href="/run/medical-disclaimer">Medical disclaimer</a>
        </li>
        <li>
          <a href="/run/terms">Terms of use</a>
        </li>
        <li>
          <a href="/run/support">Support</a>
        </li>
        <li>
          <a href="/run/delete-account">Delete your account</a>
        </li>
      </ul>

      <h2>Lift</h2>
      <ul>
        <li>
          <a href="/lift/privacy">Privacy policy</a>
        </li>
        <li>
          <a href="/lift/terms">Terms of use</a>
        </li>
        <li>
          <a href="/lift/ai-disclosure">How the AI coach uses your data</a>
        </li>
        <li>
          <a href="/lift/support">Support</a>
        </li>
        <li>
          <a href="/lift/delete-account">Delete your account</a>
        </li>
      </ul>
    </main>
  );
}
