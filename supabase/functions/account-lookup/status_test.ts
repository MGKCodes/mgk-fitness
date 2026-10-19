// Which screen an address leads to, for every kind of account.
//
//     deno test

import { assertEquals } from "jsr:@std/assert@1";

import { readEmail, readFacts, statusOf } from "./status.ts";

const account = (
  confirmed: boolean,
  has_password: boolean,
  providers: string[] = [],
) => ({ exists: true as const, confirmed, has_password, providers });

Deno.test("no account is new", () => {
  assertEquals(statusOf({ exists: false }), "new");
});

Deno.test("a confirmed email account asks for its password", () => {
  assertEquals(statusOf(account(true, true)), "password");
});

Deno.test("a sign-up nobody confirmed is unconfirmed", () => {
  assertEquals(statusOf(account(false, true)), "unconfirmed");
});

Deno.test("an account made with Apple points at Apple", () => {
  assertEquals(statusOf(account(true, false, ["apple"])), "apple");
});

Deno.test("an account made with Google points at Google", () => {
  assertEquals(statusOf(account(true, false, ["google"])), "google");
});

Deno.test("both providers and no password: Apple first", () => {
  assertEquals(statusOf(account(true, false, ["apple", "google"])), "apple");
});

Deno.test("an email account later joined by Google still asks for its password", () => {
  assertEquals(statusOf(account(true, true, ["google"])), "password");
});

Deno.test("a provider account given a password asks for the password", () => {
  // *Set a password instead* (the ADR's point 4) leads here next time.
  assertEquals(statusOf(account(true, true, ["apple"])), "password");
});

Deno.test("a confirmed account with neither falls back to the password path", () => {
  assertEquals(statusOf(account(true, false, [])), "password");
});

Deno.test("an address is trimmed and lower-cased", () => {
  assertEquals(readEmail({ email: "  You@Example.COM " }), "you@example.com");
});

Deno.test("what could never be an address is refused", () => {
  for (
    const body of [
      null,
      "you@example.com",
      {},
      { email: 42 },
      { email: "" },
      { email: "you" },
      { email: "@example.com" },
      { email: "you@" },
      { email: "you@@example.com" },
      { email: "y ou@example.com" },
      { email: `${"a".repeat(320)}@example.com` },
    ]
  ) {
    assertEquals(readEmail(body), null, JSON.stringify(body));
  }
});

Deno.test("the routine's two shapes are read", () => {
  assertEquals(readFacts({ exists: false }), { exists: false });
  assertEquals(
    readFacts({
      exists: true,
      confirmed: true,
      has_password: false,
      providers: ["apple"],
    }),
    account(true, false, ["apple"]),
  );
});

Deno.test("any other shape is an error, never a guess", () => {
  for (
    const value of [
      null,
      [],
      { exists: true },
      { exists: true, confirmed: "yes", has_password: true, providers: [] },
      { exists: true, confirmed: true, has_password: true, providers: [1] },
      { exists: "false" },
    ]
  ) {
    assertEquals(readFacts(value), null, JSON.stringify(value));
  }
});
