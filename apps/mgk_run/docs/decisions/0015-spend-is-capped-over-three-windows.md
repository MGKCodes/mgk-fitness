# 0015 — Spend is capped over three windows, not one

**Status:** Accepted
**Extends:** [0007](0007-secrets-via-backend-proxy.md)

## Context

[ADR-0007](0007-secrets-via-backend-proxy.md) put a per-user spend cap at the
proxy: a rolling 24 hours, defaulting to 0.5 credits. The window was chosen
because a day is the obvious unit for a rate limit.

It is the wrong unit for a bill. A subscription charges monthly, so the number
that has to sit under revenue is a **monthly** one — and a daily cap silently
authorises thirty times itself. At 0.5/day that is about $15 a month per runner,
against a £1 subscription netting roughly £0.71 after VAT and Apple's 15%. One
runner reaching the cap would have consumed the margin of about sixteen others,
and the daily figure looked small the whole time.

The reverse is also true: a monthly cap alone would let a runaway client spend
the entire month's allowance in an hour, and the runner would find the coach
dead for four weeks with no explanation.

## Decision

**Three rolling windows — 24 hours, 7 days, 30 days — evaluated together.**

They answer different questions. The daily ceiling bounds a runaway loop. The
monthly ceiling bounds the bill. The weekly one sits between so a bad few days
cannot quietly become a bad month.

When more than one is breached, the ceiling that clears **last** is the one
reported. Telling a runner to come back in an hour for a daily cap, while the
monthly cap still binds for a fortnight, is a lie the UI then repeats.

Each window has its own secret (`COACH_{DAILY,WEEKLY,MONTHLY}_SPEND_LIMIT`), and
each falls back to a shipped default if missing, unparseable, zero or negative —
so a typo can never become "no limit".

**The shipped numbers are provisional placeholders, not measured figures**, and
are marked as such in `limits.ts`. What a runner actually costs depends on the
model behind `COACH_MODEL` / `COACH_CHAT_MODEL`, which is a server-side choice
that file deliberately knows nothing about ([0014](0014-model-is-chosen-per-surface-and-per-tier.md)).
The real numbers come from `runio.coach_usage` after live traffic; the README
carries the query.

## Obvious alternative

Keep one window and set it to the monthly figure divided by thirty.

Rejected: that is a daily cap that binds on a single enthusiastic day. A runner
who has one long conversation on a Sunday is not overspending for the month, and
refusing them is a worse failure than the one being prevented.

## Cost function

Three counters instead of one, and a lookback that now reads thirty days of
usage rows rather than one. Accepted, because usage is bounded by the caps
themselves — a runner cannot accumulate many rows without hitting a ceiling that
stops them — so the read stays small in practice.

The consequence that had to move with it: `runio_coach_record_usage` prunes rows
older than **31 days**, not 7. A row pruned before the longest window closes is
spend the cap cannot see, and the prune must always outlive
`lookbackSeconds(config)`.

## Disconfirming condition

If pricing stops being monthly — a credit pack, pay-as-you-go, bring-your-own-key
— the monthly window stops being the one that matters, and the shape should
follow whatever the new billing unit is.

## Consequences

- Adding a longer window means moving the SQL prune interval first, or the new
  ceiling silently stops binding.
- The cap is **per user, with no global ceiling**. Nothing sums across runners,
  so the only account-wide protection is the credit limit set on the OpenRouter
  key itself. That is configuration outside this repo and nothing here can
  assert it.
