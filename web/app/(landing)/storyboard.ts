/** The five stills the film is built from. `design/landing/stills.md` says what each one shows. */
export type Key = "k1" | "k2" | "k3" | "k4" | "k5";

/**
 * One stretch of the film. A hold rests on a still while the page says
 * something; a move is the camera travelling from one still to the next.
 * `screens` is how much scrolling it takes, in viewport heights.
 */
export type Shot =
  | { id: string; kind: "hold"; at: Key; screens: number }
  | { id: string; kind: "move"; from: Key; to: Key; screens: number };

// The whole page's pacing is these seven numbers. A move that feels slow is
// shortened here, not in the component.
export const shots: Shot[] = [
  { id: "above", kind: "hold", at: "k1", screens: 0.75 },
  { id: "s1", kind: "move", from: "k1", to: "k2", screens: 1.5 },
  { id: "track", kind: "hold", at: "k2", screens: 1.75 },
  { id: "s2", kind: "move", from: "k2", to: "k3", screens: 1 },
  { id: "s3", kind: "move", from: "k3", to: "k4", screens: 1.25 },
  { id: "s4", kind: "move", from: "k4", to: "k5", screens: 0.75 },
  { id: "room", kind: "hold", at: "k5", screens: 1.75 },
];

export const screens = shots.reduce((sum, shot) => sum + shot.screens, 0);
