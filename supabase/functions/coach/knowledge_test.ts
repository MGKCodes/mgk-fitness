import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { Knowledge, MAX_GUIDANCE_CHARS, renderGuidance } from "./knowledge.ts";

const rows = [
  { id: "g1", kind: "guidance", title: "Choosing a split", body: "Days do the work." },
  { id: "c1", kind: "claim", title: "Volume drives it", body: "12 to 20 sets." },
];

Deno.test("rows become titled blocks", () => {
  const out = renderGuidance(rows);
  assertStringIncludes(out, "## Choosing a split");
  assertStringIncludes(out, "Days do the work.");
  assertStringIncludes(out, "## Volume drives it");
});

Deno.test("a row missing a title or body is skipped, not half-rendered", () => {
  const out = renderGuidance([
    { id: "x", kind: "guidance", title: "", body: "orphan" },
    { id: "y", kind: "guidance", title: "Kept", body: "  " },
    ...rows,
  ]);
  assertEquals(out.includes("orphan"), false);
  assertEquals(out.includes("Kept"), false);
  assertStringIncludes(out, "Choosing a split");
});

Deno.test("the limit drops whole documents, never half of one", () => {
  // The qualifications are usually in the second half of a claim and the
  // confident part is usually the first, so a truncated one is worse than none.
  const long = { id: "l", kind: "claim", title: "Long", body: "x".repeat(200) };
  const out = renderGuidance([rows[0], long], 120);
  assertStringIncludes(out, "Choosing a split");
  assertEquals(out.includes("Long"), false);
});

Deno.test("nothing at all is an empty string, not an error", () => {
  assertEquals(renderGuidance([]), "");
});

Deno.test("a failed read is empty guidance rather than a failed request", () => {
  // A coach with no house guidance still answers. One that refuses because a
  // reference table was slow does not.
  const k = new Knowledge("http://x", "key", "Bearer t", () =>
    Promise.resolve(new Response("nope", { status: 500 })));
  return k.forApp("lift").then((g) => {
    assertEquals(g, "");
  });
});

Deno.test("a thrown read is empty guidance too", () => {
  const k = new Knowledge("http://x", "key", "Bearer t", () =>
    Promise.reject(new Error("socket")));
  return k.forApp("lift").then((g) => {
    assertEquals(g, "");
  });
});

Deno.test("it asks for shared rows as well as the app's own", async () => {
  // A claim about progressive overload belongs to both coaches, and
  // duplicating it per app is how two copies of one fact drift apart.
  let seen = "";
  const k = new Knowledge("http://x", "key", "Bearer t", (url) => {
    seen = String(url);
    return Promise.resolve(new Response(JSON.stringify(rows), { status: 200 }));
  });
  const out = await k.forApp("lift");
  assertStringIncludes(seen, "app=in.(all,lift)");
  assertStringIncludes(seen, "/rest/v1/knowledge");
  assertStringIncludes(out, "Choosing a split");
});

Deno.test("guidance comes before claims", () => {
  // If the ceiling bites, losing citations beats losing instructions.
  assertEquals(MAX_GUIDANCE_CHARS > 1000, true);
  const k = new Knowledge("http://x", "key", "Bearer t", (url) => {
    assertStringIncludes(String(url), "order=kind.asc");
    return Promise.resolve(new Response("[]", { status: 200 }));
  });
  return k.forApp("lift").then(() => {});
});
