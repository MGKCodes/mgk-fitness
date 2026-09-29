# 0037 — The sandbox stays open in production

**Status:** Accepted

## Context

`REVENUECAT_ACCEPT_SANDBOX` decides whether the webhook honours a purchase
RevenueCat marks `environment: SANDBOX`. It has been `true` since it was
introduced, and every release document said to unset it before submitting:
*"Unset the flag before submitting"* (Gate 1), *"It is a launch blocker:
`supabase secrets unset`"* (play-setup.md), *"never in production"*
(store-setup.md), and the webhook README called it *"Development only"*.

The reason given everywhere was the same sentence: a sandbox event is a real
event from a fake payment, *"so accepting them in production lets anybody with a
tester account grant themselves a coach."*

Two things about that sentence are wrong, and one of them would have cost the
submission.

**App Review buys in the sandbox.** Apple's reviewers test in-app purchases in
the sandbox environment against the production build — Apple's own receipt
guidance tells production servers to accept sandbox receipts for exactly that
reason. With the flag unset, the reviewer pays, the webhook ignores the event
(`ignore: "sandbox"`), `core.entitlements` never gets a row, and the coach stays
locked behind a purchase that "went through". That is the textbook 2.1
rejection, and the checklist was instructing it.

**"Anybody with a tester account" is a short list we write.** A sandbox purchase
against this app can come from: a TestFlight install (testers we invite), a
sandbox Apple ID (created in our App Store Connect), a Play licence tester
(listed in our Play Console), or App Review. A member of the public running the
store build buys in production and cannot do otherwise.

## Decision

**`REVENUECAT_ACCEPT_SANDBOX` stays `true` in production**, through review and
after it. The code default stays `false` — a project that has not decided gets
the safe answer; this one has decided.

## The alternatives

**Unset it before submitting** — the old plan. Fails review, as above.

**On for review, off after approval.** Closes the tester route once live, but it
must be switched back on before every later submission, and forgetting is a
rejection found a day later. A flag with a calendar attached is a flag that will
eventually be wrong.

**Accept sandbox only for listed accounts** (an allowlist of user ids). Sound,
but App Review may sign up rather than use the demo account, and an allowlist
that misses the reviewer is the first alternative again.

## Cost function

What leaks is a coach for people we already chose to let in, for as long as a
sandbox subscription lasts — minutes to days, because sandbox and TestFlight
subscriptions renew on an accelerated clock and stop by themselves. Since
2026-09-29 the coach gate and the app both refuse an `active` row more than 24
hours past its `expires_at`, so even a lost `EXPIRATION` event cannot turn a
sandbox grant into a permanent one. Each sandbox call still spends real
OpenRouter credit, bounded by the tier ceilings.

## What this obliges

- **Never publish a public TestFlight link** while this is on. A public beta is
  the one way a stranger gets a sandbox purchase.
- Sandbox grants are indistinguishable from paid ones in `core.entitlements`
  today. An `environment` column is the follow-up that makes them countable.

## The disconfirming condition

Sandbox entitlements showing up for accounts nobody on the team recognises. That
means the population is not the one described here, and the allowlist becomes
the answer.
