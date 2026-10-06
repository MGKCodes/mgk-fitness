import { apps, availability, source } from "../(landing)/links";

/**
 * What this site tells mgkcodes.com about the suite.
 *
 * The studio's home page shows each of its products being built, from a
 * sketch to the live site, and says where each one is out. It reads that
 * from here rather than keeping its own copy, so the studio's page changes
 * when this one does: going live in a store is still an edit to `links.ts`
 * and nothing else, and mgkcodes.com follows within the hour.
 *
 * The shape is mgkcodes.com's to define (`lib/studio.ts` there). Version 1:
 * a line of state, the stores, and the app's screens with the first one's
 * source, abridged, which the studio's page types out while it builds the
 * phone.
 *
 * `source` is how to work on the suite, from `links.ts` and CONTRIBUTING.md.
 * The studio's page shows it only while `open` is true, so making the
 * repository public is still the one edit to `links.ts`.
 */
export const dynamic = "force-static";

const first = (store: "apple" | "google") => apps.map(([, links]) => links[store]).find(Boolean);

export function GET() {
  return Response.json({
    studio: 1,
    status: availability(),
    live: apps.some(([, links]) => links.apple || links.google),
    stores: [
      { platform: "iPhone", store: "App Store", href: first("apple") },
      { platform: "Android", store: "Google Play", href: first("google") },
    ],
    app: {
      // The same screens the landing page shows, from `public/screens`.
      screens: [
        { src: "/screens/run-record.png", label: "Run" },
        { src: "/screens/run-plan.png", label: "Run" },
        { src: "/screens/lift-log.png", label: "Lift" },
      ],
      // apps/mgk_run, recording_screen.dart, abridged to a phone's width.
      code: [
        "Scaffold(",
        "  body: Stack(",
        "    children: [",
        "      RouteMap(",
        "        points: _points),",
        "      _TopStrip(",
        "        label: 'Recording'),",
        "      _Panel(",
        "        distanceM: _d),",
        "    ],",
        "  ),",
        ")",
      ],
    },
    source: {
      open: source.open,
      repository: source.repository,
      contributing: source.contributing,
      license: "AGPL-3.0",
      // CONTRIBUTING.md: work happens on develop, and every commit is signed off.
      branch: "develop",
      signOff: true,
      setup: ["flutter pub get", "flutter analyze"],
    },
  });
}
