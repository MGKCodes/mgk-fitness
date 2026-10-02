# Going public

The repository is private and is about to be made public. This is what was
checked before that, what it found, and what is left for the day itself.

**When:** on or before Sunday 11 October 2026. Matthew plans to announce the
project that day, and said on 2 October that the week before it is for getting
the repository ready.

Checked on 2 October 2026, with `develop` at `82e7b3c`. **Redo the two scans
if the flip is more than a few days later**: they describe the history as it
was, and every commit since is unscanned.

**The first scan was run again later the same day**, after Run 1.0.0 was
submitted and `develop` was promoted to `main` (`8afe036`): `gitleaks` over
every ref, 579 commits, and the same single finding, the demo key below. The
second scan and the file-name check were not repeated, and that day's commits
added what is listed under *Added on the day of the submission*.

Run's `docs/compliance.md` names two things that must be true first: no secret
anywhere in the history, and no copyrighted training table anywhere in the
source. Both are below. Its roadmap still lists the first as open; that line is
Run's to tick.

## Secrets: none found

Making a repository public publishes every commit it has ever had, on every
branch and tag, so the whole history was scanned and not only the files as
they are.

| Check | Covered | Found |
|---|---|---|
| `gitleaks` 8.30.1, every ref | 567 commits | One, and it is not a secret: see below |
| A second scan for key shapes, every added line | 280,082 lines | Test fixtures only |
| File names ever committed | every ref | No `.env`, keystore, `.p8`, `.p12`, `key.properties`, `google-services.json`, service account or `app_config.json` |

- **What gitleaks found** is the service key in `supabase/knowledge/sync.ts`.
  Its issuer is `supabase-demo`: it is the key every copy of the Supabase CLI
  ships with for a database on your own machine, it is in Supabase's public
  documentation, and it opens nothing of ours.
- **What the second scan found**: a key pair that `delete-account/apple_test.ts`
  generates as it runs, the password `hunter2222` in a widget test, and three
  `env(...)` references in `supabase/config.toml`. None is a credential.
- **Public by design**, and so not findings: the project's address and its
  publishable key, which `web/app/supabase.ts` and both apps carry. Row-level
  security is the boundary, not the key.

The second scan looked for Supabase, OpenRouter, OpenAI, Anthropic, Stripe,
RevenueCat, GitHub, AWS, Google, Slack, Replicate, Resend, Esri and SMTP2GO key
shapes, private key blocks, JSON web tokens, and anything assigned to a name
like `password`, `secret` or `api_key`.

**What a scan cannot show** is a secret in a shape no pattern knows, or one
written into a sentence. If one turns up after the flip, rewriting history does
not help, because it has already been copied: the key is rotated, and that is
the whole remedy.

## What becomes public that is not a secret

Worth a decision each, because none can be taken back afterwards:

- **Three personal or studio addresses in the documents.**
  `mgkcodes@gmail.com` (in `apps/mgk_run/docs/history/app-store-1.0.0-record.md`
  and `apps/mgk_lift/docs/store-setup.md`), `mgkcodes+sandbox@gmail.com` (in
  Lift's `store-setup.md`) and `mattkay02@gmail.com` (in Run's
  `testflight-1.0.0-test-sheet.md` and `history/release-1.0.0.md`). Leave them,
  or replace them with `hello@mgkcodes.com` before the flip. After it they are
  in the history either way.
- **The App Review accounts' addresses**, in both apps' store documents. Their
  passwords are not in the repository, and nothing that pairs an account with a
  password was found.
- **Everything that was ever committed**, including files since deleted, on
  `main`, `develop` and all 29 tags.
- **`.codex/config.toml`**, which holds a path on Matthew's machine and nothing
  else. Harmless; it could simply be untracked.
- **`web/`**, which is visible and not open: it has its own licence, and
  [`NOTICE.md`](../NOTICE.md) says why.

### Added on the day of the submission

Run's store runbooks gained these on 2 October, after the scans above. None is
a credential, and each is now part of what becomes public:

- **The Google Cloud project's name**, `mgk-fitness`, the address of the
  service account RevenueCat uses, and the name of the Pub/Sub topic Play
  publishes to (`apps/mgk_run/docs/play-setup.md`). An address and two names;
  the service account's key is not in the repository.
- **Codemagic build ids** for builds 27 to 29, and App Store Connect's delivery
  id for build 29, in the build tags and the release plan. They identify a
  build to somebody already signed in, and open nothing.
- **Three links to private pages** in the READMEs: the screen board, the store
  shots and the submission sheet. A stranger who follows one is refused. Either
  share the pages when the repository opens or say beside the links that they
  are private, which Run's README does.
- **A video on the site**,
  `web/public/run/explanations/recording-with-the-screen-off.mp4`, recorded on
  an emulator. It shows the app and nothing of anybody's.

**The review accounts' passwords were reset that day, in the Supabase SQL
editor, and were never written to a file.** A search of the working tree for
both finds nothing.

## Run's own list

Run's [`after-1.0.0.md`](../apps/mgk_run/docs/after-1.0.0.md) has carried a
table headed *Before the repository goes public* since the review of
29 September. It was written before this page and the two do not yet agree, so
read both on the day:

- It says **pull requests from forks can reach Codemagic secrets**; this page
  says the `checks` workflow holds none. Both can be true, since the release
  workflows hold secrets and `checks` does not, but which workflows a fork's
  pull request can trigger has not been tested. Settle it by reading
  Codemagic's settings, not either document.
- It lists four things this page does not: that `checks` has never run and
  cannot pass as configured, gaps in `.gitignore` for keystores and credential
  files, that `scripts/codemagic-build.sh` builds from any branch it is given,
  and that `web/` sends no Content-Security-Policy header.
- Its sixth, the demo key in `supabase/knowledge/sync.ts`, is the finding
  explained above.

## Copyrighted training tables: none found

A search of `apps/*/lib`, `packages/` and `supabase/` for VDOT tables and the
published plans by name (Daniels, Pfitzinger, Higdon, Hansons) found nothing.
That is a search, not a reading of `supabase/knowledge/`: it shows the names are
absent, not that no schedule was paraphrased.

Lift's exercise illustrations are CC BY-SA and are settled in this repository.
`NOTICE.md` lists two things still outstanding outside it.

## The database, since its design becomes readable

The migrations describe every table and policy, which is intended: the
publishable key is already in every copy of the apps. It does mean a gap is
easier to find. Supabase's security advisor, run on the day of the scans, said:

- **Two trigger functions can be called by anybody**:
  `core.sync_activity_from_run()` and `core.sync_activity_from_workout()` are
  `security definer` and executable by `anon` and `authenticated`. A trigger
  function called directly raises an error, so this is very likely not
  exploitable, and there is still no reason for the grant. Closing it is two
  lines, which do not affect the triggers themselves:

  ```sql
  revoke execute on function core.sync_activity_from_run() from public, anon, authenticated;
  revoke execute on function core.sync_activity_from_workout() from public, anon, authenticated;
  ```

- **Leaked-password protection is off** in Supabase Auth. It is a dashboard
  switch that refuses passwords known from breaches.
- **`coach.usage` has row-level security and no policy.** Intended: it is
  reached only through functions, under `service_role`.

Since the waiting list's migration was applied, later the same day, the
advisor also names `core.join_waiting_list` as callable by anybody and
`core.waiting_list` as having no policy. Both are meant: the function is the
list's one door, and the table has no other.

## What strangers will be able to do

- **Open pull requests, which Codemagic builds.** The `checks` workflow in
  `codemagic.yaml` runs on every pull request to any branch, on a Mac, for up
  to twenty minutes. It holds no secrets, so nothing leaks, but the minutes are
  ours. Look at how Codemagic treats pull requests from forks before the flip.
- **Open issues.** They are on. Discussions are off.
- **Find a security problem and want to say so quietly.**
  [`SECURITY.md`](../SECURITY.md) says how.

## On the day

1. Redo the two scans if any time has passed. The first is
   `gitleaks git --redact --log-opts="--all" .`
   Then go through Run's own list, above.
2. Decide on the addresses above.
3. Bring to `main` what a visitor reads first and `develop` alone holds. On
   2 October only `web/` was promoted, so [`SECURITY.md`](../SECURITY.md),
   this page and the waiting list's migration were on `develop`, and `main`
   is the branch a visitor lands on. Run's version bump stays behind: `main`
   is what was submitted.
4. Make the repository public.
5. In its settings, turn on **secret scanning** and **push protection**, both
   free for a public repository, and **private vulnerability reporting**.
   Protect `main` and `develop`.
6. Check that Vercel still asks before building a pull request from a fork.
7. Set `open` to `true` in
   [`web/app/(landing)/links.ts`](../web/app/(landing)/links.ts), build the
   site, and follow its three links to the repository. The website goes
   straight to `main`.
8. Tick the line in Run's `docs/roadmap.md`.
