import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./landing.css";

// The apps' own typeface. `next/font` fetches it when the site is built and
// serves it from this domain, so a visitor's browser never calls a font host.
// That is the same promise the legal pages keep by using no webfont at all.
const inter = Inter({ subsets: ["latin"], display: "swap", variable: "--inter" });

const title = "MGKFitness";
const description =
  "MGKFitness is two apps on one account. Run is a running tracker and training coach. Lift is a strength log with a coach of its own.";

export const metadata: Metadata = {
  metadataBase: new URL("https://mgkfitness.mgkcodes.com"),
  title: { absolute: title },
  description,
  // What a link to the page shows where it is shared. The picture is
  // `opengraph-image.jpg`, beside this file: the page's own hero, photographed
  // at 1200 by 630. `design/landing/README.md` says how to take it again.
  openGraph: {
    type: "website",
    url: "/",
    siteName: title,
    title,
    description,
    locale: "en_GB",
  },
  twitter: { card: "summary_large_image", title, description },
  // The page is live and still asks not to be indexed. Being found by a search
  // is a separate decision from being reachable by a link.
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
