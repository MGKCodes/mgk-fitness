import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./landing.css";

// The apps' own typeface. `next/font` fetches it when the site is built and
// serves it from this domain, so a visitor's browser never calls a font host.
// That is the same promise the legal pages keep by using no webfont at all.
const inter = Inter({ subsets: ["latin"], display: "swap", variable: "--inter" });

export const metadata: Metadata = {
  metadataBase: new URL("https://mgkfitness.mgkcodes.com"),
  title: { absolute: "MGKFitness" },
  description:
    "MGKFitness is two apps on one account. Run is a running tracker and training coach. Lift is a strength log with a coach of its own.",
  // Stays off until the film is real and the page is ready to be found. A page
  // that ranks before then is a first impression nobody chose.
  robots: { index: false, follow: true },
};

// The landing page has a layout of its own because it shares nothing with the
// pages in `(pages)/`: those are documents in the reader's own light or dark
// theme, and this is one dark full-bleed film.
export default function LandingLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en-GB" className={inter.variable}>
      <body>{children}</body>
    </html>
  );
}
