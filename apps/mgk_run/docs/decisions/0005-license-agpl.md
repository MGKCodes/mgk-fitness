# 0005 — AGPL-3.0 license with DCO sign-off

**Status:** Accepted

## Context

Runio is both a **shippable product** (headed for the App Store) and a **public
showcase** for MGKCodes. Two goals pull in different directions:

- A permissive license (MIT/Apache-2.0) maximises reuse and contributions, but
  lets anyone reskin Runio and ship a closed-source competitor.
- A copyleft license keeps derivatives open, but raises the usual "GPL can't go
  on the App Store" concern.

That App Store concern is a multi-copyright-holder problem (it blocked VLC),
**not** a copyleft problem per se: Signal ships on the App Store under AGPL-3.0
because a single entity controls the copyright and can grant Apple's required
terms. MGKCodes is in that same sole-owner position.

## Decision

License Runio under **AGPL-3.0**. Manage contributions with a **Developer
Certificate of Origin (DCO)** — a per-commit `Signed-off-by` — rather than a
full CLA. This keeps the contribution trail clean enough for MGKCodes to
distribute the app under Apple's terms while every public fork stays open.

## Consequences

- Public forks and derivatives must remain open under AGPL-3.0; nobody can take
  Runio closed and compete.
- The showcase goal is fully met — the code is 100% public and readable.
- Contributors must sign off commits (`git commit -s`); unsigned commits are
  asked to amend (see [CONTRIBUTING.md](../../../../CONTRIBUTING.md)).
- MGKCodes, as sole copyright holder, retains the right to distribute via the
  App Store and to relicense if ever needed.
- Reversible: switching to a permissive license later is a one-file change while
  the repo is still private. We are private-first for exactly this reason.
