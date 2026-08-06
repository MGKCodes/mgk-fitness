# 0006 — In-run audio cues deferred to post-v1

**Status:** Accepted

## Context

The handoff left one open product decision: the in-run experience for v1. The
options were (a) a live metrics screen **plus** spoken audio cues, (b) a live
metrics screen with audio deferred, or (c) background recording reviewed
afterwards. Audio cues (`flutter_tts`) are cheap and high-value — "the coach
only exists during a run if it can speak" — but they sit on top of a recording
layer that must first be correct and reliable.

## Decision

For **v1**, ship a **live in-run screen** (pace, distance, splits) and **defer
spoken audio cues to post-v1**. Drop `flutter_tts` from the initial dependency
set; add it in Phase C (see [roadmap.md](../roadmap.md)).

## Consequences

- v1 effort concentrates on a correct, crash-safe recorder and a visible coach
  in Plan/History, rather than splitting attention to the audio layer early.
- The coach is still present in v1 through onboarding, session rationale, and
  adaptation — just not spoken mid-run.
- Audio is a clean additive feature later: `flutter_tts` must duck background
  audio (not stop it) when it lands.
- If priorities change, promoting audio into v1 only adds one dependency and the
  in-run speech layer — no rework of recording.
