# Security

If you find a way to read or change somebody else's data, or anything else that
puts the people who use Run or Lift at risk, please tell us before you tell
anybody else.

- **Use *Report a vulnerability*** under this repository's Security tab. It
  reaches the maintainer privately. Or email **hello@mgkcodes.com**.
- Say what you did and what happened. A way to reproduce it is the most useful
  thing you can send.
- Please do not open a public issue for it, and please do not test against
  accounts or data that are not yours. A local stack (`supabase start`, see the
  README) has the same schema and policies as production, and you can break it
  freely.

## What is in scope

- **The database's row-level security**: any way for one account to read or
  change another's rows. The policies are in `supabase/migrations/`.
- **The Edge Functions** in `supabase/functions/`: the coach, account deletion
  and the purchase webhook.
- **The apps**, Run and Lift, as built from this repository.
- **The website**, mgkfitness.mgkcodes.com, built from `web/`.

## What is not a finding

The address of the Supabase project and its publishable key are in this
repository and in every copy of the apps, on purpose. Row-level security is the
boundary, not the key, so a policy that lets one account read another's rows is
exactly what we want to hear about, and the key being visible is not.

The same goes for the service key in `supabase/knowledge/sync.ts`, which secret
scanners flag: its issuer is `supabase-demo`, it is the key every copy of the
Supabase CLI ships with for a database on your own machine, and it opens nothing
of ours.

## What happens next

We read every report, answer it, and fix what is real. We will credit you if
you would like that.
