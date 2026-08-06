# Architecture overview

Runio is an offline-first Flutter app with a thin Supabase backend and an AI
coach reached only through a server-side proxy.

## Principles

1. **Offline-first.** A run in progress is owned by the on-device database.
   Supabase is a backup and cross-device store, not the source of truth for
   live recording.
2. **The model proposes, the validator disposes.** Every LLM output is a
   structured proposal validated deterministically in Dart before use.
3. **Keys never touch the client.** The LLM provider is reached only through a
   Supabase Edge Function.
4. **Store metric, convert at display.** One canonical unit internally.
5. **Design for absence.** Denied HealthKit reads look identical to no data;
   the UI handles missing data as normal, not as an error.

## Components

```
┌──────────────────────────────────────────────────────────┐
│  Flutter app (iOS)                                        │
│                                                           │
│  UI  ─▶  Repositories  ─▶  Local store (Drift / SQLite)   │
│                    │                                       │
│          RunRecorder (interface)                          │
│            └─ GeolocatorRunRecorder                       │
│                    │                                       │
│          HealthKit (health pkg: read + write)             │
└───────────────┬───────────────────────┬──────────────────┘
                │ sync                   │ AI calls
                ▼                        ▼
        ┌───────────────┐      ┌───────────────────────┐
        │   Supabase    │      │ Supabase Edge Function │
        │  Auth · DB    │      │   (holds provider key) │
        │  (RLS)        │      │           │            │
        └───────────────┘      └───────────┼────────────┘
                                           ▼
                                   ┌───────────────┐
                                   │  OpenRouter   │
                                   └───────────────┘
```

## Layers

- **UI** — screens for Record, Plan, History, and onboarding.
- **Repositories** — the only thing the UI talks to. They read/write the local
  store and reconcile with Supabase. All data crosses this boundary in metric.
- **Local store** — Drift over SQLite. Source of truth for live recording and
  the offline mirror of synced data.
- **RunRecorder** — an interface with one concrete `geolocator` implementation.
  Swapping the recording engine is a one-class change. See
  [run-recording.md](run-recording.md).
- **Sync** — pushes local runs to Supabase and pulls cross-device data. The
  server is a backup, not the authority for an in-progress run.
- **AI proxy** — a Supabase Edge Function is the *only* thing that talks to the
  LLM provider (OpenRouter; the model is a server-side `COACH_MODEL` choice).
  See [llm-and-secrets.md](llm-and-secrets.md).

## Data flow: recording a run

1. `RunRecorder` emits location points.
2. Each point is filtered (accuracy), processed (smoothing, autopause), and
   **persisted to local SQLite immediately**.
3. On finish: compute splits/summary → save locally → sync to Supabase → write
   an `HKWorkout` back to HealthKit.
4. HealthKit reads are deduplicated against Runio's own workout before anything
   reaches the training log.

## Data flow: generating a plan

1. Onboarding fills a structured runner profile (validated in Dart).
2. The Edge Function calls the provider to generate a **skeleton**; the Dart
   validator enforces structure; the skeleton is shown to the user in full.
3. Each week, the Edge Function generates **seven sessions** for the coming
   week, constrained by the skeleton slot and recent history; the validator
   checks them before they land.

See [plan-generation.md](plan-generation.md).
