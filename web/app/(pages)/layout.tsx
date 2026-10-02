import type { Metadata } from "next";
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
          MGKCodes Ltd. <a href="mailto:hello@mgkcodes.com">hello@mgkcodes.com</a>
        </footer>
      </body>
    </html>
  );
}
