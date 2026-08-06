# 0003 — LLM generates, deterministic validator enforces

**Status:** Accepted

## Context

Training plans span many weeks and dozens of sessions. Long-horizon LLM
generation degrades **structurally** in ways that are invisible on casual
inspection: a taper disappears, two hard sessions land on consecutive days,
volume jumps out of a deload. Precision (a pace off by seconds/km) does not
matter; structure does. An 80-session block cannot be eyeballed for safety.

Separately, published training resources (Daniels' VDOT tables, Pfitzinger
schedules) are copyrighted. The repo is public, so reproducing them is both a
legal risk and unnecessary.

## Decision

The **LLM generates**; a **small deterministic validator (~150 lines) in Dart
enforces structure**. Every model output — skeleton, weekly sessions, profile
extraction, adaptation diff — is a structured proposal that must pass the
validator (and domain sanity checks) before it is stored or shown.

Pace derivation is deterministic Dart from **formulae** (Riegel; zones as a
percentage of threshold pace), never copied tables. Principles are read from the
literature; tables and specific schedules are not reproduced.

## Consequences

- Model and prompt changes are safe: the validator is the regression net, tested
  across a matrix of inputs (see
  [plan-generation.md](../architecture/plan-generation.md)).
- The model never writes a number straight into a plan — "the model proposes,
  the validator disposes" is a system-wide rule, applied to onboarding too
  ([onboarding.md](../architecture/onboarding.md)).
- No copyrighted tables/schedules in source, keeping the public repo clean (see
  [compliance.md](../compliance.md)).
