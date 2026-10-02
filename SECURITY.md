# Security

If you find a way to read or change somebody else's data, or anything else that
puts the people who use Run or Lift at risk, please tell us before you tell
anybody else.

- **Email hello@mgkcodes.com**, or use *Report a vulnerability* under this
  repository's Security tab.
- Say what you did and what happened. A way to reproduce it is the most useful
  thing you can send.
- Please do not open a public issue for it, and please do not test against
  accounts or data that are not yours.

## What is not a finding

The address of the Supabase project and its publishable key are in this
repository and in every copy of the apps, on purpose. Row-level security is the
boundary, not the key, so a policy that lets one account read another's rows is
exactly what we want to hear about, and the key being visible is not.

## What happens next

We read every report, answer it, and fix what is real. We will credit you if
you would like that.
