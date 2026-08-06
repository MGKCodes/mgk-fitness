# Runio documentation

Start here.

## Product

- **[Product specification](product-spec.md)** — what Runio is, the decisions
  made, scope, packages, and platform requirements. The source of truth.
- **[Roadmap](roadmap.md)** — the phased build order.

## Architecture

- **[Overview](architecture/overview.md)** — system design and how the pieces
  fit together.
- **[Data model](architecture/data-model.md)** — schema and the offline-first
  local mirror.
- **[Run recording](architecture/run-recording.md)** — GPS capture, point
  persistence, HealthKit deduplication, elevation, calories.
- **[Plan generation](architecture/plan-generation.md)** — LLM generation with
  a deterministic validator, two-stage generation, invariants, pace derivation.
- **[Onboarding](architecture/onboarding.md)** — conversational slot-filling.
- **[LLM & secrets](architecture/llm-and-secrets.md)** — the AI proxy
  architecture and how keys are kept out of the client.

## Decisions

- **[Architecture Decision Records](decisions/)** — the *why* behind the big
  calls, one file each.

## Compliance & legal

- **[Compliance](compliance.md)** — GDPR, health data, sub-processors, App
  Store review notes.
- **[Privacy policy (draft)](privacy-policy.md)**
- **[Medical disclaimer](medical-disclaimer.md)**
