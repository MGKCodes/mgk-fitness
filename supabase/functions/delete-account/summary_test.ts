// When the picture files are swept, against each summary the routine can send.
//
//     deno test

import { assertEquals } from "jsr:@std/assert@1";

import { sweepsProgressPhotos } from "./summary.ts";

Deno.test("a Lift-only deletion sweeps the photos while Run keeps the login", () => {
  assertEquals(
    sweepsProgressPhotos({
      remaining_apps: ["run"],
      shared_deleted: false,
      photos_deleted: true,
      auth_user_deletable: false,
    }),
    true,
  );
});

Deno.test("a Run-only deletion leaves Lift's photos alone", () => {
  assertEquals(
    sweepsProgressPhotos({
      remaining_apps: ["lift"],
      shared_deleted: false,
      photos_deleted: false,
      auth_user_deletable: false,
    }),
    false,
  );
});

Deno.test("a full deletion sweeps them", () => {
  assertEquals(
    sweepsProgressPhotos({
      remaining_apps: [],
      shared_deleted: true,
      photos_deleted: true,
      auth_user_deletable: true,
    }),
    true,
  );
});

Deno.test("a full deletion still sweeps against the routine from before the flag", () => {
  assertEquals(
    sweepsProgressPhotos({
      remaining_apps: [],
      shared_deleted: true,
      auth_user_deletable: true,
    }),
    true,
  );
});

Deno.test("a partial deletion against the old routine sweeps nothing", () => {
  assertEquals(
    sweepsProgressPhotos({ remaining_apps: ["run"], shared_deleted: false }),
    false,
  );
});
