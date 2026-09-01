#!/usr/bin/env python3
"""Render the legal documents to self-contained pages for mgkcodes.com.

`docs/privacy-policy.md` is the source of truth: `legal_copy_test.dart` already
pins the in-app copy to it, and App Store review compares the published page
against what the app shows. That makes three renderings of one text, and the
only safe way to keep three copies identical is to stop hand-writing two of
them. Regenerate after any edit to the source:

    python tool/build_legal_pages.py

Run from `apps/mgk_run`. Writes to `docs/legal-site/`.

**Deliberately dependency-free output.** No webfont, no CDN, no analytics — a
privacy policy that leaks the reader's IP address to a font host before they
have read the first line is not a good look, and it is the sort of thing a
regulator notices. System font stack only, so the page works on any host that
can serve a file.

Internal-only blocks are stripped: the draft banner and the note pointing at
`legal_copy.dart` are notes to ourselves and have no business on a public page.
The publication blockers they name are re-emitted as an HTML comment at the top
of the file, so whoever deploys it sees them in the source.
"""

from __future__ import annotations

import html
import pathlib
import re
import sys

DOCS = pathlib.Path("docs")
OUT = DOCS / "legal-site"

# Blockers that must clear before either page goes live. Taken from the source
# document's own draft banner, which is stripped from the rendered output.
BLOCKERS = [
    "Legal review of this document.",
    "A processor agreement with OpenRouter covering special-category data.",
    "Whether the configured COACH_MODEL's provider trains on inference inputs.",
    "The publication date - replace the PUBLICATION_DATE token below.",
]

PAGES = [
    ("privacy-policy.md", "privacy-policy.html"),
    ("medical-disclaimer.md", "medical-disclaimer.html"),
]

CSS = """
:root{color-scheme:light dark;--ink:#14171a;--muted:#5a6169;--ground:#fff;
--rule:#e3e6ea;--accent:#7a4f08;--quote:#f6f7f8}
@media (prefers-color-scheme:dark){:root{--ink:#e6e9ec;--muted:#9aa1a9;
--ground:#101214;--rule:#282d32;--accent:#d9a63e;--quote:#191c1f}}
*{box-sizing:border-box}
body{margin:0;background:var(--ground);color:var(--ink);
font:16px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,
"Helvetica Neue",Arial,sans-serif;-webkit-font-smoothing:antialiased}
main{max-width:44rem;margin:0 auto;padding:3.5rem 1.25rem 6rem}
h1{font-size:clamp(1.75rem,4.5vw,2.4rem);line-height:1.15;margin:0 0 .5rem;
letter-spacing:-.02em}
h2{font-size:1.2rem;margin:2.75rem 0 .75rem;letter-spacing:-.01em;
padding-top:1.25rem;border-top:1px solid var(--rule)}
p,li{margin:0 0 .9rem}
ul{padding-left:1.25rem}
li>ul{margin-top:.6rem}
a{color:var(--accent)}
code{font:.9em ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
background:var(--quote);padding:.1em .35em;border-radius:3px}
footer{margin-top:4rem;padding-top:1.5rem;border-top:1px solid var(--rule);
color:var(--muted);font-size:.9rem}
"""

NL = chr(10)


def inline(text: str) -> str:
    """Escape, then re-apply the inline markdown these documents actually use."""
    out = html.escape(text, quote=False)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"(?<![*\w])\*([^*]+)\*(?!\w)", r"<em>\1</em>", out)
    out = re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", r'<a href="\2">\1</a>', out)
    # Relative links point at repo files that do not exist on the web.
    out = re.sub(r"\[([^\]]+)\]\((?!https?://)[^)]+\)", r"\1", out)
    return out


def blocks(md: str) -> list[tuple[str, int, str]]:
    """Markdown to [(kind, indent, joined_text)]. Blockquotes are internal notes.

    Lines are joined into their block **before** any inline markup is applied.
    Applying it per line breaks emphasis that wraps across a source line, which
    is how one italic span in the policy reached the page as a literal asterisk.
    """
    out: list[tuple[str, int, str]] = []
    buf: list[str] = []
    kind = ""
    indent = 0

    def flush() -> None:
        nonlocal buf, kind, indent
        if buf:
            out.append((kind, indent, " ".join(buf).strip()))
        buf, kind, indent = [], "", 0

    for raw in md.split(NL):
        line = raw.rstrip()
        stripped = line.strip()

        if stripped.startswith(">") or not stripped:
            flush()
            continue
        if stripped.startswith("# "):
            flush()
            out.append(("h1", 0, stripped[2:].strip()))
            continue
        if stripped.startswith("## "):
            flush()
            out.append(("h2", 0, stripped[3:].strip()))
            continue

        m = re.match(r"^(\s*)- (.*)$", line)
        if m:
            flush()
            kind, indent, buf = "li", len(m.group(1)), [m.group(2).strip()]
            continue

        # A continuation of whatever block is open, or the start of a paragraph.
        # An indented paragraph after a blank line still belongs to the list item
        # above it — that is how the sub-processor entries carry a sentence, a
        # sub-list and then a closing sentence, and losing it would split one
        # list of three processors into three lists.
        if kind:
            buf.append(stripped)
        else:
            kind, buf = "p", [stripped]
            indent = len(line) - len(line.lstrip())

    flush()
    return out


def render(md: str) -> tuple[str, str]:
    title = ""
    parts: list[str] = []
    stack: list[int] = []

    def close_to(target: int) -> None:
        while stack and stack[-1] > target:
            parts.append("</li></ul>")
            stack.pop()

    for kind, indent, text in blocks(md):
        if kind == "h1":
            close_to(-1)
            title = text
        elif kind == "h2":
            close_to(-1)
            parts.append("<h2>" + inline(text) + "</h2>")
        elif kind == "p":
            # Close only the lists nested deeper than this paragraph. At indent
            # 0 that closes everything; indented, it keeps the paragraph inside
            # the list item it was written under.
            close_to(indent - 1)
            parts.append("<p>" + inline(text) + "</p>")
        else:
            if not stack or indent > stack[-1]:
                stack.append(indent)
                parts.append("<ul><li>")
            else:
                close_to(indent)
                parts.append("</li><li>")
            parts.append(inline(text))

    close_to(-1)
    return title, NL.join(parts)


def build(src_name: str, out_name: str) -> str:
    md = (DOCS / src_name).read_text(encoding="utf-8")
    title, body = render(md)
    body = body.replace("[date]", "PUBLICATION_DATE")
    warn = NL.join("     %d. %s" % (n, b) for n, b in enumerate(BLOCKERS, 1))

    page = f"""<!doctype html>
<!--
  GENERATED by tool/build_legal_pages.py from docs/{src_name}.
  Do not edit this file. Edit the source and regenerate, or the app, the repo
  and this page stop agreeing - which is exactly what App Store review checks.

  DO NOT PUBLISH until:
{warn}
-->
<html lang="en-GB">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)}</title>
<style>{CSS}</style>
</head>
<body>
<main>
<h1>{html.escape(title)}</h1>
{body}
<footer>MGKCodes Ltd &middot; <a href="mailto:hello@mgkcodes.com">hello@mgkcodes.com</a></footer>
</main>
</body>
</html>
"""
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / out_name).write_text(page, encoding="utf-8")
    return "%s  (%.1f KB)  <- docs/%s" % (out_name, len(page) / 1024, src_name)


if __name__ == "__main__":
    if not DOCS.is_dir():
        sys.exit("run this from apps/mgk_run")
    for src, dst in PAGES:
        print(build(src, dst))
