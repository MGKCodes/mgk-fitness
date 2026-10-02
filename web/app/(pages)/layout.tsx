import type { Metadata } from "next";
import { company, disclosure } from "../company";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://mgkfitness.mgkcodes.com"),
  title: {
    default: "MGKFitness",
    template: "%s | MGKFitness",
  },
  description:
    "Legal pages and support for the MGKFitness apps, by MGKCodes Ltd.",
  // Nothing here is worth ranking, and a support page outranking the app in
  // search would be actively unhelpful. Revisit when there is marketing copy.
  robots: { index: false, follow: true },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en-GB">
      <body>
        {children}
        <footer>
          <a href={`mailto:${company.email}`}>{company.email}</a> ·{" "}
          <a href="/privacy">Privacy on this website</a>
          <br />
          {disclosure}
        </footer>
      </body>
    </html>
  );
}
