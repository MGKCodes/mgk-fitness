# 0040 — Our terms are the terms of use; App Store Connect keeps Apple's EULA

**Status:** Accepted. Records a reversal that 8ac1181 made without one.

## Context

On 2026-09-02 the release plan settled on Apple's standard EULA as the app's
terms: nothing to write, a URL Apple hosts, and the paywall linked it.

On 2026-09-10, 8ac1181 wrote terms of our own (`docs/terms-of-use.md`, served at
`https://mgkfitness.mgkcodes.com/run/terms`), because the app gives training
advice and ships on Android, and neither the medical-disclaimer position nor an
Android customer is covered by Apple's document. `kTermsOfUseUrl` in
`lib/src/features/legal/domain/legal_urls.dart` points there; the paywall and
Settings › Privacy & legal link it, pinned by `purchase_screen_test.dart` and
`legal_screen_test.dart`.

No ADR recorded the change, so on 2026-09-29 four places still said Apple's
EULA: the release plan's Gate 2, the App Store description's terms link, the
test sheet's G9, and the live index page of `web/`.

One premise was also wrong: App Store Connect's **License Agreement** field
takes plain text (Apple's help page on custom license agreements), not a URL.

## Decision

- **Our terms are the terms of use.** The paywall, Settings, both store
  descriptions and the web index link `/run/terms`.
- **App Store Connect's License Agreement stays Apple's Standard EULA.** Our
  terms already say Apple's EULA continues to apply to App Store purchases and
  wins where the two conflict (`docs/terms-of-use.md`), so the two documents
  stack rather than compete. Pasting our terms as a custom EULA would create a
  second copy of a legal text, which this project has already learned drifts.

## Cost function

Two documents govern an iOS purchase instead of one, and a reader has to follow
the precedence clause to know which wins. That is standard for subscription apps
and cheaper than maintaining a pasted copy.

## The disconfirming condition

App Review asking for the terms in the License Agreement field itself. Then the
custom EULA is generated from `docs/terms-of-use.md` by the same tool that
renders the web page, never typed.
