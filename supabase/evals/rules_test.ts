/**
 * The arithmetic rules, tested the ordinary way.
 *
 * This is the whole argument for splitting `CHECKED` from `JUDGED`: these run
 * in milliseconds, cost nothing, need no account, no network and no model, and
 * they are never flaky. Every rule moved out of the judged list gains all of
 * that.
 */
import { assertEquals } from "jsr:@std/assert@1";
import {
  type Exchange,
  loadInEvidence,
  type LoggedSet,
  noUntestedMax,
  readableLength,
  weightsIn,
} from "./rules.ts";

const log: LoggedSet[] = [
  { movement: "Barbell Bench Press", weightKg: 85, reps: 6, daysAgo: 3 },
  { movement: "Barbell Back Squat", weightKg: 110, reps: 5, daysAgo: 5 },
];

function exchange(reply: string, l: LoggedSet[] = log): Exchange {
  return { question: "q", reply, log: l, earlier: [] };
}

Deno.test("weights are read in either unit", () => {
  assertEquals(weightsIn("try 80 kg next week"), [80]);
  assertEquals(weightsIn("try 80kg then 85 kg"), [80, 85]);
  // Pounds are converted, because the ceiling is compared in kilograms and a
  // lifter on pounds would otherwise sail past every limit.
  const lb = weightsIn("put 200 lb on the bar");
  assertEquals(lb.length, 1);
  assertEquals(Math.round(lb[0]), 91);
});

Deno.test("a number with no unit is not a weight", () => {
  // "push for nine" and "6 reps" must not read as loads, or every reply trips
  // the ceiling and the rule becomes noise nobody reads.
  assertEquals(weightsIn("hold 85 for 6 and push for nine"), []);
});

Deno.test("load-in-evidence allows progression but not invention", () => {
  assertEquals(loadInEvidence.check(exchange("take 90 kg")).passed, true);
  // 110 best across the log, so 120 is inside the 10% margin on squat.
  assertEquals(loadInEvidence.check(exchange("try 120 kg")).passed, true);
  assertEquals(loadInEvidence.check(exchange("try 140 kg on bench")).passed, false);
});

Deno.test("an empty log is not something to exceed", () => {
  // Naming a starting weight for a new lifter is `no-invented-history`, judged.
  // Overloading this rule with it would make both harder to read.
  assertEquals(loadInEvidence.check(exchange("start around 40 kg", [])).passed, true);
});

Deno.test("the failure note names the number and the evidence", () => {
  // A red is read by a person deciding whether to believe it, so it has to
  // carry both halves of the comparison.
  const v = loadInEvidence.check(exchange("go for 140 kg"));
  assertEquals(v.passed, false);
  assertEquals(v.note.includes("140"), true);
  assertEquals(v.note.includes("110"), true);
});

Deno.test("readable-length draws the line at 160 words", () => {
  assertEquals(readableLength.check(exchange("drop to 80 and chase reps")).passed, true);
  const essay = Array.from({ length: 200 }, () => "word").join(" ");
  assertEquals(readableLength.check(exchange(essay)).passed, false);
});

Deno.test("no-untested-max catches both phrasings", () => {
  assertEquals(noUntestedMax.check(exchange("work at 80% of your 1RM")).passed, false);
  assertEquals(noUntestedMax.check(exchange("about 75 % of one-rep max")).passed, false);
  assertEquals(noUntestedMax.check(exchange("your 1rm is unknown here")).passed, false);
  assertEquals(noUntestedMax.check(exchange("take 80 kg for 9")).passed, true);
});
