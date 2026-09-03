# 0001 — Liftio is replaced, not relaunched

**Status:** Accepted (2026-08-17)

## Context

`apps/mgk_lift` is a Flutter rewrite of Liftio, which ships on the App Store
today as an Expo/React Native app at **1.4.0** — bundle `com.mgkcodes.liftio`,
App Store id `6759969740`.

The rewrite was scaffolded with `com.mgkcodes.fitness.lift`, matching the suite
convention that `codemagic.yaml` defends at length: a bundle id is permanent, so
it should name the suite rather than the product, leaving the product free to be
renamed later. That reasoning is sound and it is why `mgk_run` is
`com.mgkcodes.fitness.run`.

**This reverses a decision that was already taken.** `README.md` recorded it
plainly: *"this is a new record, not an update. The existing listing gets
retired rather than upgraded... a deliberate call taken while the user count was
small enough to absorb it — the alternative was carrying a name that predates
the suite forever."*

That reasoning was not wrong. It weighed a permanent identifier against a small
user base and chose the identifier, which is the right way round to think about
it. What it did not weigh is that the listing carries more than a name: reviews,
history, search position, and an App Store id already published on
`getliftio.com`. Retiring a live record to avoid an untidy string is paying a
real cost for a cosmetic one.

Three facts decide it the other way:

1. **There is almost nothing to protect on the old build, and it is already
   broken.** `20260806130000_restructure_schemas.sql` moved Liftio's tables out
   of `public`, which the shipped app queries through PostgREST. It has been
   non-functional since 2026-08-07. The migration's own header accepts this,
   recording that there are *two users and both are known*.
2. **The listing itself is still worth having.** It carries the name, the
   history, the reviews, and an App Store id already wired into
   `getliftio.com`.
3. **The data already moved.** `ALTER TABLE ... SET SCHEMA` preserved rows, so
   the cloud history lives in `lift.` and `core.` where the Flutter app reads.
   There is no migration to pay for by staying on the same listing.

## Decision

Ship as **Liftio 2.0.0** on the existing listing.

- iOS bundle id is **`com.mgkcodes.liftio`**, inherited from the shipped app.
- Android `applicationId` and `namespace` match it, even though Play has no
  existing listing to inherit — the two stores should name the same product the
  same way.
- The version goes **1.4.0 → 2.0.0**. A rewrite that changes language, local
  storage and business model is what a major bump is for.

This **deliberately breaks the suite convention for this app only.** `mgk_run`
keeps `com.mgkcodes.fitness.run`; it has no shipped predecessor to inherit from,
so the convention costs it nothing.

## Consequences

- The comment in `codemagic.yaml` explaining suite-named bundle ids is now true
  of Run and not of Lift. Any Lift workflow added there must not copy Run's
  identifier pattern.
- iOS signing reuses Liftio's existing App ID and provisioning rather than
  creating new ones. One less thing to set up, and the same reason the first
  Run build failed — profiles are fetched, not created.
- Existing installs receive 2.0.0 as an update, so it must not assume a fresh
  device. Whether the app restores their cloud history on sign-in is
  **unverified** and tracked in [release-2.0.0.md](../release-2.0.0.md).
- The Play listing is a genuinely new first upload. Nothing to migrate there,
  and no legacy id to inherit — `com.mgkcodes.liftio` is claimed fresh.
- If Lift is ever renamed, the bundle id will name a product that no longer
  exists. That is the cost the suite convention exists to avoid, accepted here
  because an established listing is worth more than a tidy identifier.
