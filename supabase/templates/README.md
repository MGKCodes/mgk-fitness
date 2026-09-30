# Auth email templates

What Supabase Auth sends, for both apps, since they share one account. Each
file is the **whole** template: open it, copy everything, and paste it into
Supabase › Authentication › Emails › Templates, with the subject below.
`config.toml` points the local stack at the same files.

**A saved template takes a minute or two to reach the mail.** Supabase restarts
its auth server to apply it, and an email sent in between still uses the old
one; the first test of the light-first design went out that way on
30 September. Wait a couple of minutes after saving before testing.

| File | Dashboard template | Subject | Sent when |
|---|---|---|---|
| `recovery.html` | Reset password | `Choose a new password` | "Forgot your password?" in either app |
| `confirmation.html` | Confirm sign up | `Confirm your email for MGKFitness` | an email sign-up, once confirmation is on |
| `password_changed_notification.html` | Password changed, among the security notifications further down the same page, switched on there | `Your MGKFitness password was changed` | any password change, including a reset |

The other templates (invite, magic link, change of email, reauthentication)
are never sent: neither app offers those flows. Write one here the day that
changes.

## Where the links go

- **Reset password** links to `{{ .SiteURL }}/reset-password` with a token
  hash, not `{{ .ConfirmationURL }}`. Both apps sign in with PKCE, so the
  confirmation URL would arrive with a code only the phone that asked can
  exchange. The page (`web/app/reset-password`) verifies the hash when the form
  is sent, so a mail scanner that opens the link does not spend it.
- **Confirm sign up** uses `{{ .ConfirmationURL }}`: Supabase confirms the
  address when the link is opened and then redirects to the Site URL. A scanner
  opening it first confirms the address early, which is harmless.

`{{ .SiteURL }}` is `https://mgkfitness.mgkcodes.com` in production, so check
Authentication › URL Configuration if a link ever lands somewhere odd.

## The design, and its rules

**Written by `build_templates.py`**, which holds the one frame all three
share: edit it, run it, and paste the files that changed. Editing a file by
hand is how three emails start to disagree.

**Light first, with a dark version.** The first design was charcoal only, and
the Gmail app in dark mode inverted it into light grey with a dark button: it
ignores an email's own dark styles and flips the colours of anything it thinks
is dark. So the base is light (a white card on `#F2F2F2`, a `#1A1A1A` headline,
a charcoal pill), and a `prefers-color-scheme: dark` block, with Outlook.com's
`[data-ogsc]` equivalent, swaps in the apps' own greys (`mgk_ui`'s
`AppColors`): `#1A1A1A` page, `#2D2D2D` card with a `#404040` edge, white
headline, `#9CA3AF` text, the silver `#C0C0C0` pill. Apple Mail and iOS Mail
show that version in dark mode; Gmail inverts the light one, which lands close
to it. Greyscale either way (ADR-0009).

The address in the text is a `mailto:` link styled like the words around it,
so Gmail does not turn it into a blue link of its own.

- **No images.** Mail clients block them by default, and a picture fetched from
  our server tells us when somebody opened the email. The wordmark is text.
- **No webfont.** The system font stack, for the same reason as the website:
  loading a font from a host leaks the reader's address to it.
- **No tracking.** SMTP2GO's open and click tracking stay off, and its
  `link.` tracking record is deliberately not in DNS; a rewritten reset link
  is the last thing this email should carry.
- **Tables and inline styles**, because that is what every mail client
  renders. The one `<style>` block only tightens the card on a narrow screen;
  without it the email still reads.
- **The link is written out as text too**, under the button, for clients that
  strip buttons.

Sent through SMTP2GO's EU relay as `MGKFitness <noreply@mgkfitness.mgkcodes.com>`
(Lift's `docs/store-setup.md`, step 6).
