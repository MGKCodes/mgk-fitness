# 0035 — The coach asks before it sends

**Status:** Accepted

## Context

The coach cannot answer without sending the runner's training to OpenRouter,
which passes it to the model provider that writes the reply. Some of that is
health information: special-category data under UK GDPR, and the privacy policy
has named **consent** as the lawful basis since 2026-09-01. Nothing collected
it. Every way into the coach sent first and asked nobody:

- "Build a plan" pushed the intake, which sends on its first frame;
- the coach mark opened the conversation;
- every "ask the coach" called `chat.ask` with no screen in between, carrying
  dated runs and paces, the plan, the rolling summary and a few recalled
  messages.

App Store guideline 5.1.2(i), as revised in November 2025, asks for the same
thing in its own words: disclose where personal data is shared, including with
a third-party AI, and get explicit permission before it is.

## Decision

**Every way into the coach asks, and the service refuses without an answer.**

1. **The order is account, permission, price, coach** — one gate,
   `_ensureCoachAccess` in the shell, for the mark, every "ask the coach",
   "Build a plan" and a week's "Adjust". Permission after the account because the answer is kept on
   one; before the price so nobody pays for a coach and then declines to let
   it see their training.
2. **The sheet names OpenRouter and not a model vendor.** The model is a server
   choice (ADR-0007, ADR-0014) and can change without a build. It lists what
   is sent and what never is, says the retention setting is a control we apply
   rather than a promise, and links the policy. "Agree" and "Not now";
   neither is pre-selected, and "Not now" sends nothing.
3. **The medical disclaimer is the second step, not part of the first.**
   Agreeing to where data goes and acknowledging that a plan is not medical
   advice are different things; one button for both would make neither clear.
   It is the same screen `CoachFlow` gates on, so the wording cannot drift, and
   it now reaches the conversation, which never showed it.
4. **Per account, in auth metadata**: `run_ai_consent` =
   `{"version": 1, "at": "<ISO-8601 UTC>"}`, beside `run_intro_seen`. A second
   phone is not asked again; a second account on the same phone is. A stored
   version below `kAiConsentVersion` asks again.
5. **The phone holds only answers the account has not received yet.** Every
   decision is written locally first, then to metadata, and the local entry is
   dropped once metadata has it. A full local copy read as "account or phone"
   gets withdrawal wrong both ways: withdraw offline and metadata still says
   yes; withdraw on another phone and this one's copy says yes forever.
6. **`CoachService` refuses before it builds a body**, on every surface,
   throwing `CoachConsentRequiredException`. The screens ask; this is what
   makes asking the rule rather than a habit, including for calls nobody
   watches — a summary written as the sheet closes, a week filled in ahead.
   Generation callers fall back to the deterministic plan, which is built on
   the phone, so nothing leaves either way.
7. **Withdrawal is one row in Settings › Privacy & legal**, one confirmation,
   and clears metadata and the phone's entry. Account deletion clears the key.

## Consequences

- The tier is now re-read at the gate only when it says *free*. Every entry
  goes through the gate now, and a re-read that fails resolves to free, so
  re-reading a subscriber would show the paywall to a paying runner on a bad
  connection. Revocation is still caught on resume (ADR-0032) and refused by
  the Edge Function regardless.
- A withdrawal made on one phone reaches another at that phone's next session
  refresh, not instantly: the answer is read from the persisted session so the
  check costs no round trip.
- Runners who built a plan before this build have no answer stored. Their
  look-ahead weeks stay deterministic until they next open the coach and agree.
- The Edge Function does not check the answer. The client is the only
  enforcement; a server-side check is the natural next step.
