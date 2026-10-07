# Architecture Decision Records

An ADR captures a significant decision, the context that forced it, and the
consequences we accept. They are immutable once accepted — if a decision
changes, add a new ADR that supersedes the old one rather than editing history.

## Format

Each record uses: **Status · Context · Decision · Consequences.**

## Index

| # | Decision | Status |
|---|---|---|
| [0001](0001-flutter-ios-only.md) | Flutter, iOS only | Superseded in part by [0021](0021-android-is-a-target.md) |
| [0002](0002-no-strava-integration.md) | No Strava integration | Accepted |
| [0003](0003-llm-generates-validator-enforces.md) | LLM generates, validator enforces | Accepted |
| [0004](0004-offline-first-local-source-of-truth.md) | Offline-first; local is source of truth for live runs | Accepted |
| [0005](0005-license-agpl.md) | AGPL-3.0 license with DCO | Amended by [0048](0048-contributions-come-in-under-an-app-store-permission.md) |
| [0006](0006-in-run-audio-deferred.md) | In-run audio cues deferred to post-v1 | Accepted |
| [0007](0007-secrets-via-backend-proxy.md) | AI calls via a server-side proxy | Accepted |
| [0008](0008-shared-supabase-platform.md) | Shared Supabase project (Runio + Liftio platform) | Accepted |
| [0009](0009-greyscale-design-language.md) | Greyscale design language (unified with Liftio) | Accepted |
| [0010](0010-strength-sessions-not-prescribed.md) | Strength sessions are scheduled, not prescribed | Accepted |
| [0011](0011-a-plan-has-a-shape.md) | A plan has a shape (block / rhythm / horizon / log) | Accepted |
| [0012](0012-backup-is-consented-restore-only-adds.md) | Backup is consented, and restore only ever adds | Amended in part by [0032](0032-identity-is-an-event-and-the-tier-is-re-read.md), [0035](0035-the-phones-training-belongs-to-one-account.md) |
| [0013](0013-page-every-postgrest-read.md) | Page every PostgREST read | Accepted |
| [0014](0014-model-is-chosen-per-surface-and-per-tier.md) | The model is chosen per surface, and per tier | Amended by [0030](0030-the-coach-is-the-paid-half.md) |
| [0015](0015-spend-is-capped-over-three-windows.md) | Spend is capped over three windows, not one | Accepted |
| [0016](0016-a-run-is-editable-its-trace-is-not.md) | A run is editable; its trace is not | Accepted |
| [0017](0017-the-coach-is-the-entry-point.md) | The coach is the entry point; completion is observed | Amended by [0030](0030-the-coach-is-the-paid-half.md) |
| [0018](0018-onboarding-opens-as-a-conversation.md) | Onboarding opens as a conversation; the form comes last | Accepted |
| [0019](0019-onboarding-is-two-moments.md) | Onboarding is two moments; only the second is about a plan | Accepted |
| [0020](0020-codemagic-is-the-build-path.md) | Codemagic is the build and submit path | Amended in part by [0039](0039-one-commit-two-stores-and-the-pubspec-owns-the-build-number.md) |
| [0021](0021-android-is-a-target.md) | Android is a target, and recording must survive Doze | Accepted |
| [0022](0022-the-in-run-map-is-north-up.md) | The in-run map is north-up | Amended in part by [0031](0031-the-in-run-map-pans-and-follow-is-a-mode.md) |
| [0023](0023-the-log-is-read-from-the-phone.md) | The log is read from the phone | Accepted |
| [0024](0024-elevation-is-barometric-or-absent.md) | Elevation is barometric or absent | Accepted |
| [0025](0025-a-coach-conversation-is-a-session.md) | A coach conversation is a session, bounded by silence | Accepted |
| [0026](0026-a-record-is-a-window-in-a-trace.md) | A record is a window in a trace, not a run's own time | Accepted |
| [0027](0027-a-plan-ends-on-race-day.md) | A plan ends on race day, and the runner says how | Accepted |
| [0028](0028-revenuecat-is-the-purchase-path.md) | RevenueCat is the purchase path, and the webhook is the truth | Accepted |
| [0029](0029-what-a-tier-costs-and-buys.md) | What a tier costs, and what it buys | Amended in part by [0030](0030-the-coach-is-the-paid-half.md) and [0038](0038-premium-buys-more-coaching-not-a-different-model.md) |
| [0030](0030-the-coach-is-the-paid-half.md) | The coach is the paid half, on both apps | Amended in part by [0032](0032-identity-is-an-event-and-the-tier-is-re-read.md) |
| [0031](0031-the-in-run-map-pans-and-follow-is-a-mode.md) | The in-run map pans, and following is a mode | Accepted |
| [0032](0032-identity-is-an-event-and-the-tier-is-re-read.md) | Identity is an event, and the tier is re-read on resume | Amended in part by [0035](0035-the-phones-training-belongs-to-one-account.md) |
| [0033](0033-the-bottom-chrome-floats.md) | The bottom chrome floats, and every surface pads for it | Accepted |
| [0034](0034-a-plan-starts-on-the-coming-monday.md) | A plan starts on the coming Monday | Accepted |
| [0035](0035-the-phones-training-belongs-to-one-account.md) | The phone's training belongs to one account | Accepted |
| [0036](0036-the-coach-asks-before-it-sends.md) | The coach asks before it sends | Accepted |
| [0037](0037-the-sandbox-stays-open-in-production.md) | The sandbox stays open in production | Accepted |
| [0038](0038-premium-buys-more-coaching-not-a-different-model.md) | Premium buys more coaching, not a different model | Superseded by [0041](0041-premium-is-a-better-model-and-a-bigger-allowance.md) |
| [0039](0039-one-commit-two-stores-and-the-pubspec-owns-the-build-number.md) | One commit, two stores, and the pubspec owns the build number | Accepted |
| [0040](0040-our-terms-and-apples-eula.md) | Our terms are the terms of use; App Store Connect keeps Apple's EULA | Accepted |
| [0041](0041-premium-is-a-better-model-and-a-bigger-allowance.md) | Premium is a better model and a bigger allowance; which model is configuration | Accepted |
| [0042](0042-a-screen-that-leads-with-its-photograph.md) | A screen that leads with its photograph may carry it at strength | Accepted |
| [0043](0043-the-map-keeps-what-it-has-shown.md) | The map keeps what it has shown, and does not download what it has not | Accepted |
| [0044](0044-race-week-is-a-week-of-its-own.md) | Race week is a week of its own, and race day is on the plan | Accepted |
| [0045](0045-the-runs-figures-on-the-lock-screen.md) | A run's figures are on the lock screen, drawn natively | Accepted |
| [0046](0046-a-version-is-submitted-once.md) | A version is submitted once, and `main` is what was submitted | Accepted |
| [0047](0047-email-first-a-code-to-confirm-a-name-on-the-account.md) | Email first, a code to confirm, and a name on the account | Accepted |
| [0048](0048-contributions-come-in-under-an-app-store-permission.md) | Contributions come in under an app store permission | Accepted |
