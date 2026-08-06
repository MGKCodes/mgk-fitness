# 0002 — No Strava integration

**Status:** Accepted

## Context

Strava is the obvious integration for a running app, and users would ask for it.
However, Strava's API agreement prohibits using Strava data in connection with
the operation of an AI/ML application, and prohibits uses that compete with
Strava. Runio is an AI coaching app. Integrating would put the product in direct
violation of the terms.

## Decision

**No Strava integration of any kind.** Do not read Strava data, do not write to
Strava, do not offer account linking. Runs from watches and other apps arrive
through **HealthKit** instead.

## Consequences

- No dependency on Strava's API terms or rate limits.
- Third-party device data still reaches Runio via HealthKit, covering the main
  user need (getting existing runs in).
- Feature requests for Strava import/export are **out of scope** and closed with
  a link to this ADR.
