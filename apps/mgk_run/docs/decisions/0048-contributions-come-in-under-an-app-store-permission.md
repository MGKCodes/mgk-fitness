# 0048 — Contributions come in under an app store permission

**Status:** Accepted, 7 October 2026. Amends [0005](0005-license-agpl.md).

## Context

[ADR-0005](0005-license-agpl.md) licensed the code AGPL-3.0 and managed
contributions with the DCO, on the ground that MGKCodes is the sole copyright
holder and so, like Signal, can ship through the App Store, whose terms add
restrictions the AGPL does not allow.

The repository went public on 7 October 2026 and asks for contributions. That
exposed a gap in 0005's reasoning. **The DCO does not keep the sole-owner
position.** A sign-off certifies that the contributor may submit their change
under the project's licence; it gives MGKCodes no right beyond that licence. So
the first merged contribution would be somebody else's code, held by us only
under the AGPL, and shipping it through the App Store could break the licence
on their part. That is the VLC case (withdrawn from the App Store in 2011 after
one of its copyright holders objected), which 0005 itself names. Signal avoids
it with a contributor licence agreement, which 0005 chose not to have.

Every one of the 726 commits so far is Matthew's, so nothing is wrong yet. The
fix has to land before the first outside contribution, not after it.

## Options

- **A contributor licence agreement (CLA).** Each contributor signs once,
  through a bot on their first pull request, giving MGKCodes broad rights over
  their contribution. Restores the sole-owner position, and keeps the option to
  relicense or sell commercial licences. Costs a signature from every
  contributor, puts some off, and gives MGKCodes a right nobody else has, on a
  project whose page says it is made with the people who use it.
- **An additional permission under the AGPL's section 7.** One paragraph,
  granted by the copyright holders: anybody may ship the code through an app
  store despite the store's own restrictions, as long as they publish the full
  source. Contributions come in under the AGPL with that permission, so it
  covers every line. Nobody signs anything, and it applies to everybody alike.
  Gives up the option to relicense other people's code.

## Decision

**The additional permission**, in [`LICENSE-EXCEPTION.md`](../../../../LICENSE-EXCEPTION.md),
beside an unchanged [`LICENSE`](../../../../LICENSE). Contributions are accepted
under the AGPL with that permission, and the DCO sign-off certifies exactly that
([`CONTRIBUTING.md`](../../../../CONTRIBUTING.md)). The DCO stays: it is still
the record that each contributor had the right to submit.

0005 stands in every other respect: AGPL-3.0, so that nobody can take the apps
closed.

## Consequences

- Run and Lift can go on being shipped through both stores with outside
  contributions in them.
- So can anybody's fork, on the same terms: they must publish the full source
  of what they ship. That is the point of the AGPL, and the permission does not
  weaken it.
- MGKCodes cannot relicense contributed code, or sell a commercial licence to
  it. If that is ever wanted, it needs a CLA from that day on, and the
  contributions before it stay as they are.
- Section 7 lets anybody remove the permission from their own copy, so a fork
  can choose to be stricter than this repository.
- Not legally reviewed. The permission's wording should be read by a solicitor,
  as should one question it does not touch: whether shipping the CC BY-SA 4.0
  exercise drawings ([Lift ADR-0003](../../../mgk_lift/docs/decisions/0003-exercise-illustrations-are-cc-by-sa.md))
  through the App Store sits with that licence's clause against downstream
  restrictions. Those drawings are not ours to grant a permission over.
