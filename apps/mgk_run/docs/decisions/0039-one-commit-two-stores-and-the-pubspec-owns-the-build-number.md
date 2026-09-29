# 0039 — One commit, two stores, and the pubspec owns the build number

**Status:** Accepted. Amends [ADR-0020](0020-codemagic-is-the-build-path.md) in
three places.

## Context

[ADR-0020](0020-codemagic-is-the-build-path.md) is still marked Accepted, and
three of its statements stopped being true while it was:

1. *"One workflow, `ios-release`."* There are four release workflows in
   `codemagic.yaml` — `run-ios-release`, `run-android-release`,
   `lift-ios-release`, `lift-android-release` — plus `checks`.
2. *"No Android workflow. Runio is iOS-only … a harness, not a product."*
   [ADR-0021](0021-android-is-a-target.md) already said *"Ship Android as well as
   iOS"*, and since build 23 `run-android-release` publishes to the Play internal
   track by itself. Build 25 is on both stores' test tracks.
3. *"`PROJECT_BUILD_NUMBER` owns the build number."* Codemagic's counter is
   project-wide and diverged from the TestFlight number (docs' "build 11/12/13"
   were binaries 18/19/20). Since 0c36ec0 and 5e4a7ce the build number is the
   `+N` in `apps/mgk_run/pubspec.yaml`, and Play's versionCode and TestFlight's
   build number come from that one line.

Because nothing recorded the change, `app-store-1.0.0.md` kept a bullet saying
*"nothing ships to Play for Run at 1.0.0"*, citing ADR-0021 for the opposite of
what it says.

## Decision

- **Run 1.0.0 ships on the App Store and Google Play**, from the same commit,
  with the same build number on both.
- **The build number is `+N` in `apps/mgk_run/pubspec.yaml`**, bumped by a
  commit before a build is fired. Codemagic's counter names a Codemagic run and
  nothing else.
- **What shipped is a tag, `run/build-N`, on the commit Codemagic checked out** —
  read off the build record, not assumed from the branch tip. (Build 25's tag sat
  on a6eb6e1, whose build was cancelled; the builds that shipped came from
  12d74d8. That is the failure this rule exists for.)
- Lift keeps `$PROJECT_BUILD_NUMBER` until its App Store Connect number is known
  from the account; setting one blind would arm a failing upload.

## Cost function

A forgotten bump is found at upload, where the store refuses a repeated number.
That is loud and cheap. The failure it replaces — two numbering schemes and a
doc that cannot say which binary a tester holds — was silent and cost real
debugging time twice.

## The disconfirming condition

A store that needs different build numbers per platform for the same commit.
Neither does today.
