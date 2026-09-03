/// Legal documents that live somewhere other than this repository.
///
/// The privacy policy and the medical disclaimer are generated from `docs/` and
/// rendered in-app as [LegalDocument]s, so they need no URL. The Terms of Use
/// are Apple's, hosted by Apple, and so are a link rather than a document.
library;

/// Apple's standard EULA, which is the Terms of Use for this app.
///
/// Nothing to write and Apple hosts it, which is what
/// [ADR-0005](../../../../docs/decisions/0005-license-agpl.md) makes safe:
/// distributing under AGPL through the App Store is a multi-copyright-holder
/// problem and MGKCodes is the sole holder, the same position Signal is in.
///
/// **Reached from two places, deliberately.** Guideline 3.1.2 requires it on
/// the purchase surface, which is why `PurchaseScreen` carries it; but a link
/// that exists only on a paywall is unreachable by anybody who is not currently
/// buying something, including a reviewer checking Settings. `LegalScreen`
/// carries the same URL for that reason. It lives here rather than beside
/// either screen so that neither owns it — and in particular so that `legal/`
/// does not have to import `coaching/` to show a legal document.
const String kTermsOfUseUrl =
    'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
