/// Legal documents that live somewhere other than this repository.
///
/// The privacy policy and the medical disclaimer are generated from `docs/` and
/// rendered in-app as [LegalDocument]s, so they need no URL. The Terms of Use
/// are a link, for the reason given below.
library;

/// **Our** Terms of Use, generated from `docs/terms-of-use.md` and published
/// alongside the privacy policy.
///
/// This was Apple's standard EULA until 2026-09-10. That is permitted on the
/// App Store and **is not accepted by Google Play**: a Play listing selling a
/// subscription wants terms the developer publishes. Relying on a licence
/// agreement written by a shop to cover a product that prescribes physical
/// exercise was the wrong shape anyway — Apple's EULA has nothing to say about
/// a medical disclaimer, and section 3 of ours is the part that matters most.
///
/// Apple's EULA still applies to App Store purchases as Apple requires, and
/// ours says so; where the two disagree about an App Store purchase, Apple's
/// wins. Both stores are satisfied by one document either way.
///
/// **A link rather than an in-app [LegalDocument], and deliberately so.** The
/// policy and the disclaimer are rendered in-app because they must be readable
/// with no signal — a runner on a train, a reviewer on bad hotel wifi. Terms
/// are read once, at purchase, where there is by definition a connection,
/// because the store needs one to take the money. So the offline cost is zero
/// and the benefit is real: these can be corrected without an App Store build.
///
/// **Reached from two places, deliberately.** Guideline 3.1.2 requires it on
/// the purchase surface, which is why `PurchaseScreen` carries it; but a link
/// that exists only on a paywall is unreachable by anybody who is not currently
/// buying something, including a reviewer checking Settings. `LegalScreen`
/// carries the same URL for that reason. It lives here rather than beside
/// either screen so that neither owns it — and in particular so that `legal/`
/// does not have to import `coaching/` to show a legal document.
///
/// [ADR-0005](../../../../docs/decisions/0005-license-agpl.md) is why the AGPL
/// and an App Store distribution are compatible here: it is a
/// multi-copyright-holder problem and MGKCodes is the sole holder, the same
/// position Signal is in. Section 7 of the terms leaves that licence's grants
/// intact rather than purporting to remove them.
const String kTermsOfUseUrl = 'https://mgkfitness.mgkcodes.com/run/terms';
