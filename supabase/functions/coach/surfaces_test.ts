// Unit tests for the prompt surfaces.
//
// These are reachable without a server because index.ts holds no prompts: it
// calls `Deno.serve` at load, so anything defined there could only be tested
// through a socket. Everything asserted here is pure — a request body in,
// provider messages out, and the mapping from the model's answer onto the app's
// contract. Run from this directory:
//
//     deno test
//
// (No permissions needed; there is no I/O in surfaces.ts.)

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";

import {
  type Body,
  CHAT_SCHEMA,
  chatIntent,
  chatMessages,
  clamp,
  conversation,
  editRunMessages,
  logRunMessages,
  modelFor,
  PERSONA,
  PROVIDER_ROUTING,
  setGoalMessages,
  summariseMessages,
  SURFACES,
  tierFrom,
} from "./surfaces.ts";
import { SURFACE_NAMES } from "./limits.ts";

const chat = SURFACES.chat;
const summarise = SURFACES.summarise;

function systemOf(messages: { role: string; content: string }[]): string {
  assertEquals(messages[0].role, "system");
  return messages[0].content;
}

const BRIEF = `They are in week 4 of 12 of a 21.1 km block, 55 days out from the
event. This is a build week of about 48 km.

Their last run was yesterday: 8 km at 5:31 /km.`;

// ---- the registry -----------------------------------------------------------

Deno.test("every limited surface has a prompt, and every prompt is limited", () => {
  // The two lists are kept in step by the type system (SURFACES is a
  // Record<Surface, ...>), but a missing entry here would be a runtime 500 on a
  // surface the limiter happily let through, so it is worth asserting.
  for (const name of SURFACE_NAMES) {
    const spec = SURFACES[name];
    assert(spec, `${name} has no prompt`);
    assertEquals(spec.name, name);
    assert(spec.maxTokens > 0, `${name} needs a token budget`);
    assert(typeof spec.schema === "object", `${name} needs a schema`);
  }
  assertEquals(Object.keys(SURFACES).length, SURFACE_NAMES.length);
});

// ---- chat: what we send -----------------------------------------------------

Deno.test("the brief goes into the system prompt exactly as written", () => {
  // Load-bearing. The app renders typed state into prose on purpose, because a
  // model handed a struct recites it back at the runner. Reformatting it here,
  // or serialising it, would undo that.
  const system = systemOf(chatMessages({ brief: BRIEF, message: "hi" }));
  assertStringIncludes(system, BRIEF);
  assert(!system.includes('\\"'), "the brief must not be JSON-encoded");
  assertStringIncludes(system, PERSONA);
});

Deno.test("no brief says so rather than leaving an empty heading", () => {
  const system = systemOf(chatMessages({ message: "hi" }));
  assert(!system.includes("The brief:"), "should not head an absent brief");
  assertStringIncludes(system, "no brief for this runner yet");
});

Deno.test("the coach is told the weekday, not the date", () => {
  // CoachBrief renders everything in relative days ("yesterday", "three days
  // ago") so the coach never quotes a date at the runner. Handing it one here
  // would invite exactly that; the weekday is what "can we move Thursday" needs.
  const system = systemOf(chatMessages({ message: "hi" }));
  assert(
    /Today is (Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\./
      .test(system),
    `expected a weekday, got: ${system.slice(-120)}`,
  );
  assert(
    !/Today is \d{4}-\d{2}-\d{2}/.test(system),
    "the chat prompt must not carry an absolute date",
  );
});

Deno.test("the runner's message is the last turn, after the history", () => {
  const messages = chatMessages({
    brief: BRIEF,
    history: [
      { role: "user", text: "how did last week look" },
      { role: "coach", text: "solid, you hit every session" },
    ],
    message: "can we move Thursday",
  });
  assertEquals(messages.length, 4);
  assertEquals(messages[1], {
    role: "user",
    content: "how did last week look",
  });
  // "coach" is the app's word for it; the provider only knows "assistant".
  assertEquals(messages[2], {
    role: "assistant",
    content: "solid, you hit every session",
  });
  assertEquals(messages[3], { role: "user", content: "can we move Thursday" });
});

Deno.test("a first message with no history is still a well-formed exchange", () => {
  const messages = chatMessages({ brief: BRIEF, message: "hello" });
  assertEquals(messages.length, 2);
  assertEquals(messages[1], { role: "user", content: "hello" });
});

Deno.test("history is capped, so a long conversation cannot grow the prompt for ever", () => {
  // The prompt is the one input the client picks, and it is charged for on
  // every turn. This is what the rolling summary exists to make survivable.
  const history = Array.from({ length: 200 }, (_, i) => ({
    role: i % 2 ? "coach" : "user",
    text: `turn ${i}`,
  }));
  const messages = chatMessages({ brief: BRIEF, history, message: "and now" });
  assertEquals(messages.length, 1 + 20 + 1);
  // The tail is what is kept: the most recent turns, not the oldest.
  assertEquals(messages[1].content, "turn 180");
  assertEquals(messages[20].content, "turn 199");
});

Deno.test("junk turns are dropped rather than sent as empty messages", () => {
  const messages = chatMessages({
    history: [
      null,
      "nope",
      { role: "user" },
      { role: "user", text: "   " },
      { role: "user", text: " real " },
    ],
    message: "ok",
  });
  assertEquals(messages.length, 3);
  assertEquals(messages[1], { role: "user", content: "real" });
});

Deno.test("one enormous turn is clipped, not sent whole", () => {
  const messages = chatMessages({
    history: [{ role: "user", text: "x".repeat(50_000) }],
    message: "y".repeat(50_000),
  });
  assert(messages[1].content.length <= 2001, "a history turn is clipped");
  assert(messages[2].content.length <= 4001, "the message is clipped");
  assert(messages[1].content.endsWith("…"), "clipping is visible to the model");
});

Deno.test("clamp leaves text alone until it is actually too long", () => {
  assertEquals(clamp("short", 10), "short");
  assertEquals(clamp("exactlyten", 10), "exactlyten");
  assertEquals(clamp("elevenchars", 10), "elevenchar…");
});

// ---- chat: the prompt itself ------------------------------------------------

Deno.test("the chat prompt states the rules the surface exists to enforce", () => {
  // Prompt text is the product here. These are the four clauses that stop the
  // chat surface from becoming a second, unvalidated planner.
  const system = systemOf(chatMessages({ brief: BRIEF, message: "hi" }));
  for (
    const clause of [
      "Never recite the brief",
      "Never state a number the brief does not contain",
      "Never write training out",
      "You are not a doctor",
      "adapt_week",
    ]
  ) {
    assertStringIncludes(system, clause);
  }
});

Deno.test("the conversational prompts contain no em dashes", () => {
  // PERSONA forbids them in the coach's voice, and a model copies the
  // punctuation of its own instructions. The generation prompts are exempt:
  // nobody reads a skeleton.
  for (
    const system of [
      systemOf(chatMessages({ brief: "x", message: "hi" })),
      systemOf(
        summariseMessages({ transcript: [{ role: "user", text: "x" }] }),
      ),
    ]
  ) {
    assert(!system.includes("—"), "em dash in a prompt the runner hears");
    assert(!system.includes("–"), "en dash in a prompt the runner hears");
  }
});

// ---- chat: what we accept back ----------------------------------------------

Deno.test("a reply is required, and an empty one is not a reply", () => {
  assert(chat.valid({ reply: "sure", intent: { kind: "none" } }));
  assert(!chat.valid({ reply: "   " }));
  assert(!chat.valid({ reply: 7 }));
  assert(!chat.valid({}));
});

Deno.test("ordinary conversation carries no intent", () => {
  const out = chat.render!({
    reply: "  Nice work on that one.  ",
    intent: { kind: "none", request: null },
  });
  assertEquals(out, { reply: "Nice work on that one.", intent: null });
});

Deno.test("a change request becomes the one intent the app can act on", () => {
  const out = chat.render!({
    reply: "I'll move it to Friday.",
    intent: {
      kind: "adapt_week",
      request: "  move Thursday's threshold to Friday  ",
    },
  });
  assertEquals(out, {
    reply: "I'll move it to Friday.",
    intent: {
      kind: "adapt_week",
      request: "move Thursday's threshold to Friday",
    },
  });
});

Deno.test("anything that is not an actionable intent degrades to conversation", () => {
  // The reply is the valuable part. Failing the whole call over a malformed
  // hint would throw away a good answer the runner can simply ask for again,
  // and the app is guaranteed either a real request or nothing.
  for (
    const intent of [
      null,
      undefined,
      "adapt_week",
      42,
      {},
      { kind: "none", request: "move Thursday" }, // sentinel wins over the text
      { kind: "delete_everything", request: "all of it" }, // not a kind we serve
      { kind: "log_run" }, // nothing to act on
      { kind: "log_run", request: "  " },
      { kind: "adapt_week" }, // nothing to act on
      { kind: "adapt_week", request: "" },
      { kind: "adapt_week", request: "   " },
      { kind: "adapt_week", request: 3 },
    ]
  ) {
    assertEquals(
      chatIntent(intent),
      null,
      JSON.stringify(intent) ?? "undefined",
    );
  }
});

Deno.test("an intent in the app's own shape is accepted too", () => {
  // Belt and braces: the prompt schema uses a "none" sentinel because a
  // nullable object is the corner of structured output providers implement
  // least consistently, but a provider that answers in the wire shape works.
  assertEquals(chatIntent({ kind: "adapt_week", request: "shorten Sunday" }), {
    kind: "adapt_week",
    request: "shorten Sunday",
  });
});

Deno.test("chat request validation refuses a turn with nothing in it", () => {
  const cases: [Body, boolean][] = [
    [{ message: "hi" }, true],
    [{ message: "  hi  " }, true],
    [{ message: "" }, false],
    [{ message: "   " }, false],
    [{ message: null }, false],
    [{}, false],
    [{ brief: BRIEF, history: [] }, false],
  ];
  for (const [body, expected] of cases) {
    assertEquals(
      chat.validRequest!(body),
      expected,
      JSON.stringify(body),
    );
  }
});

// ---- summarise --------------------------------------------------------------

Deno.test("the transcript is handed over as one block, not as turns to continue", () => {
  // Given turns, a model answers the last message. Given a transcript, it works
  // on it. That is the difference between a summary and another chat reply.
  const messages = summariseMessages({
    previous: "They coach kids on Saturdays and run early.",
    transcript: [
      { role: "user", text: "my calf is grumbling again" },
      { role: "coach", text: "keep it easy this week" },
    ],
  });
  assertEquals(messages.length, 2);
  assertEquals(messages[1].role, "user");
  assertStringIncludes(messages[1].content, "They coach kids on Saturdays");
  assertStringIncludes(messages[1].content, "Runner: my calf is grumbling");
  assertStringIncludes(messages[1].content, "Coach: keep it easy this week");
});

Deno.test("a first summary says there is nothing yet rather than nothing at all", () => {
  const messages = summariseMessages({
    previous: null,
    transcript: [{ role: "user", text: "hello" }],
  });
  assertStringIncludes(messages[1].content, "(nothing yet)");
});

Deno.test("the summarise prompt forbids appending and forbids duplicating typed data", () => {
  // The two failure modes this surface is written against: a memory that grows
  // by a line per turn until it is a log, and a memory that keeps its own copy
  // of the goal and the volume until it disagrees with the database.
  const system = systemOf(summariseMessages({
    transcript: [{ role: "user", text: "x" }],
  }));
  assertStringIncludes(system, "Write it again from scratch");
  assertStringIncludes(system, "Do not append");
  assertStringIncludes(system, "Leave out anything the app already stores");
  assertStringIncludes(system, "Three to five plain sentences");
});

Deno.test("a long transcript is capped like the chat history is", () => {
  const transcript = Array.from({ length: 200 }, (_, i) => ({
    role: i % 2 ? "coach" : "user",
    text: `line ${i}`,
  }));
  const body = summariseMessages({ transcript })[1].content;
  assert(!body.includes("line 139"), "the oldest turns are dropped");
  assertStringIncludes(body, "line 140");
  assertStringIncludes(body, "line 199");
});

Deno.test("an empty summary is a legitimate answer", () => {
  // "There is nothing worth remembering about this conversation" is a real
  // outcome, and forcing prose instead would invent memory.
  assert(summarise.valid({ summary: "" }));
  assert(summarise.valid({ summary: "They run before work." }));
  assert(!summarise.valid({ summary: null }));
  assert(!summarise.valid({}));
  assertEquals(summarise.render!({ summary: "  trimmed.  " }), {
    summary: "trimmed.",
  });
});

Deno.test("summarising nothing is refused before it costs anything", () => {
  const cases: [Body, boolean][] = [
    [{ transcript: [{ role: "user", text: "hi" }] }, true],
    [{ transcript: [] }, false],
    [{ transcript: [{ role: "user", text: "  " }] }, false],
    [{ transcript: "not a list" }, false],
    [{ previous: "an old summary" }, false],
  ];
  for (const [body, expected] of cases) {
    assertEquals(summarise.validRequest!(body), expected, JSON.stringify(body));
  }
});

Deno.test("the summary cannot grow without bound", () => {
  // max_tokens is the hard ceiling on a memory that is fed back into every
  // future prompt. A few sentences is the design; this is the backstop.
  assert(summarise.maxTokens <= 512, "a rolling memory must stay small");
});

// ---- shared -----------------------------------------------------------------

Deno.test("conversation normalises roles the app uses and the provider does not", () => {
  assertEquals(
    conversation([
      { role: "coach", text: "a" },
      { role: "assistant", text: "b" },
      { role: "user", text: "c" },
      { role: "system", text: "d" }, // not a role the app may inject
    ], 10),
    [
      { role: "assistant", content: "a" },
      { role: "assistant", content: "b" },
      { role: "user", content: "c" },
      { role: "user", content: "d" },
    ],
  );
});

// ---- model routing ----------------------------------------------------------
//
// The split exists because chat and summarise reach a person with no Dart
// validator in between. The invariant that matters most is the LAST one: unset,
// nothing changes.

function env(vars: Record<string, string>): (k: string) => string | undefined {
  return (k) => vars[k];
}

Deno.test("chat and summarise take COACH_CHAT_MODEL when it is set", () => {
  const get = env({ COACH_MODEL: "cheap", COACH_CHAT_MODEL: "better" });
  assertEquals(modelFor("chat", get), "better");
  assertEquals(modelFor("summarise", get), "better");
});

Deno.test("the validated planning surfaces stay on COACH_MODEL", () => {
  const get = env({ COACH_MODEL: "cheap", COACH_CHAT_MODEL: "better" });
  for (const s of ["intake", "skeleton", "week", "adapt"] as const) {
    assertEquals(modelFor(s, get), "cheap");
  }
});

Deno.test("a blank COACH_CHAT_MODEL is unset, not a model named ''", () => {
  const get = env({ COACH_MODEL: "cheap", COACH_CHAT_MODEL: "   " });
  assertEquals(modelFor("chat", get), "cheap");
});

Deno.test("with COACH_CHAT_MODEL unset every surface runs on COACH_MODEL", () => {
  const get = env({ COACH_MODEL: "cheap" });
  for (const s of SURFACE_NAMES) assertEquals(modelFor(s, get), "cheap");
});

Deno.test("exactly chat and summarise are human-facing", () => {
  assertEquals(
    SURFACE_NAMES.filter((s) => SURFACES[s].humanFacing),
    ["chat", "summarise"],
  );
});

// ---- tiers ------------------------------------------------------------------
//
// The safety property is the fallback DIRECTION. Anything unrecognised must
// resolve to the cheapest tier, because the alternative is a forged or buggy
// request billing at the dearest model's rate.

Deno.test("a known tier is read, anything else is free", () => {
  assertEquals(tierFrom("free"), "free");
  assertEquals(tierFrom("standard"), "standard");
  assertEquals(tierFrom("sharp"), "sharp");
  for (
    const junk of [undefined, null, "", "SHARP", "premium", 3, {}, ["sharp"]]
  ) {
    assertEquals(
      tierFrom(junk),
      "free",
      `${JSON.stringify(junk)} must be free`,
    );
  }
});

Deno.test("each tier takes its own chat model", () => {
  const get = env({
    COACH_MODEL: "cheap",
    COACH_CHAT_MODEL_FREE: "free-chat",
    COACH_CHAT_MODEL_STANDARD: "standard-chat",
    COACH_CHAT_MODEL_SHARP: "sharp-chat",
  });
  assertEquals(modelFor("chat", get, "free"), "free-chat");
  assertEquals(modelFor("chat", get, "standard"), "standard-chat");
  assertEquals(modelFor("chat", get, "sharp"), "sharp-chat");
  assertEquals(modelFor("summarise", get, "sharp"), "sharp-chat");
});

Deno.test("tier never moves the validated planning surfaces", () => {
  // There is nothing to sell on the planning surfaces: the validator, not the
  // price of the model, is what makes a plan safe.
  const get = env({
    COACH_MODEL: "cheap",
    COACH_CHAT_MODEL_SHARP: "expensive",
  });
  for (const s of ["intake", "skeleton", "week", "adapt"] as const) {
    assertEquals(modelFor(s, get, "sharp"), "cheap");
  }
});

Deno.test("an unset tier model falls back, never upward", () => {
  const get = env({ COACH_MODEL: "cheap", COACH_CHAT_MODEL: "shared-chat" });
  // No per-tier model configured: everyone gets the shared chat model, and a
  // sharp runner is never silently promoted past it.
  assertEquals(modelFor("chat", get, "sharp"), "shared-chat");
  assertEquals(modelFor("chat", get, "free"), "shared-chat");

  const only = env({ COACH_MODEL: "cheap" });
  for (const t of ["free", "standard", "sharp"] as const) {
    assertEquals(modelFor("chat", only, t), "cheap");
  }
});

Deno.test("defaulting the tier argument is the same as passing free", () => {
  const get = env({
    COACH_MODEL: "cheap",
    COACH_CHAT_MODEL_FREE: "free-chat",
    COACH_CHAT_MODEL_SHARP: "sharp-chat",
  });
  assertEquals(modelFor("chat", get), modelFor("chat", get, "free"));
});

// ---- the development model override -----------------------------------------
//
// A loosening, so the tests are about what it REFUSES. The production state is
// the allowlist being unset, and that must ignore the client completely.

Deno.test("with no allowlist the client cannot name a model", () => {
  const get = env({ COACH_MODEL: "cheap" });
  assertEquals(modelFor("chat", get, "free", "anything/at-all"), "cheap");
  assertEquals(modelFor("skeleton", get, "free", "anything/at-all"), "cheap");
});

Deno.test("only a model on the list is honoured", () => {
  const get = env({
    COACH_MODEL: "cheap",
    COACH_MODEL_ALLOWLIST: "a/one, b/two ,c/three",
  });
  assertEquals(modelFor("chat", get, "free", "b/two"), "b/two");
  // Whitespace around list entries is trimmed, so a tidy secret still matches.
  assertEquals(modelFor("chat", get, "free", "c/three"), "c/three");
  // Not on the list: ignored, falls back to configuration.
  assertEquals(modelFor("chat", get, "free", "d/four"), "cheap");
  // Membership is verbatim, never a prefix or substring match.
  assertEquals(modelFor("chat", get, "free", "a/on"), "cheap");
  assertEquals(modelFor("chat", get, "free", "a/one-turbo"), "cheap");
});

Deno.test("a non-string or empty request is ignored", () => {
  const get = env({ COACH_MODEL: "cheap", COACH_MODEL_ALLOWLIST: "a/one" });
  for (const junk of [undefined, null, "", "   ", 7, {}, ["a/one"]]) {
    assertEquals(modelFor("chat", get, "free", junk), "cheap");
  }
});

Deno.test("the override applies to every surface, so models can be compared", () => {
  const get = env({
    COACH_MODEL: "cheap",
    COACH_CHAT_MODEL: "chatty",
    COACH_MODEL_ALLOWLIST: "x/candidate",
  });
  for (const s of SURFACE_NAMES) {
    assertEquals(modelFor(s, get, "free", "x/candidate"), "x/candidate");
  }
});

Deno.test("an allowlisted model outranks the tier model", () => {
  // Deliberate: while evaluating, what you asked for is what you get. It is
  // why the Sharp model must never be put on the list.
  const get = env({
    COACH_MODEL: "cheap",
    COACH_CHAT_MODEL_SHARP: "expensive",
    COACH_MODEL_ALLOWLIST: "x/candidate",
  });
  assertEquals(modelFor("chat", get, "sharp", "x/candidate"), "x/candidate");
});

// ---- log_run ----------------------------------------------------------------
//
// A separate surface rather than letting chat return numbers: chat's job is
// prose and an intent in plain words, and what the runner said gets turned into
// fields somewhere the result can be validated (ADR-0016).

Deno.test("log_run is told to read, not to coach", () => {
  const system = systemOf(logRunMessages({ request: "ran 5k this morning" }));
  assertStringIncludes(system, "Extract only what they actually said");
  assertStringIncludes(system, "You are reading, not coaching");
  // The failure this prompt exists to prevent: an invented number is
  // indistinguishable from a reported one once it is in the log.
  assertStringIncludes(system, "Do NOT infer a distance from a");
  assertStringIncludes(system, "METRES");
  assertStringIncludes(system, "SECONDS");
});

Deno.test('log_run is given the date, so "this morning" can be resolved', () => {
  const system = systemOf(logRunMessages({ request: "ran this morning" }));
  assert(
    /Today is \d{4}-\d{2}-\d{2}/.test(system),
    "needs an absolute date to anchor a relative one",
  );
});

Deno.test("the runner's words are the whole user message", () => {
  const messages = logRunMessages({ request: "5k in 26 minutes, felt easy" });
  assertEquals(messages.length, 2);
  assertEquals(messages[1], {
    role: "user",
    content: "5k in 26 minutes, felt easy",
  });
});

Deno.test("nothing to read is refused before it costs a call", () => {
  const spec = SURFACES.log_run;
  assertEquals(spec.validRequest!({ request: "   " }), false);
  assertEquals(spec.validRequest!({}), false);
  assertEquals(spec.validRequest!({ request: "ran 5k" }), true);
});

Deno.test("log_run stays on COACH_MODEL, being an extraction", () => {
  // Reading a distance out of a sentence does not need the model that holds a
  // conversation, and this surface never reaches the runner directly.
  assertEquals(SURFACES.log_run.humanFacing, undefined);
  const get = env({ COACH_MODEL: "cheap", COACH_CHAT_MODEL: "dear" });
  assertEquals(modelFor("log_run", get), "cheap");
});

Deno.test("every field is optional, because people do not talk in fields", () => {
  // "I ran for about forty minutes" has no distance, and that is a draft with a
  // hole in it rather than an error. RunDraft decides whether the hole matters.
  const schema = SURFACES.log_run.schema as Record<string, unknown>;
  const props = schema.properties as Record<string, Record<string, unknown>>;
  for (
    const field of ["distance_meters", "duration_seconds", "when", "notes"]
  ) {
    const type = props[field].type as string[];
    assert(type.includes("null"), `${field} must accept null`);
  }
});

Deno.test('intake is given the date, so "in November" can be resolved', () => {
  // The surface that turns "Berlin in November" into a YYYY-MM-DD had no year
  // to count from. It guessed one in the past, the client's sanity check
  // rejected the date for not being in the future, and intake could never
  // complete — the coach said "review the details on the next screen" and no
  // next screen appeared. `log_run` has had this anchor all along.
  const system = systemOf(
    SURFACES.intake.messages({ slots: {}, missing: [], history: [] } as Body),
  );
  assert(
    /Today is \d{4}-\d{2}-\d{2}/.test(system),
    "needs an absolute date to anchor a relative one",
  );
});

Deno.test("intake asks which weekdays, not only how many", () => {
  // A plan is laid out on named days, so `days_per_week` alone cannot be turned
  // into a week. The schema has carried `available_weekdays` all along; nothing
  // asked the runner for it, so the confirmation screen opened with no days
  // selected and its build button silently did nothing.
  const system = systemOf(
    SURFACES.intake.messages({ slots: {}, missing: [], history: [] } as Body),
  );
  assertStringIncludes(system, "which weekdays");
});

Deno.test("chat may raise a log_run intent, for a run already done", () => {
  const schema = CHAT_SCHEMA;
  const kinds = ((schema.properties as Record<string, Record<string, unknown>>)
    .intent.properties as Record<string, Record<string, unknown>>).kind.enum;
  assertEquals(kinds, [
    "none",
    "adapt_week",
    "log_run",
    "edit_run",
    "set_goal",
  ]);
});

Deno.test("chat is told not to claim a run is logged before it is", () => {
  // The confirmation is the whole mechanism. A coach that says "logged it"
  // and then shows a card asking permission has already lied.
  const system = systemOf(chatMessages({ message: "hi" }));
  assertStringIncludes(system, "do not say you have logged it");
  assertStringIncludes(system, "a suggestion the runner");
  // And only for a run that happened: "I'll do 5k tomorrow" is a plan.
  assertStringIncludes(system, "Only for a run that has already happened");
});

Deno.test("every acting intent is told not to claim it is already done", () => {
  // Regression, found in the browser rather than here: edit_run was added with
  // the routing and the schema and without this line, and the very first live
  // correction came back "I have updated that run to your actual distance" —
  // above a card still asking permission to make the change.
  const system = systemOf(chatMessages({ message: "hi" }));
  assertStringIncludes(system, "do not say you have changed it");
  assertStringIncludes(system, "not as something already done"); // adapt_week
});

Deno.test("chatIntent carries every routable kind, not just the first one", () => {
  // Regression. This filter hard-coded "adapt_week", so log_run's first live
  // outing looked like a model refusing to follow the prompt when in fact the
  // model was right and the render step was throwing the answer away.
  assertEquals(
    chatIntent({ kind: "log_run", request: "5k in 26 minutes this morning" }),
    { kind: "log_run", request: "5k in 26 minutes this morning" },
  );
  assertEquals(chatIntent({ kind: "adapt_week", request: "move Thursday" }), {
    kind: "adapt_week",
    request: "move Thursday",
  });
});

Deno.test("the routable kinds match the enum the model is offered", () => {
  // The two drifting apart is exactly how the bug above happened: the schema
  // let the model say log_run and nothing downstream would accept it.
  const kinds = ((CHAT_SCHEMA.properties as Record<
    string,
    Record<
      string,
      unknown
    >
  >).intent.properties as Record<string, Record<string, unknown>>).kind
    .enum as string[];
  for (const kind of kinds) {
    if (kind === "none") continue;
    assertEquals(
      chatIntent({ kind, request: "something" })?.kind,
      kind,
      `${kind} is offered to the model but cannot be routed`,
    );
  }
});

// ---- edit_run ---------------------------------------------------------------

Deno.test("edit_run refuses to guess which run, and says why", () => {
  const system = systemOf(editRunMessages({ request: "that was 6k" }));
  // The failure this exists to prevent: a guessed day rewrites a run the
  // runner never mentioned, and the log looks perfectly ordinary afterwards.
  assertStringIncludes(system, "leave it null rather than guessing");
  assertStringIncludes(system, "This surface only edits");
  assert(
    /Today is \d{4}-\d{2}-\d{2}/.test(system),
    "needs an absolute date to resolve a relative one",
  );
});

Deno.test("edit_run changes carry only what was restated", () => {
  // null means "as it was", so correcting a distance must not resend the
  // duration and quietly overwrite it with the model's recollection.
  const schema = SURFACES.edit_run.schema as Record<string, unknown>;
  const props = schema.properties as Record<string, Record<string, unknown>>;
  const changes = props.changes.properties as Record<
    string,
    Record<string, unknown>
  >;
  for (const field of Object.keys(changes)) {
    assert(
      (changes[field].type as string[]).includes("null"),
      `${field} must accept null`,
    );
  }
});

Deno.test("chat can tell a correction from a new run", () => {
  const system = systemOf(chatMessages({ message: "hi" }));
  assertStringIncludes(system, '"edit_run"');
  // Naming the cost, because the model has to choose between two intents that
  // look alike.
  assertStringIncludes(system, "corrections, not new runs");
});

Deno.test("edit_run stays on COACH_MODEL and never reaches the runner", () => {
  assertEquals(SURFACES.edit_run.humanFacing, undefined);
  const get = env({ COACH_MODEL: "cheap", COACH_CHAT_MODEL: "dear" });
  assertEquals(modelFor("edit_run", get), "cheap");
});

// ---- set_goal ---------------------------------------------------------------

Deno.test("set_goal is offered to the model and can be routed", () => {
  assertEquals(
    chatIntent({
      kind: "set_goal",
      request: "I'm doing Manchester on 5 April",
    }),
    { kind: "set_goal", request: "I'm doing Manchester on 5 April" },
  );
});

Deno.test("the chat prompt says a goal change replaces the plan", () => {
  // The runner is approving the loss of a block, not a tweak to one. A prompt
  // that lets the coach raise this casually is a prompt that throws away
  // sixteen weeks on a maybe.
  const system = systemOf(chatMessages({ message: "hi" }));
  assertStringIncludes(system, "set_goal");
  assertStringIncludes(system, "it replaces it");
  // And the same no-false-claim rule the other acting intents carry. Its own
  // paragraph, at the front, because buried at the end of the careful-with-this
  // paragraph the model ignored it: the first live set_goal came back "I have
  // updated your goal" above a card still asking permission.
  assertStringIncludes(system, "Do NOT say you have set it");
  assertStringIncludes(system, "not what you have done");
});

Deno.test("the chat prompt keeps thinking aloud out of set_goal", () => {
  // "I might do a marathon next year" is not a decision, and acting on it
  // would supersede a plan the runner never agreed to lose.
  const system = systemOf(chatMessages({ message: "hi" }));
  assertStringIncludes(system, "have actually decided");
});

Deno.test("set_goal reads a target and nothing else", () => {
  const system = systemOf(setGoalMessages({ request: "half in October" }));
  assertStringIncludes(system, "goal_distance_meters");
  assertStringIncludes(system, "METRES");
  // The distances it must not have to guess at.
  assertStringIncludes(system, "42195");
  assertStringIncludes(system, "21097");
  assertStringIncludes(system, "You are reading, not coaching");
  // An absolute date, unlike chat: resolving "April" needs to know the year.
  assert(/Today is \d{4}-\d{2}-\d{2}/.test(system));
});

Deno.test("set_goal is told not to invent a distance it does not know", () => {
  // A guessed race distance is indistinguishable from a reported one once the
  // plan is built on it.
  const system = systemOf(setGoalMessages({ request: "the Snowdonia race" }));
  assertStringIncludes(system, "leave this null rather than guessing");
});

Deno.test("clearing a goal is distinct from not restating one", () => {
  // The load-bearing distinction in this schema. Null means "unchanged", so
  // without a separate flag "move the race to May" and "I'm stopping" would
  // arrive identically, and one of them wipes the block.
  const system = systemOf(setGoalMessages({ request: "I'm done with it" }));
  assertStringIncludes(system, "clears_goal");
  assertStringIncludes(system, "different from a null distance");

  const schema = SURFACES.set_goal.schema as Record<string, unknown>;
  const props = schema.properties as Record<string, Record<string, unknown>>;
  assertEquals(props.clears_goal.type, "boolean");
  // The other two accept null; this one never does, so "absent" cannot be
  // mistaken for "stop".
  assert(!JSON.stringify(props.clears_goal.type).includes("null"));
});

Deno.test("set_goal refuses an empty request rather than paying for nothing", () => {
  const spec = SURFACES.set_goal;
  assertEquals(spec.validRequest?.({ request: "   " } as Body), false);
  assertEquals(spec.validRequest?.({} as Body), false);
  assertEquals(spec.validRequest?.({ request: "a marathon" } as Body), true);
});

Deno.test("set_goal is rate limited hardest of the acting surfaces", () => {
  // Not a cost limit: every accepted one supersedes a block. Four legitimate
  // changes of mind in an hour is a loop, not a runner.
  assertEquals(SURFACES.set_goal.maxTokens, 256);
});

// ---- provider routing -------------------------------------------------------

Deno.test("special-category data is never routed to a provider that may train", () => {
  // OpenRouter defaults `data_collection` to "allow", which permits providers
  // that may train on the request. The bodies going through here carry injury
  // notes, symptoms, and whatever the runner typed to their coach.
  //
  // This test exists because the flag lived inline in index.ts, which calls
  // Deno.serve at module scope and therefore cannot be imported or tested. One
  // deletion in a refactor and every test would still pass, CI would stay
  // green, and the data would quietly start being trained on. Three bugs of
  // exactly that shape were found in this codebase in a single week.
  assertEquals(PROVIDER_ROUTING.data_collection, "deny");
});

Deno.test("routing still demands endpoints that enforce the schema", () => {
  // A provider that silently drops `response_format` returns prose the parser
  // rejects, which reads as a model failing to follow its prompt and is not.
  assertEquals(PROVIDER_ROUTING.require_parameters, true);
});

Deno.test("routing carries nothing beyond the two flags it is meant to", () => {
  // A guard on scope rather than on values: this object is sent to a third
  // party on every request, so anything added to it should be a decision
  // someone made rather than a field that arrived.
  assertEquals(Object.keys(PROVIDER_ROUTING).sort(), [
    "data_collection",
    "require_parameters",
  ]);
});
