import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  conversationRequired,
  errorCode,
  MAX_BODY_BYTES,
  parseBody,
} from "./request.ts";

Deno.test("a body over the ceiling is refused before it is read", () => {
  const huge = JSON.stringify({
    surface: "chat",
    message: "x".repeat(MAX_BODY_BYTES),
  });
  assertEquals(parseBody(huge), { error: "request_too_large", status: 413 });
});

Deno.test("the ceiling counts bytes, not characters", () => {
  // Three bytes each in UTF-8: a string under the limit in characters but
  // over it in bytes must still be refused.
  const wide = JSON.stringify({ message: "€".repeat(MAX_BODY_BYTES / 2) });
  assert(wide.length < MAX_BODY_BYTES * 2);
  assertEquals(parseBody(wide), { error: "request_too_large", status: 413 });
});

Deno.test("only a JSON object is a body", () => {
  for (const raw of ["", "not json", "null", "[]", "42", '"chat"', "true"]) {
    assertEquals(parseBody(raw), { error: "bad_request", status: 400 }, raw);
  }
  assertEquals(parseBody('{"surface":"chat"}'), { body: { surface: "chat" } });
});

Deno.test("only a Lift chat turn must name its conversation", () => {
  assert(conversationRequired("lift_chat", true, ""));
  assert(!conversationRequired("lift_chat", true, "lift:1-abc"));
  // The three surfaces that answered 400 from 2026-09-01.
  for (const surface of ["lift_intake", "lift_plan", "lift_swap"]) {
    assert(!conversationRequired(surface, true, ""), surface);
  }
  // Run has no memory store here at all.
  assert(!conversationRequired("chat", false, ""));
});

Deno.test("an upstream error is logged as its code, never its message", () => {
  const flagged = JSON.stringify({
    error: {
      code: 403,
      message: "Input was flagged",
      metadata: { flagged_input: "my calf is sore and I feel dizzy" },
    },
  });
  assertEquals(errorCode(flagged), "403");
  assertEquals(
    errorCode({ code: "rate_limited", message: "slow down" }),
    "rate_limited",
  );
  assertEquals(
    errorCode({ type: "invalid_request_error" }),
    "invalid_request_error",
  );
  assertEquals(errorCode({ message: "no code here" }), "no_code");
  assertEquals(errorCode("<html>gateway</html>"), "unparsed");
  assertEquals(errorCode(null), "no_code");
  for (const out of [errorCode(flagged), errorCode({ message: "dizzy" })]) {
    assert(!out.includes("dizzy"), out);
  }
});
