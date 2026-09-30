# 0035 — The phone's training belongs to one account

**Status:** Accepted
**Amends:** [0012](0012-backup-is-consented-restore-only-adds.md), [0032](0032-identity-is-an-event-and-the-tier-is-re-read.md) in part

## Context

The phone holds one database, one profile photo, one stored name and one backup
answer, and none of it said whose it was. The coach's memory rows carry no user
id by design, because the local database was only ever meant to hold one
runner. Signing out only called `auth.signOut()`.

So when a **different** account signed in, ADR-0032's rule — "two different
people signing in must both restore" — ran the restore and then the backfill for
them, and the backfill pushed every local run the server lacked into the new
account, stamped with the new user id, GPS traces and all. The new account saw
the first runner's log, plan, injury notes, coach transcripts and photo, and the
coach wrote its brief about them from somebody else's training.

The backup answer made it worse: one word for the whole phone, so the second
account inherited the first one's yes. A phone restored from an iCloud or Google
backup brought the same word back.

## Decision

**The phone records which account its training belongs to**, in a small file
beside the others (`FileLocalDataOwner`) rather than a column — the question is
about the phone, not about a row, and a column would be a schema change on every
table to answer it. `LocalDataGuard` holds the one rule:

- A phone with no training on it has no owner. Whoever signs in claims it.
- The first account to sign in while training is here becomes its owner. That
  is the ordinary path: weeks of runs with no account (ADR-0019), then an
  account, and the runs are theirs. It is also what every existing install looks
  like the first time this runs.
- **A different account signing in while training is here is asked, before
  anything else happens,** to erase this phone's training and continue, or to
  sign out. `AuthGate` shows the question instead of the app, and
  `HomeShell._doRestoreThenLoad` waits on the same answer, so nothing restores,
  backfills or reaches the coach until it is given.

"Training" is everything of a runner's: every table in the database (read and
cleared as `allTables`, so a table added later is covered on the day it lands),
the profile photo, the stored name, the backup answer and the push record. The
intro and disclaimer markers and the distance unit stay; they describe the
install and a display preference, not the person.

**A yes to backing up belongs to the account that gave it** (`consentFor`). The
file records who answered, and a grant applies only while that account is the
one signed in and the training on the phone is theirs. A no is a no for
everybody: it can never send anything. A grant written before this, with no
account attached, reads as unknown and is asked again.

**Leaving can take the training with it.** Signing out offers "Also remove my
data from this phone", **off by default**: the phone is where the training lives
(ADR-0004) and an account is its backup, so signing out of the backup is not a
reason to lose the original.

## Obvious alternative

**A `user_id` column on every local table**, filtering reads by the signed-in
account, so two runners could share a phone. It is the design a multi-user app
wants and this one is not: every query in the app would gain a filter, every
restore a key, the coach's memory a column it was designed without, and the
signed-out runner — the ordinary case since ADR-0019 — would own nothing at all.
A phone is one runner's. The rule makes that true instead of assumed.

## Cost function

A runner who owns two accounts, or makes a second by mistake, is asked to erase
their own training to use the second one on this phone. Signing out and back in
with the first is the way round it, and the question says what signing out
does.

**A same-account OS restore still carries the answer across.** Keying by account
means a phone restored from a backup of *another* account's phone authorises
nothing; a phone restored from the same account's backup, with its session, is
that account's phone. Making re-consent on new hardware unconditional again
(ADR-0012's original intent) needs the answer excluded from OS backup — Android
backup rules and iOS's exclude-from-backup attribute — which is native
configuration rather than Dart.
