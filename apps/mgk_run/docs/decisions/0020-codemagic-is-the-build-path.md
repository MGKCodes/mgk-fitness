# 0020 — Codemagic is the build and submit path

**Status:** Accepted
**Extends:** [0001](0001-flutter-ios-only.md)

## Context

Runio is an iOS app ([ADR-0001](0001-flutter-ios-only.md)) developed on
Windows. Every screen in it has been verified on Flutter web and an Android
emulator; **the target platform has never been built**. That is a tolerable way
to design a screen and an impossible way to ship one.

An iOS archive needs macOS and Xcode. Buying a Mac to run `flutter build ipa`
is the obvious answer and a poor one: it makes shipping depend on being at a
particular desk, and the machine spends its life idle between releases.

GitHub Actions already runs `format`, `analyze` and `test` on every push. It
does not build iOS, and pointing it at a `macos-latest` runner would mean
managing certificates, provisioning profiles and an App Store Connect key as
repository secrets — the whole signing apparatus, hand-rolled, in a repo that
is going public.

Codemagic already does this for `frunt-mobile`, and has done since that app
went to the store. The pipeline is understood, the App Store Connect
integration works, and the failure modes are familiar.

## Decision

**Builds and TestFlight submissions go through Codemagic, configured by
`codemagic.yaml` in this repo.**

One workflow, `ios-release`, triggered manually. It generates the gitignored
config from secure environment variables, runs Drift codegen, installs pods,
fetches signing, builds the IPA and publishes to TestFlight.

**In the repo, not only in the UI.** Codemagic can be configured entirely
through its web form, and for a while `frunt-mobile` was. A build defined in a
web form is a build nobody can review, diff, or explain six months later — and
the two steps here that are easy to omit and silent when omitted (codegen, and
`--dart-define-from-file`) are exactly the kind of thing that belongs under
review.

### What the CI build must not contain

The generated config writes the dev-account fields **empty**. Those credentials
drive the quick-sign-in and persona buttons, which are already `kDebugMode`-only
and tree-shaken from a release build. Writing them blank anyway is belt and
braces: a credential absent from the binary cannot be lifted out of it, and this
app holds health data.

The OpenRouter key is not in this pipeline at all and must never be. It lives in
Supabase secrets and reaches the model through the Edge Function
([ADR-0007](0007-secrets-via-backend-proxy.md)); a provider key in a Codemagic
environment group is a provider key in the app bundle.

### No Android workflow

Runio is iOS-only. The Android build exists so design work can be checked on
Windows; it is a harness, not a product. A release pipeline for it would say
otherwise, and somebody would eventually ship from it.

## The obvious alternative

**GitHub Actions on a `macos-latest` runner**, keeping all CI in one place.

Rejected on the signing apparatus rather than on the runner. Codemagic's App
Store Connect integration and code-signing identities already exist for this
Apple account and are already trusted with it; reproducing that in Actions means
base64-encoded certificates and a `.p8` key sitting in the secrets of a repo
that is about to be public. The consolidation is not worth owning that.

## Cost function

Judge this by whether a build can be fired without anybody being at a Mac. If
shipping ever waits on hardware, this has stopped paying for itself.

The accepted cost is a second CI system: Actions gates every push, Codemagic
ships. Two places to look when something is red.

## Disconfirming condition

Reverse this if the free tier stops covering the build volume, or if Codemagic's
macOS images fall behind the Xcode version App Store Connect requires — at that
point a Mac and a local `flutter build ipa` is the simpler answer, not the
harder one.

## Consequences

- The one-time UI setup is listed at the top of `codemagic.yaml`, by name, so
  the names in the file and the names in the account cannot drift silently.
- `PROJECT_BUILD_NUMBER` owns the build number, so `version:` in `pubspec.yaml`
  is the marketing version only and bumping it is a release decision rather
  than a build one.
- A build is only as honest as what it contains. At the time of writing both
  onboarding permission requests are stubs that return granted without asking
  the OS, so an IPA from this pipeline will show "Allowed" for Location and
  Health with no system dialog. That is a fine thing to put in front of
  yourself and a bad thing to put in front of a tester.
