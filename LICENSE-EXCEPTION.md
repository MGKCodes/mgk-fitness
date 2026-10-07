# Additional permission: app stores

Copyright (C) 2026 Matthew Kay and MGKCodes Ltd

The code in this repository is licensed under the GNU Affero General Public
License, version 3 ([`LICENSE`](LICENSE)), **with the additional permission
below**, which its copyright holders grant under section 7 of that licence. It
covers everything [`LICENSE`](LICENSE) covers. It does not cover `web/`, which
has a licence of its own, or the files [`NOTICE.md`](NOTICE.md) lists under
other licences.

`LICENSE` itself is the licence's text, unchanged. This file is where the
permission lives.

## The permission

> As an additional permission under section 7 of the GNU Affero General Public
> License, version 3, the copyright holders of this Program give you permission
> to convey the Program, or a work based on it, in object code form through an
> application store or similar distribution service operated by a third party
> (for example, Apple's App Store or Google Play), even where that service's
> terms of use, technical measures or conditions of distribution place
> restrictions on recipients beyond those this License allows, provided that:
>
> 1. you also make the Corresponding Source of the work you convey available to
>    every recipient, free of charge, under this License, in one of the ways
>    section 6 allows; and
>
> 2. the restrictions come only from the service's own terms, technical
>    measures or conditions of distribution, and you add no restriction of your
>    own.
>
> To the extent that a restriction meeting these conditions would otherwise
> conflict with section 6 or section 10 of this License, those sections do not
> apply to that restriction. Every other term of this License continues to
> apply, including section 13.
>
> Section 7 of this License allows you to remove this permission from your copy
> of the Program, or from any part of it, when you convey it. If you modify the
> Program, you may extend this permission to your modifications, but you are
> not obliged to.

## In plain words

**Why it exists.** Apple's App Store attaches terms of its own to every app it
delivers, such as limits on the devices an app may run on. The AGPL forbids
passing code on with restrictions it does not allow (its section 10). While all
of this code had one owner that did not matter, since a licence does not bind
the person who grants it, and the apps went into the stores on that basis
([Run ADR-0005](apps/mgk_run/docs/decisions/0005-license-agpl.md)). The moment
somebody else's code is merged, it would matter: their part reaches us only
under the AGPL, and shipping it through the App Store could break it. That is
how VLC came to be withdrawn from the App Store in 2011. This permission
settles it for everybody's code at once, and nobody has to sign anything.

**What it lets anybody do.** Ship this code, or their own version of it,
through an app store, as long as they publish the full source of what they
ship, under this same licence.

**What it does not change.** Everything else in the AGPL stands. Anybody who
ships a changed version still has to publish their changes. Anybody who runs a
changed version of the server code for other people, over the internet, still
has to offer them its source (section 13). And it applies to everybody equally:
it is not a right kept for MGKCodes.

**Contributions** are accepted under the AGPL with this permission, so it covers
every line the repository holds. [`CONTRIBUTING.md`](CONTRIBUTING.md) says so
where it asks for a sign-off.

**Not legally reviewed**, on the same terms as the apps' policies. The
permission was written on 7 October 2026, before the first contribution from
anybody outside MGKCodes, so that all of the code has been under it from the
start. [Run ADR-0048](apps/mgk_run/docs/decisions/0048-contributions-come-in-under-an-app-store-permission.md)
records why this and not a contributor agreement.
