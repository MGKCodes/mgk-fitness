# 0047 — Email first, a code to confirm, and a name on the account

**Status:** Accepted, 2026-10-03, for the next Lift and Run versions after
Lift 2.0.0 and Run 1.0.1 (expected 2.0.1 and 1.0.2), submitted together.
Lift 2.0.0 goes first, while Run 1.0.0 is in review; Run 1.0.1, whose sign-in
it matches, follows once 1.0.0 is through. Replaces
"Email only" (O1, [Lift's 2.0.0 redesign](../../../mgk_lift/docs/lift-2.0.0-redesign.md))
where the name is concerned, and ends the rule that signing in never says
whether an address has an account.

## Context

Both apps' sign-in screens offer Apple, Google and *Continue with email*. The
email form then has two modes, signing in and making an account, with a switch
between them. People have to know which one they need before they type
anything, and Run has to guess whether a sign-in is new from the mode that was
showing (`onSignUpIntent`).

Checking an email-first flow against Supabase on 3 October turned up three
things:

- **The secrecy is only on screen.** Both apps refuse to say whether an address
  has an account: a wrong password never says which half was wrong, and the
  reset message is the same either way. But for an address that already has a
  confirmed account, Supabase's sign-up call returns a made-up user with an
  empty `identities` list, which is the standard way to detect one. The public
  key that makes the call ships in both apps and on the reset page.
- **Signing up twice keeps the first password.** For an address still waiting
  for confirmation, sign-up resends the email and changes nothing else
  ([`signup.go`](https://github.com/supabase/auth/blob/master/internal/api/signup.go):
  "do not update the user because we can't be sure of their claimed identity").
  Somebody who started, forgot and tried again with a new password finds, once
  confirmed, that the first password is the one that works. Anybody who typed
  another person's address first has their password on that account once its
  owner confirms.
- **Google rewrites `name`.** Supabase copies the provider's profile into the
  user's metadata when a Google account is made, when Google is linked to an
  existing account, and on every later Google sign-in
  ([`external.go`](https://github.com/supabase/auth/blob/master/internal/api/external.go)).
  Run keeps the coach's name under `name`. Read in the source; not yet seen on
  a real account.

Most people are expected to use Apple or Google. The email path is for
everybody else, and for App Review's accounts.

## Decision

### Email first

1. The first screen is unchanged: Apple, Google, *Continue with email*.
2. *Continue with email* asks for the address alone, and a server function
   looks it up. It answers `new`, `unconfirmed`, `password`, or which provider
   the account uses (`apple`, `google`), and nothing else. `unconfirmed` looks
   exactly like `new` on screen.
3. **`password`:** *Welcome back*, the address with *Change*, a password field,
   and *Forgot your password?*, which sends to the address already typed. A
   wrong password is called a wrong password.
4. **`apple` or `google`:** *This address signs in with Apple* (or Google) and
   that button, with *Set a password instead*, which sends the reset email.
   Supabase allows a password on an account made with a provider.
5. **`new` or `unconfirmed`:** *Create your account* and a password under the
   rule below, then a 6-digit code by email.
6. **The code is typed into the app.** When it checks out the account is signed
   in. If the lookup said `unconfirmed`, the password typed here then replaces
   the one the account was made with: the code proves the inbox, so this is
   safe, and it closes the gap above. Only then, because the "password changed"
   notice is on, and writing a password to a brand-new account would send it to
   everybody who signs up.
7. **Whether an account is new is read from the account**, made by this sign-in
   or not, for every way in. That includes Apple's browser flow on Android,
   which finishes after its call has returned. It replaces `onSignUpIntent`.

Telling a stranger that an address has an account is accepted. It says "this
address uses MGKFitness" and nothing about anybody's training, the API already
says as much, and Google's and Microsoft's sign-ins work the same way. The
comments, documents and test-sheet rows that promise otherwise change with this.

### A code confirms a new address

The confirmation email carries a 6-digit code **and** the link it has now,
because every Run before 1.0.2 and every Lift before 2.0.1 know only the link. The code field
takes iOS's offer from Mail (`AutofillHints.oneTimeCode`).

### The password rule

At least 8 characters, at least one number and at least one symbol. A symbol is
anything that is not a letter or a digit, so a hyphen or a space counts (the
passwords iOS suggests use hyphens). It is checked in the apps when an account
is made, and on the reset page. Signing in accepts whatever password the account
already has.

The server's minimum goes to 8, which the apps already enforce. Its character
rules stay off: Supabase offers letters and digits, or upper and lower case with
digits (and optionally symbols), and none of those is "a number and a symbol".
Turning one on would also make today's apps fail sign-ups with an error they do
not explain. There is no list of common passwords, and no leaked-password check
(Supabase offers that on the Pro plan only).

### The name belongs to the account

- **One optional step after any new account**, by any route, asking what to
  call them. It is the MGKFitness account's name: both apps show it on the
  profile, and Run's coach uses it.
- **With Apple or Google it starts filled in** with the first name the provider
  passed, and can be changed or cleared. Nobody has to use the name their
  provider holds. Apple is asked for the name (`fullName`), gives it only the
  first time an Apple ID signs in to the app, and gives it to the app rather
  than to Supabase. Google's arrives in its token, and the prefill takes its
  first word.
- **Run skips the step** when its intro already has a name.
- **Stored in the user's metadata as `display_name`**, not `name`, which Google
  rewrites. Run's existing `name` values are copied across once.
- **Never sent to the AI model**, as now.
- **Optional, because App Review rejects apps that require a name after Sign in
  with Apple.** If a reviewer objects anyway, the step is skipped for Apple
  accounts that shared a name. The name can still be changed on the profile.
- **Both privacy policies** stop saying that Apple and Google pass "an email
  address and an identifier, and nothing else". Lift declares a name in its App
  Privacy and Play data safety answers; Run already does. Run's policy changes
  only after 1.0.0's review is through.

### When it ships

The two apps share one account, so their sign-in rules change in the same
release, never one app ahead of the other. Lift 2.0.0 and Run 1.0.1 already
match. Lift 2.0.0 is not held for Run 1.0.1, so for the few days between them
Run 1.0.0's older sign-in screen is live beside Lift's: the same account and
the same rule, laid out differently. This is the next pair.

It is built on its own branch, `feat/email-first-sign-in`, made from
`develop` when the work starts, and merged into `develop` only once Lift
2.0.0 **and** Run 1.0.1 have both been submitted
([ADR-0046](0046-a-version-is-submitted-once.md)). `develop` is what both are
built from, so merging sooner would put it into one of them. Until then the
branch takes `develop` in whenever `develop` moves, so it does not drift. The
lookup function can be deployed earlier, because nothing calls it. The email
template, the reset page's rule and the policies change on the day Lift 2.0.1
and Run 1.0.2 are submitted.

This record went into `develop` on 5 October, the day Lift 2.0.0 was
submitted, so that its number and its line in both apps' decision lists are
held. It changes no build.

## Edge cases

| Case | What happens |
|---|---|
| A typo in the address | The address is on every later step with *Change*. A likely typo of a common domain gets "Did you mean …?". No code means *Resend* after 60 seconds, or *Change* |
| A wrong or expired code | Said as such, with *Resend* |
| Offline at the lookup | "No connection", with what was typed kept. Never a guess at new or returning |
| An address made with Apple, typed in | Step 4 |
| Apple with Hide My Email | A different address, so a second account, and the lookup cannot see it coming. The line under the buttons stays |
| Google or Apple with the address of an email account | Supabase links them into one account, first removing any unconfirmed sign-in on it |
| Another account's training on the phone | The guard ([ADR-0035](0035-the-phones-training-belongs-to-one-account.md)), unchanged |
| An account deleted in Run but kept for Lift | Found, so *Welcome back* |
| App Review's accounts | The password path, unchanged |
| Many sign-ups at once | Supabase limits auth email (30 new users an hour by default with our own SMTP); worth checking before a launch |

## Consequences

- Both apps' sign-in screens change again, with their tests and both screen
  boards, soon after they were made to match.
- One more server function to keep running, and it answers anybody who asks.
- The number-and-symbol rule mostly produces `Password1!`. Accepted, because
  most people will never see the password path.
- A duplicate made through Hide My Email stays a duplicate: nothing merges
  accounts. Adding Apple to an existing account (manual linking, off today) is a
  later step.

## Open

- Whether Google's name and photograph are in fact stored on a real account.
  The dashboard shows it. *For the policies, settled 5 October:* Lift 2.0.0
  was submitted with a privacy policy that says Google may send a name and a
  picture link, kept with the login and not used, and its store forms declare
  Name. Run's policy says the same once 1.0.0's review is through. What is
  left is reading one real Google account (counts only) to keep or drop the
  Name rows.
- Linking both apps to `mgkfitness.mgkcodes.com` for saved passwords
  (`webcredentials`, `assetlinks.json`), so the phone suggests a strong password
  and both apps fill it in.
- Whether Lift's coach uses the name too.
