# Compliance & legal

MGKFitness: Run processes **special-category health data under UK GDPR** and
prescribes
physical load. These are prerequisites for App Store submission, not
follow-ups.

## Health data is special-category data

Running data, heart rate, weight, and derived fitness metrics are health data.
Under UK/EU GDPR this is special-category personal data with a higher bar for
lawful processing, storage, and deletion.

Requirements before submission:

- **Privacy policy** published and linked in-app and on the store listing. Draft
  in [privacy-policy.md](privacy-policy.md); rendered in-app by
  `lib/src/features/legal/`.
- **A working deletion path** — the user can delete their account and all
  associated data and it is actually removed from Supabase, not just hidden.
  Built as the
  [`delete-account` Edge Function](../../../supabase/functions/delete-account/README.md);
  see [Deletion on a shared account](#deletion-on-a-shared-account) below.

  `core.delete_account(p_user_id, p_app)` sweeps **every table in the target
  app's schema carrying a `user_id`** — `run` and `lift` are the app schemas,
  plus `coach` — discovered from the catalogue and ordered so children go before
  parents, rather than working from a hard-coded list. That is what makes the
  policy's "every record we hold for you" claim safe to write: the coach
  transcripts and the usage ledger were added months after the function and were
  covered the day they existed. A list would have needed someone to remember.

  **This paragraph described `runio_delete_account` and the `runio` schema until
  2026-09-01**, a month after `20260806130000_restructure_schemas.sql` renamed
  that schema to `run`. The function was right the whole time; the document
  justifying it to a regulator was not, which is the worse way round for the two
  to disagree.
- **Data minimisation** — only collect what the coach needs.

## Named sub-processors

The privacy policy must name every third party that processes user data. For
the app:

| Sub-processor | Purpose | Data shared |
|---|---|---|
| **Supabase** | Auth, database, Edge Functions (hosting) | Account; and — **only with backup consent** — runs, traces, plans, coach transcripts. Usage records regardless, since the limiter cannot work without them. `eu-west-1` (Ireland) |
| **OpenRouter** | LLM gateway for onboarding, planning, adaptation and conversation | Training context **and the runner's own messages**; see below |
| **RevenueCat** | Subscription purchases and the entitlement state behind them ([ADR-0028](decisions/0028-revenuecat-is-the-purchase-path.md)) | The Supabase `user_id` as a pseudonymous app user id, and purchase records. **No training, health or message content.** |
| **MapTiler** | Basemap tiles | Approximate viewport coordinates |

**Pick the model provider before writing the policy, not after.** The app calls
the model through **OpenRouter**, a gateway: the specific model is a server-side
`COACH_MODEL` secret, so it can change without an app release
([ADR-0007](decisions/0007-secrets-via-backend-proxy.md),
[llm-and-secrets.md](architecture/llm-and-secrets.md)). OpenRouter is therefore
the named sub-processor, and it forwards our request to whichever provider serves
the selected model.

That indirection has a compliance consequence worth being deliberate about: the
processor behind the gateway is a **configuration choice**, so the policy names
OpenRouter as the recipient rather than promising one downstream provider. If a
regulator or App Review asks which model is in use, answer from the deployed
`COACH_MODEL` value — do not guess from the repo. Changing `COACH_MODEL` to a
model from a different provider is a **policy-visible change**: re-check this
table before doing it.

### What is actually sent

This used to read "structured training context (goals, volumes, session
history)". That was true when only the planning surfaces existed and it stopped
being true the moment the coach could hold a conversation. Stating it in a
privacy policy after that would have been a misrepresentation, which is why it
is spelled out per surface here and in the policy:

| Surface | What goes up |
|---|---|
| `skeleton`, `week`, `adapt` | The profile and the plan as JSON: goal, volumes, available days, session kinds and distances, injury notes if given |
| `chat` | `CoachBrief` prose — the same facts as above plus plan history and readiness — **and up to the last 20 turns of the conversation verbatim** |
| `intake` | The onboarding conversation verbatim, which is where a runner first describes their injuries |
| `log_run`, `edit_run`, `set_goal` | One sentence the runner wrote |
| `summarise` | The transcript, to compress it |

So free text the runner typed **does** reach the provider, and it is the field
most likely to contain a symptom or a diagnosis. What still never leaves:

- **Raw GPS traces.** No `run_points` row is ever sent to a model.
- **Identity.** No name, email or `auth.uid()` — the request is made by the Edge
  Function under our key, so the provider sees our server, not the runner's IP
  or device.

That is de-identified, not anonymous, and the policy says so rather than
implying otherwise. All calls route through our
[Edge Function proxy](architecture/llm-and-secrets.md); the client never talks to
a model provider directly.

**Before launch, settle two things with OpenRouter that code cannot settle:**
whether a processor agreement / DPA is in place naming them for special-category
data, and whether the configured `COACH_MODEL`'s provider trains on inference
inputs. The second is a per-model property and changing `COACH_MODEL` can change
the answer, which is another reason that change is policy-visible.

## Backup consent is the lawful basis, and it is off by default

Explicit consent is the Art. 9 basis, and it is a real switch rather than a
sentence in a policy: **Back up my data** starts off, and with it off no run,
plan or transcript is sent to Supabase at all. The app is fully usable in that
state because the device owns the data (CLAUDE.md rule 1).

- `BackupConsent` is three-valued — `unknown` / `granted` / `declined` — so "has
  not been asked" is distinguishable from "said no". A runner is asked before
  anything moves, and on new hardware consent arrives `unknown`, so the order is
  always ask, then restore.
- Every push path is wrapped by a consent gate (`ConsentedRunBackup`,
  `ConsentedPlanBackup`, `ConsentedMemoryMirror`) rather than each caller
  remembering to check.
- **Withdrawal deletes.** Turning it off runs `BackupEraser` over the stored
  rows, so withdrawing consent is not merely prospective.
- Restoring is one-way and insert-or-ignore: a pull can only add, never
  overwrite. Verified end to end against the live project by
  `test/live/restore_round_trip_test.dart`.

The one thing consent does **not** gate is the AI request itself. The coach
cannot answer without sending context, so using the coach sends it either way,
and the policy says that in the same breath rather than leaving it to be
inferred.

## Medical disclaimer

The app prescribes physical load, so a medical disclaimer is required and must
be surfaced at onboarding. Standard "consult a physician, stop if you
experience pain" wording. See [medical-disclaimer.md](medical-disclaimer.md).

It is enforced as a **gate**, not a footnote: `CoachFlow` shows it before the
onboarding conversation starts, so nothing is generated until the runner accepts.
Acknowledgement is remembered locally (a marker file — not an account setting, so
there is no server round-trip in the way of a legal notice), and every failure
mode of that store resolves to *show it again* rather than skip it. The same
wording stays reachable from the in-app legal screen.

## Deletion on a shared account

The app shares one `auth.users` pool and `core.profiles` / `core.user_settings`
with **MGKFitness: Lift** ([ADR-0008](decisions/0008-shared-supabase-platform.md)).
Deleting the login would therefore delete **the sibling app's** account and
cascade away its workouts,
exercises, sets, and progress photos — erasing data from an app the user did not
ask to leave. A naive "delete the auth row" implementation is a data-loss bug
wearing a compliance badge.

So deletion is scoped by what the account actually holds. `core.delete_account`
takes the asking app and enumerates tables from the catalogue, so this table
describes a mechanism rather than a list somebody maintains:

| | On `delete_account(user, 'run')` | Only if the sibling app holds no data |
|---|---|---|
| Every `run.*` row for the user | erased | |
| `coach.conversations`, `coach.turns`, `coach.summaries` **tagged `run`** | erased | |
| `coach.usage` (the rate limiter's ledger — counts and costs, no content) | retained | deleted |
| `core.profiles.dob`, `.weight_kg` | **retained** | cleared with the row |
| `core.user_settings` row | | deleted |
| `core.profiles` row | | deleted |
| `auth.users` row (the login) | | deleted |

A login surviving with no data behind it is recoverable; erasing the sibling
app's data is not, so the tie breaks that way. When the login is retained the app
says so plainly and points at hello@mgkcodes.com for removing it.

**This table was wrong in four places until 2026-09-07, and one of them was a
promise the code had stopped keeping.** It named the `runio` schema, renamed to
`run` by `20260806130000_restructure_schemas.sql`; it put the shared rows in
`public` rather than `core`; it was silent on coach data, which
`20260807140000_delete_account_scopes_the_coach.sql` made erasable per app,
closing a real gap where a lifter deleting their running data left those
conversations behind; and it said `dob` and `weight_kg` were **always cleared**
when `20260806130300_account_deletion.sql` had deliberately stopped clearing
them on a partial deletion — *"they now live in `core.profiles`, belong to the
person, and survive as long as the profile does. That is a real change in
meaning, not an oversight."*

**That last one is the direction that matters**: the document defending erasure
to a regulator claimed more erasure than the function performs. It is the same
shape as the defect the build 12 field test found in backup consent — the policy
promised deletion and the code did none — and the same shape as the `runio`
error recorded thirty lines above, which was corrected in the paragraph that
described the function while the table describing the same function was missed.
Both halves are checked against the migrations now, not against each other.

Deletion should still become a single platform-level surface offering "leave the
running app" and "close my MGKCodes account" as distinct choices, rather than one
app inferring the other's usage. The sibling app is on the same stack now, so
what was once blocked on that is only unbuilt.

## App Store review

- The **Health & Fitness** category brings extra scrutiny on data handling.
- **Always-on location** needs a written justification. "Recording a run with
  the screen off" is accepted.
- Be ready to explain, in App Review notes, exactly what health data is read,
  written, and shared, and with whom.

## Going public (open source)

Before flipping the repository from private to public:

- **Scrub git history of secrets** — any key, token, or `.env` that was ever
  committed must be removed from history and rotated.
- **No copyrighted training tables or schedules** anywhere in source (e.g. VDOT
  tables, published plan schedules). Principles and formulae only. See
  [ADR-0003](decisions/0003-llm-generates-validator-enforces.md).

## Not legal advice

This document is engineering guidance to keep compliance in view during the
build. It is not legal advice. Have the privacy policy and disclaimer reviewed
before submission.
