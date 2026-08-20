import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { parse } from "./sync.ts";

const good = `---
id: c1-thing
app: all
kind: claim
title: A thing
confidence: High
last_checked: 2026-08-20
sources:
  - https://example.com/a
  - https://example.com/b
depends_on:
  - SomeClass.member
---

The body.

With two paragraphs.
`;

Deno.test("front matter and body come apart", () => {
  const d = parse(good, "x.md");
  assertEquals(d.id, "c1-thing");
  assertEquals(d.app, "all");
  assertEquals(d.kind, "claim");
  assertEquals(d.sources.length, 2);
  assertEquals(d.depends_on, ["SomeClass.member"]);
  assertEquals(d.body.startsWith("The body."), true);
  assertEquals(d.body.endsWith("two paragraphs."), true);
});

Deno.test("a claim without a date is refused", () => {
  // The whole point of the table is that a claim can be audited. An undated one
  // is folklore, and folklore is what this replaced.
  const undated = good.replace("last_checked: 2026-08-20\n", "");
  assertThrows(() => parse(undated, "x.md"), Error, "last_checked");
});

Deno.test("a claim without sources is refused", () => {
  const unsourced = good.replace(
    "sources:\n  - https://example.com/a\n  - https://example.com/b\n",
    "sources: []\n",
  );
  assertThrows(() => parse(unsourced, "x.md"), Error, "source");
});

Deno.test("guidance needs neither", () => {
  // Coaching prose goes stale against the product rather than the literature,
  // so it is checked differently and does not need a citation.
  const g = `---
id: how-to-say-it
app: lift
kind: guidance
title: How to say it
sources: []
---

Say it kindly.
`;
  const d = parse(g, "g.md");
  assertEquals(d.kind, "guidance");
  assertEquals(d.last_checked, null);
});

Deno.test("an unknown app or kind is refused rather than stored", () => {
  assertThrows(() => parse(good.replace("app: all", "app: liftio"), "x.md"));
  assertThrows(() => parse(good.replace("kind: claim", "kind: notes"), "x.md"));
});

Deno.test("an empty sources list does not swallow the next key", () => {
  // `sources: []` followed by `depends_on:` -- the list-opening branch has to
  // stop claiming lines once a new key appears.
  const d = parse(
    good.replace(
      "sources:\n  - https://example.com/a\n  - https://example.com/b\n",
      "sources: []\n",
    ).replace("kind: claim", "kind: guidance"),
    "x.md",
  );
  assertEquals(d.sources, []);
  assertEquals(d.depends_on, ["SomeClass.member"]);
});

Deno.test("a file with no front matter is a hard error", () => {
  assertThrows(() => parse("just a body", "x.md"), Error, "front matter");
});
