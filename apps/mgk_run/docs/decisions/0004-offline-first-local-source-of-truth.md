# 0004 — Offline-first; local store is the source of truth for live runs

**Status:** Accepted

## Context

A run is recorded outdoors, often with intermittent or no connectivity, and must
survive an app crash or OS termination mid-run. Treating the server as the
source of truth for an in-progress run would risk data loss exactly when it
hurts most, and would make the app feel fragile.

## Decision

Runio is **offline-first**. The on-device store (Drift/SQLite) is the **source
of truth for a run in progress**. Every location point is **persisted to local
storage as it arrives** — a run is never held only in memory. Supabase is a
backup and cross-device store, synced when a connection is available.

The same rule holds for the **training plan**: it is owned by the on-device
database, read locally, and written locally before the UI reflects the change.
Supabase mirrors it. So alongside run recording, the plan and the runner's
**session marks** (done / skipped) are authored offline — a runner can finish a
session in a tunnel and mark it there.

Everything else assumes a connection, and error handling stays a local concern
rather than an architectural theme.

## Consequences

- A crash or termination mid-run is recoverable from local storage.
- The recording engine can sit behind a `RunRecorder` interface and be swapped
  without touching persistence (see
  [run-recording.md](../architecture/run-recording.md)).
- The sync layer must reconcile local and remote without treating the server as
  authoritative for live runs. This must be built from the first commit —
  retrofitting offline-first is painful.
- Data is stored in metric locally and remotely; conversion happens only at
  display (see [data-model.md](../architecture/data-model.md)).
- Persistence follows the same seam as recording: a `PlanStore` interface with a
  Drift implementation on device and an in-memory one for the preview harness and
  tests, and a `PlanBackup` mirror that is best-effort only. A failed backup can
  never fail a local write, so an offline mark still lands.
- Because the plan outlives the session that made it, a plan stores the **start
  date** it is anchored to and a **snapshot of the profile it was generated
  against** — otherwise a reloaded plan would insist it is still week 1, and a
  later profile edit would retroactively invalidate a sound plan.
