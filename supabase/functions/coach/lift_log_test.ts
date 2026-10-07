// Unit tests for the lifting log the coach is handed.
//
// Two things are being protected. One is that a warm-up never reaches the
// coach as a top set, because everything it says afterwards is derived from
// what it thinks the lifter can lift. The other is that the read is scoped by
// RLS rather than by this file.
//
//     deno test

import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  LiftLog,
  readLiftPlan,
  renderLiftLog,
  renderLiftPlan,
} from "./lift_log.ts";

function session(
  name: string,
  startedAt: string,
  exercises: unknown[],
): Record<string, unknown> {
  return { name, started_at: startedAt, exercises };
}

const working = (weight: number, reps: number) => ({
  reps,
  weight_kg: weight,
  set_type: "working",
  is_completed: true,
});

// ---- rendering --------------------------------------------------------------

Deno.test("a session renders as a date, a name, and its working sets", () => {
  assertEquals(
    renderLiftLog([
      session("Push", "2026-08-05T18:30:00+00:00", [
        { name: "Bench press", sets: [working(80, 5), working(82.5, 3)] },
      ]),
    ]),
    "2026-08-05 Push\n  Bench press: 80kg x5, 82.5kg x3",
  );
});

Deno.test("warm-ups and unticked sets are not training", () => {
  // The definition of "counts" has to match the app's, because a coach that
  // reads a warm-up as a top set will prescribe from it.
  assertEquals(
    renderLiftLog([
      session("Push", "2026-08-05T18:30:00Z", [
        {
          name: "Bench press",
          sets: [
            { ...working(40, 10), set_type: "warmup" },
            { ...working(80, 5), is_completed: false },
            working(80, 5),
          ],
        },
      ]),
    ]),
    "2026-08-05 Push\n  Bench press: 80kg x5",
  );
});

Deno.test("a session with nothing that counts is dropped entirely", () => {
  // Not listed with an empty body. An abandoned session is not a fact about
  // someone's training, and a model handed a run of them will find a pattern.
  assertEquals(
    renderLiftLog([
      session("Push", "2026-08-05T18:30:00Z", [
        {
          name: "Bench press",
          sets: [{ ...working(40, 10), set_type: "warmup" }],
        },
      ]),
      session("Pull", "2026-08-02T18:30:00Z", [
        { name: "Deadlift", sets: [working(140, 5)] },
      ]),
    ]),
    "2026-08-02 Pull\n  Deadlift: 140kg x5",
  );
});

Deno.test("a zero weight is bodyweight, not a failure to load the bar", () => {
  // `lift.sets.weight_kg` defaults to 0 and that is how a chin-up is stored.
  assertEquals(
    renderLiftLog([
      session("Pull", "2026-08-02T18:30:00Z", [
        { name: "Chin-up", sets: [working(0, 8)] },
      ]),
    ]),
    "2026-08-02 Pull\n  Chin-up: bodyweight x8",
  );
});

Deno.test("an unnamed session still renders its date and its sets", () => {
  assertEquals(
    renderLiftLog([
      session("", "2026-08-02T18:30:00Z", [
        { name: "Squat", sets: [working(100, 5)] },
      ]),
    ]),
    "2026-08-02\n  Squat: 100kg x5",
  );
});

Deno.test("malformed rows are dropped rather than rendered as nulls", () => {
  // Everything here has arrived over the wire. A "nullkg xnull" in the prompt
  // is a number the model will happily reason from.
  assertEquals(renderLiftLog(null), "");
  assertEquals(renderLiftLog("nope"), "");
  assertEquals(renderLiftLog([null, 3, "x"]), "");
  assertEquals(
    renderLiftLog([
      session("Push", "2026-08-05T18:30:00Z", [
        { name: "Bench press", sets: [{ ...working(80, 5), weight_kg: null }] },
      ]),
    ]),
    "2026-08-05 Push\n  Bench press: bodyweight x5",
  );
});

// ---- the read ---------------------------------------------------------------

Deno.test("the log is read as the caller, in the lift schema", () => {
  // The Authorization header is the CALLER's, not the service key: RLS decides
  // which sessions the coach can see, and a coach that can read somebody
  // else's log is one bypass away from being the worst bug in the product.
  let seen: { url: string; headers: Headers } | null = null;
  const log = new LiftLog("https://db", "anon-key", (url, init) => {
    seen = { url: String(url), headers: new Headers(init?.headers) };
    return Promise.resolve(
      new Response(
        JSON.stringify([
          session("Push", "2026-08-05T18:30:00Z", [
            { name: "Bench press", sets: [working(80, 5)] },
          ]),
        ]),
        { status: 200 },
      ),
    );
  });

  return log.recent("Bearer caller-jwt").then((rendered) => {
    assertEquals(rendered, "2026-08-05 Push\n  Bench press: 80kg x5");
    const call = seen!;
    assertEquals(call.headers.get("Authorization"), "Bearer caller-jwt");
    assertEquals(call.headers.get("apikey"), "anon-key");
    assertEquals(call.headers.get("Accept-Profile"), "lift");
    // Deleted sessions and templates are not training either.
    assert(call.url.includes("deleted_at=is.null"), call.url);
    assert(call.url.includes("is_template=eq.false"), call.url);
    assert(call.url.includes("order=started_at.desc"), call.url);
  });
});

Deno.test("a failed log read answers without the log rather than refusing", () => {
  // The coach can still say something useful, and the prompt tells it to ask
  // rather than assume when it has nothing. Refusing the turn would be worse.
  const failing = new LiftLog(
    "https://db",
    "anon-key",
    () => Promise.resolve(new Response("nope", { status: 400 })),
  );
  const throwing = new LiftLog(
    "https://db",
    "anon-key",
    () => Promise.reject(new Error("socket")),
  );

  return Promise.all([
    failing.recent("Bearer caller-jwt"),
    throwing.recent("Bearer caller-jwt"),
  ]).then(([a, b]) => {
    assertEquals(a, "");
    assertEquals(b, "");
  });
});

// ---- the active plan -------------------------------------------------------

Deno.test("the plan reads as its name, its days and what they said", () => {
  const out = renderLiftPlan([{
    split: "Upper / Lower",
    day_order: ["Upper", "Lower", "Upper", "Lower"],
    available_weekdays: [1, 2, 4, 5],
    goal: "Bench 100kg",
    equipment: "A full gym",
    injury_notes: "Left shoulder, no overhead pressing",
  }]);
  assertEquals(
    out,
    "Plan: Upper / Lower on Mon, Tue, Thu, Fri (Upper, Lower, Upper, Lower)\n" +
      "Training for: Bench 100kg\n" +
      "Trains with: A full gym\n" +
      "Working around: Left shoulder, no overhead pressing",
  );
});

Deno.test("a declined answer is left out, not printed as null", () => {
  const out = renderLiftPlan([{
    split: "Full body",
    day_order: [],
    available_weekdays: [1, 3, 5],
    goal: null,
    equipment: null,
    injury_notes: null,
  }]);
  assertEquals(out, "Plan: Full body on Mon, Wed, Fri");
});

Deno.test("no plan is nothing at all", () => {
  assertEquals(renderLiftPlan([]), "");
  assertEquals(renderLiftPlan(null), "");
});

Deno.test("the plan is read as the caller, active only", async () => {
  let seen: Request | undefined;
  const fake = (input: RequestInfo | URL, init?: RequestInit) => {
    seen = new Request(input, init);
    return Promise.resolve(
      new Response(JSON.stringify([{ split: "Push / Pull / Legs" }])),
    );
  };
  const out = await readLiftPlan(
    "https://x.supabase.co",
    "anon",
    "Bearer user-jwt",
    fake as typeof fetch,
  );
  assertEquals(out, "Plan: Push / Pull / Legs");
  assert(seen);
  assertEquals(seen.headers.get("Authorization"), "Bearer user-jwt");
  assertEquals(seen.headers.get("Accept-Profile"), "lift");
  assert(seen.url.includes("status=eq.active"));
});

Deno.test("a plan that will not load is no plan, not a refused turn", async () => {
  const fake = () => Promise.resolve(new Response("nope", { status: 500 }));
  assertEquals(
    await readLiftPlan("https://x", "anon", "Bearer t", fake as typeof fetch),
    "",
  );
});
