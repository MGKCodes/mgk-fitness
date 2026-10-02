# 0046 — A version is submitted once, and `main` is what was submitted

**Status:** Accepted, 2026-10-02. Extends
[ADR-0039](0039-one-commit-two-stores-and-the-pubspec-owns-the-build-number.md),
and changes when `develop` is promoted
([CONTRIBUTING.md](../../../../CONTRIBUTING.md), Branching).

## Context

Run 1.0.0, build 29, was submitted to the App Store and Google Play on
2 October 2026, both from `9204036`.

Until then `main` was "what has shipped", promoted "when both apps release".
Nothing had ever met that rule: Lift was not ready, so `main` was a hundred and
forty commits behind `develop` and held only the website. And nothing said what
happens to the version number once a build is with a reviewer. ADR-0039 owns
the build number and is silent on the version.

Two questions needed an answer on the day. What does `main` mean while a review
is running? And if the review comes back with something that needs a new
binary, what is that binary called?

## Decision

- **`main` is what was submitted.** `develop` is promoted to `main` when an
  app's version goes to the stores for review, not when it is approved and not
  when both apps have released. The build itself is still the tag,
  `run/build-N`, on the commit Codemagic checked out (ADR-0039): `main` may
  carry documents written on the day of the submission that the build does not.
- **A version number is submitted once.** `1.0.0` is build 29 and stays build
  29. The commit after the promotion moves `develop`'s pubspec to the next
  patch version and the next build number, `1.0.1+30`, so nothing built from
  `develop` afterwards can be mistaken for the version under review.
- **A rejection that needs a new binary is answered by the next version**, from
  `develop`. It is not answered by a second build of the rejected version, and
  it is not answered from `main`. If `1.0.0` never reaches the public, the
  first version anybody installs is `1.0.1`, and that is fine.
- **A rejection that needs no binary changes nothing here.** A screenshot, a
  description or an answer on a form is fixed in the console and resubmitted
  with the same build.
- **Work does not wait for the review.** Everything after the promotion goes on
  `develop` and belongs to the next version.

## Cost function

Both stores allow the other way: a rejected `1.0.0` can be resubmitted with
build 30 under the same version. Declining that costs a version number, and a
public history that may begin at `1.0.1`.

What it buys is one answer to "what is 1.0.0?": one build, one tag, one commit.
Under the other rule `1.0.0` is whichever build was approved, and every
document, test sheet and bug report that says "1.0.0" has to say which.

Promoting at submission costs a `main` that can hold a version nobody has yet
approved. Promoting at approval would leave `main` saying nothing useful for
the days a review takes, which is exactly when somebody asks what is in it.

## The disconfirming condition

A store that refuses a first public version other than `1.0.0`, or a review
that asks for a new build *of the same version* by name. Neither is known.

Or a rejection loop long enough that the version number runs ahead of anything
a runner has seen (`1.0.4` as the first release). At that point the number has
stopped meaning anything to them and this is worth revisiting.
