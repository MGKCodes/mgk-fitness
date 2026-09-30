"""Writes the three auth email templates from one frame, so they cannot drift.

    python supabase/templates/build_templates.py

Edit here, run it, then paste the files that changed into Supabase (README.md).

Light first, with a dark version for clients that honour prefers-color-scheme
(Apple Mail, iOS Mail) and Outlook.com's [data-ogsc] selectors. Gmail's apps
ignore both and invert a light email on their own, which lands near the dark
version anyway; they invert a dark one into light grey, which is why the first
design came out the wrong way round on an iPhone.
"""

import os

OUT = os.path.dirname(os.path.abspath(__file__))
FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif"

# The apps' own greys (mgk_ui AppColors) for dark; their mirror for light.
L = dict(page="#F2F2F2", card="#FFFFFF", edge="#E2E2E2", ink="#1A1A1A",
         text="#4B5563", faint="#6B7280", btn="#1A1A1A", btn_ink="#FFFFFF", rule="#E5E5E5")
D = dict(page="#1A1A1A", card="#2D2D2D", edge="#404040", ink="#FFFFFF",
         text="#9CA3AF", faint="#9CA3AF", btn="#C0C0C0", btn_ink="#1A1A1A", rule="#404040")


def head(title):
    d = D
    return f"""<!doctype html>
<html lang="en-GB">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>{title}</title>
<style>
  :root {{ color-scheme: light dark; supported-color-schemes: light dark; }}
  body {{ margin: 0; padding: 0; }}
  @media (max-width: 520px) {{
    .card {{ padding: 32px 24px !important; }}
    .h1 {{ font-size: 24px !important; line-height: 30px !important; }}
  }}
  @media (prefers-color-scheme: dark) {{
    .page {{ background-color: {d['page']} !important; }}
    .card {{ background-color: {d['card']} !important; border-color: {d['edge']} !important; }}
    .ink {{ color: {d['ink']} !important; }}
    .text {{ color: {d['text']} !important; }}
    .faint {{ color: {d['faint']} !important; }}
    .btn-cell {{ background-color: {d['btn']} !important; }}
    .btn {{ color: {d['btn_ink']} !important; }}
    .rule {{ border-color: {d['rule']} !important; }}
  }}
  [data-ogsc] .page {{ background-color: {d['page']} !important; }}
  [data-ogsc] .card {{ background-color: {d['card']} !important; border-color: {d['edge']} !important; }}
  [data-ogsc] .ink {{ color: {d['ink']} !important; }}
  [data-ogsc] .text, [data-ogsc] .faint {{ color: {d['text']} !important; }}
  [data-ogsc] .btn-cell {{ background-color: {d['btn']} !important; }}
  [data-ogsc] .btn {{ color: {d['btn_ink']} !important; }}
</style>
</head>
"""


def frame(title, preheader, body, footer):
    l = L
    spacer = "&#8199;&#847;" * 6
    return head(title) + f"""<body class="page" style="margin:0;padding:0;background-color:{l['page']};">
<div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:{l['page']};">{preheader}{spacer}</div>
<table role="presentation" class="page" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="{l['page']}" style="background-color:{l['page']};">
  <tr>
    <td align="center" style="padding:40px 16px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:520px;">
        <tr>
          <td class="faint" style="padding:0 4px 20px 4px;font-family:{FONT};font-size:12px;line-height:16px;font-weight:700;letter-spacing:3px;color:{l['faint']};">MGKFITNESS</td>
        </tr>
        <tr>
          <td class="card" bgcolor="{l['card']}" style="background-color:{l['card']};border:1px solid {l['edge']};border-radius:20px;padding:40px 36px;">
{body}
          </td>
        </tr>
        <tr>
          <td class="faint" style="padding:24px 4px 0 4px;font-family:{FONT};font-size:12px;line-height:18px;color:{l['faint']};">{footer}<br>MGKCodes Ltd &middot; <a class="faint" href="https://mgkfitness.mgkcodes.com" style="color:{l['faint']};text-decoration:underline;">mgkfitness.mgkcodes.com</a></td>
        </tr>
      </table>
    </td>
  </tr>
</table>
</body>
</html>
"""


def h1(text):
    return f'            <h1 class="h1 ink" style="margin:0 0 12px 0;font-family:{FONT};font-size:28px;line-height:34px;font-weight:700;letter-spacing:-0.4px;color:{L["ink"]};">{text}</h1>'


def p(html, bottom=28, size=16, line=24, top=0):
    return f'            <p class="text" style="margin:{top}px 0 {bottom}px 0;font-family:{FONT};font-size:{size}px;line-height:{line}px;color:{L["text"]};">{html}</p>'


def email():
    # A link we style ourselves, so Gmail does not turn the address blue.
    return f'<a class="ink" href="mailto:{{{{ .Email }}}}" style="color:{L["ink"]};text-decoration:none;">{{{{ .Email }}}}</a>'


def strong(text):
    return f'<span class="ink" style="color:{L["ink"]};font-weight:700;">{text}</span>'


def button(href, label):
    return f"""            <table role="presentation" cellpadding="0" cellspacing="0" border="0">
              <tr>
                <td class="btn-cell" bgcolor="{L['btn']}" style="background-color:{L['btn']};border-radius:999px;">
                  <a class="btn" href="{href}" style="display:inline-block;padding:15px 30px;font-family:{FONT};font-size:16px;line-height:20px;font-weight:700;color:{L['btn_ink']};text-decoration:none;border-radius:999px;">{label}</a>
                </td>
              </tr>
            </table>"""


def fallback(href):
    return f"""            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
              <tr>
                <td class="rule" style="padding:28px 0 0 0;border-bottom:1px solid {L['rule']};font-size:0;line-height:0;">&nbsp;</td>
              </tr>
            </table>
{p(f'Button not working? Copy this into your browser:<br><a class="ink" href="{href}" style="color:{L["ink"]};text-decoration:underline;word-break:break-all;">{href}</a>', bottom=0, size=13, line=20, top=20)}"""


reset_link = "{{ .SiteURL }}/reset-password?token_hash={{ .TokenHash }}&amp;type=recovery"
confirm_link = "{{ .ConfirmationURL }}"

templates = {
    "recovery.html": frame(
        "Choose a new password",
        "Your link to choose a new password for Lift and Run. It works once.",
        "\n".join([
            h1("Choose a new password"),
            p(f"Somebody asked to reset the password for {email()}, the account you use in Lift and Run."),
            button(reset_link, "Choose a new password"),
            p("The link works once. If you did not ask for this, ignore this email: your password has not changed.", bottom=0, size=15, line=22, top=28),
            fallback(reset_link),
        ]),
        "Sent by MGKFitness, the account behind Lift and Run, because somebody asked for it with this address.",
    ),
    "confirmation.html": frame(
        "Confirm your email",
        "One tap to finish setting up your account for Lift and Run.",
        "\n".join([
            h1("Confirm your email"),
            p(f"Tap below to confirm {email()} and finish setting up the account you use in Lift and Run."),
            button(confirm_link, "Confirm my email"),
            p("Then go back to the app and sign in. If you did not sign up, ignore this email: the address will not be confirmed.", bottom=0, size=15, line=22, top=28),
            fallback(confirm_link),
        ]),
        "Sent by MGKFitness, the account behind Lift and Run, because somebody signed up with this address.",
    ),
    "password_changed_notification.html": frame(
        "Your password was changed",
        "The password for your Lift and Run account was just changed.",
        "\n".join([
            h1("Your password was changed"),
            p(f"The password for {email()}, the account you use in Lift and Run, was just changed. If that was you, there is nothing to do.", bottom=16),
            p(f"{strong('If it was not,')} choose a new one straight away with {strong('Forgot your password?')} on the sign-in screen of Lift or Run, and tell us at "
              f'<a class="ink" href="mailto:hello@mgkcodes.com" style="color:{L["ink"]};text-decoration:underline;">hello@mgkcodes.com</a>.', bottom=0),
        ]),
        "Sent by MGKFitness, the account behind Lift and Run, to tell you about a change to your account.",
    ),
}

for name, html in templates.items():
    with open(os.path.join(OUT, name), "w", encoding="utf-8", newline="\n") as f:
        f.write(html)
    print("wrote", name, len(html))
