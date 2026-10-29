# MGKFitness: Lift — documentation

Lift's own documents. Anything shared with Run is in the suite's
[`docs/`](../../../docs/) — the test is whether it would still be true if one
app were deleted.

Documents tier by **lifecycle, not topic**, the same rule Run follows:

| Tier | Changes | Answers |
|---|---|---|
| **Decisions** | Never — superseded, not edited | *Why is it this way?* |
| **Architecture** | Every time the code moves | *How does it work now?* |
| **Work** | Constantly, then stops | *What is left to do?* |

## Shipping 2.0.0

Open work. Start with the first.

**Lift's release is worked from these four files and nothing else.** Run's
plans, runbooks and checklists are not inputs to Lift's work and are not to be
read or edited for it; where a step touches something both apps share (a
secret, an account, a workflow file), the step says so itself. Lift's work
happens in its own worktree, never in a checkout another session is using
([CONTRIBUTING.md](../../../CONTRIBUTING.md), *Two sessions at once*).

- **[submission-week.md](submission-week.md)** — what is left before both
  store submissions, checked against the code, production and Codemagic on the
  date at its top. The one list to work from.
- **[store-setup.md](store-setup.md)** — the dashboards, in order. Matthew's.
- **[store-listing.md](store-listing.md)** — every listing and privacy field,
  drafted for pasting.
- **[testflight-2.0.0-test-sheet.md](testflight-2.0.0-test-sheet.md)** — the
  form. Carried to a phone with build 41, ticked, handed back.

Closed, and kept because the code and the screen board cite their decisions by
number:

- **[lift-2.0.0-redesign.md](lift-2.0.0-redesign.md)** — R1 to R13.
- **[lift-2.0.0-logging-rework.md](lift-2.0.0-logging-rework.md)** — D1 to D6.
- **[design-review-2026-09-30.md](design-review-2026-09-30.md)** — the nineteen
  findings the redesign answered.
- **[lift-2.0.0-track.md](lift-2.0.0-track.md)** — TR1 to TR9: Track as a
  front page, *Your workouts* reworked, and the launch. It replaces the
  redesign's Track (R1, R12 and the workouts row).

## In 2.0.1

What the next release changes for somebody using the app, written as it is
built. Lift has no `CHANGELOG.md`, so until it has one this list is where a
change a lifter would notice is recorded.

- **Signing in with an email asks for the address first** (Run's
  [ADR-0047](../../mgk_run/docs/decisions/0047-email-first-a-code-to-confirm-a-name-on-the-account.md)).
  A lookup leads to *Welcome back*, *This address signs in with Apple* (or
  Google), or *Create your account*: a password of at least 8 characters with
  a number and a symbol, then a 6-digit code typed into the app. A wrong
  password is called a wrong password, and *Forgot your password?* names the
  address. The two-mode form and its switch are gone, and so is the rule that
  signing in never says whether an address has an account.
- **A name on the account.** Asked once after a new account made with an
  address or with Google, which starts it filled in with Google's first name;
  never after Apple. Shown on Settings and the account screen, and given,
  changed or cleared there. It is the suite's one name, so Run shows the same.
  Lift's coach does not use it (the ADR's open question).
- **The coach asks before it sends anything** (issue #10, Run's
  [ADR-0036](../../mgk_run/docs/decisions/0036-the-coach-asks-before-it-sends.md)).
  A sheet before the coach's first request, from the coach mark, *Build a
  plan* or a swap mid-session, says what is sent and where, and nothing goes
  until *Agree*. The answer is kept on the account as `lift_ai_consent`, and
  the coach's server checks it. 2.0.0's switch was on by default, which is not
  a yes, so everybody is asked once. *Use the AI coach* still hides the coach;
  turning it off now also takes the answer back, and a swap with the coach off
  is chosen by hand rather than sent. Deleting Lift's data and keeping the
  login clears the answer.
- **A planned session fills in the weight** (#4). Each movement opens on what
  was lifted last time, one step heavier if that beat the time before (2.5 kg
  for a main lift, 1 kg otherwise) and the same weight if it did not. Plan
  says *last time 90 kg × 5* under each movement, and an accessory that has
  not moved in six sessions shows as gone stale. Read off the logged sessions
  on the phone, so it works with no signal, and a new plan has weights from
  the first session for anything done before. In 2.0.0 every planned session
  opened blank.
- **A first open** ([ADR-0005](decisions/0005-lift-opens-as-run-does.md)).
  A new install opens on a welcome, then the coach's lines, one after another:
  what Track, Plan and Profile are for, what the C at the bottom does, that
  coaching and plans are a subscription and logging is not, and that sessions
  stay on the phone until somebody signs in. *I already have an account* goes
  through sign-in first. Shown once, and never to anybody upgrading from 2.0.0.
  Track's first card no longer promises a backup to somebody signed out.

**On the day 2.0.1 is submitted**, with Run 1.0.2, and Matthew's, because each
changes production or a published document (the ADR's *Build*, held for the
owner): the confirmation email carries the code beside its link, the server's
minimum password goes to 8, the reset page checks the rule, and
`account-lookup` is deployed if it is not already. Lift's own documents change
the same day, not before, since 2.0.0 is live with them:

- [privacy-policy.md](privacy-policy.md), and its copy in the app
  (`legal_copy.dart`, held to it by `legal_copy_test.dart`) and on the site:
  *Account data* gains the first name a person chooses to give, and says
  Google's first name is offered as a suggestion rather than "not used";
  SMTP2GO sends a code as well as a link to confirm an address; and *Your
  account* says an address is looked up to show the right next step.
- [store-listing.md](store-listing.md): the Name rows in App Privacy and Data
  safety become the name somebody gives, optional, for the app's function,
  rather than only what Google may send.
- [ai-disclosure.md](ai-disclosure.md) and the privacy policy's coach section
  say the coach asks first and keeps the answer on the account (issue #10).
  Already changed here and in the app; the site's copies are regenerated from
  them that day.

**After 2.0.1 is live on both stores**, not before: deploy `coach` with
`lift` in `CONSENT_KEYS` (`supabase/functions/coach/consent.ts`). From then on
a Lift 2.0.0 install is refused until it updates, because it never asked.
- [testflight-2.0.0-test-sheet.md](testflight-2.0.0-test-sheet.md) is 2.0.0's;
  its rows B5 to B8 say what changes.

## History

- **[history/](history/)** — frozen on 1 October 2026, when they described a
  branch and a payments plan that no longer existed: the first release plan,
  the September submission plan, the August punch list and the 30 September
  handover. None of it is maintained; the path is the warning.

## The screen board

The [Lift Screen Board](https://claude.ai/artifact/UZKDFbA8qht1Nj9TQ3dQB1) is
every screen as the app renders it. Three steps, from `apps/mgk_lift`:

```bash
flutter build web -t lib/preview/main.dart --release
PLAYWRIGHT_DIR='C:/…/boardtools' node tool/capture_screens_web.mjs
SHARP_DIR='C:/…/boardtools' CAPTURE_DATE=YYYY-MM-DD node tool/build_screen_board.mjs
```

Then republish `screenshots/screen-board.html` to the board's own link, so it
stays one place.

- `boardtools` is any folder where `npm install playwright sharp` and
  `npx playwright install chromium` have run. Use Windows-style paths: Node
  reads a Git Bash `/c/Users/…` as `C:\c\Users\…`.
- The builder refuses to run when `lib/preview/main.dart` and
  `tool/screen_board.json` disagree about which screens exist.
- Set `previous`, `since` and the `first` tags in the JSON for a round that
  adds screens.
- **Two plates are timing-sensitive.** `session-summary-pb` shows the coach's
  bubble, which is on screen for under three seconds, and a capture that lands
  late photographs the screen without it. `track-backup-failed` shows a pill
  that arrives after the first frame, and version 18 was published without it.
  Compare both with the published ones before republishing.

## Decisions

- **[decisions/](decisions/)** — Lift's own ADRs. Start with
  [0001 — Liftio is replaced, not relaunched](decisions/0001-liftio-is-replaced-not-relaunched.md).

Decisions that bind **both** apps mostly sit in Run's
[`decisions/`](../../mgk_run/docs/decisions/), which is where they accumulated
first — [ADR-0025, a coach conversation is a session](../../mgk_run/docs/decisions/0025-a-coach-conversation-is-a-session.md)
binds Lift as much as Run.

The index is [decisions/README.md](decisions/README.md), which also lists the
shared ones that live in Run's set.

## Not here yet

**Architecture.** Lift has no `architecture/` directory, so the as-built
picture lives in the suite's [`architecture.md`](../../../docs/architecture.md)
and [`database.md`](../../../docs/database.md) plus the code. Run's
[`architecture/`](../../mgk_run/docs/architecture/) is the shape to copy when
it is worth writing — and a caution about the cost of not maintaining it: four
of its six files have gone stale.
