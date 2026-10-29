// Unit tests for the server's consent check.
//
// The direction that matters is the one that sends health data: every shape
// that is not a clear, current yes must read as no.
//
//     deno test

import { assert, assertEquals } from "jsr:@std/assert@1";

import { AI_CONSENT_VERSION, consentChecked, hasAiConsent } from "./consent.ts";

const user = (meta: unknown) => ({ id: "u1", user_metadata: meta });
const yes = { version: 1, at: "2026-10-02T09:15:00.000Z" };

Deno.test("a current yes on the account is a yes", () => {
  assert(hasAiConsent("run", user({ run_ai_consent: yes })));
  // A newer version than the server knows still answers today's question,
  // as `isCurrent` reads it on the phone.
  assert(hasAiConsent("run", user({ run_ai_consent: { ...yes, version: 2 } })));
});

Deno.test("no answer, or a withdrawn one, is a no", () => {
  // Withdrawal removes the key, so these are the same case.
  assertEquals(hasAiConsent("run", user({})), false);
  assertEquals(hasAiConsent("run", user({ run_intro_seen: true })), false);
  assertEquals(hasAiConsent("run", user(null)), false);
  assertEquals(hasAiConsent("run", { id: "u1" }), false);
  assertEquals(hasAiConsent("run", null), false);
  // Version 0 only ever lives on the phone, but if it reached the account it
  // must not read as agreement.
  assertEquals(
    hasAiConsent("run", user({ run_ai_consent: { ...yes, version: 0 } })),
    false,
  );
});

Deno.test("an older version asks again", () => {
  assertEquals(AI_CONSENT_VERSION, 1, "raise this with kAiConsentVersion");
  assertEquals(
    hasAiConsent("run", user({ run_ai_consent: { ...yes, version: 0.5 } })),
    false,
  );
});

Deno.test("anything unreadable is a no", () => {
  for (
    const bad of [
      true,
      "yes",
      1,
      [yes],
      { version: "1", at: yes.at },
      { version: 1 },
      { version: 1, at: "not a date" },
      { version: Number.NaN, at: yes.at },
      { at: yes.at },
    ]
  ) {
    assertEquals(
      hasAiConsent("run", user({ run_ai_consent: bad })),
      false,
      JSON.stringify(bad),
    );
  }
});

Deno.test("agreeing to one app's coach is not agreeing to the other's", () => {
  // Each app asks its own question and keeps its own key, so a yes to Run's
  // coach opens nothing in Lift's, and the reverse.
  assertEquals(hasAiConsent("lift", user({ run_ai_consent: yes })), false);
  assertEquals(hasAiConsent("run", user({ lift_ai_consent: yes })), false);
  assert(
    hasAiConsent("lift", user({ run_ai_consent: yes, lift_ai_consent: yes })),
  );
});

Deno.test("both apps are checked", () => {
  assert(consentChecked("run"));
  // From Lift 2.0.1 (issue #10). Before it, Lift wrote no answer to read.
  assert(consentChecked("lift"));
});

Deno.test("Lift reads its answer by the same rule as Run", () => {
  assert(hasAiConsent("lift", user({ lift_ai_consent: yes })));
  assertEquals(hasAiConsent("lift", user({})), false);
  assertEquals(
    hasAiConsent("lift", user({ lift_ai_consent: { ...yes, version: 0 } })),
    false,
  );
  assertEquals(
    hasAiConsent("lift", user({ lift_ai_consent: { version: 1 } })),
    false,
  );
});
