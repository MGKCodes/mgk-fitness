import { readFile } from "node:fs/promises";
import path from "node:path";

/**
 * The suite's bare screens, by id, for any site that shows it.
 *
 * `public/screens` is the one place for them: raw phone screens, no device
 * frame, no background. The landing page shows them, mgkcodes.com reads the
 * first three through `app.screens`, and matthewkay.dev reads this whole list
 * through `screens`. So replacing a file there and deploying updates all
 * three, and sizes are read from the files at build, so a recapture at a
 * different size needs no edit here.
 *
 * An id is a promise: it always means the same screen. Add ids freely; never
 * reuse or rename one, because those sites look screens up by id. The alt
 * text matches the landing page's.
 */
type ScreenDef = { id: string; title: string; alt: string };

const DEFS: ScreenDef[] = [
  { id: "run-record", title: "Run · recording", alt: "Run recording a run: the route drawn on a map, 4.28 km, the time and the pace." },
  { id: "run-plan", title: "Run · plan", alt: "Run's plan for a marathon: this week's sessions, day by day." },
  { id: "run-coach", title: "Run · coach", alt: "Run's coach answering what a half marathon could be run in." },
  { id: "lift-log", title: "Lift · session", alt: "Lift during a session: sets of bench press ticked off, the next one filled in." },
  { id: "lift-rest", title: "Lift · rest", alt: "Lift between sets: a rest timer counting down from 1:30." },
  { id: "lift-plan", title: "Lift · plan", alt: "Lift's plan: an upper and lower split across the week, with today's movements." },
  { id: "lift-coach", title: "Lift · coach", alt: "Lift's coach saying: your bench has not moved in three weeks. Want to look at it?" },
];

export type StudioScreen = ScreenDef & { surface: "phone"; src: string; width: number; height: number };

/** A PNG's size, from its header: no image library needed. */
function pngSize(buf: Buffer): { width: number; height: number } {
  return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
}

export async function studioScreens(): Promise<StudioScreen[]> {
  return Promise.all(
    DEFS.map(async (def) => {
      const file = path.join(process.cwd(), "public", "screens", `${def.id}.png`);
      return { ...def, surface: "phone" as const, src: `/screens/${def.id}.png`, ...pngSize(await readFile(file)) };
    })
  );
}
