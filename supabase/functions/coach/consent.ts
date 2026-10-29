// Whether the caller agreed to their training being sent to the AI provider.
//
// ADR-0036 made the app ask before the coach sends anything, and said the
// service refuses without an answer. Until this module the refusal lived only
// on the phone, so a build with a bug, an older client or a hand-made request
// reached the provider with no yes on record. This is the same rule, read from
// the same place, at the one gate every request passes.
//
// Pure, like `tierFor`: it takes the user object `/auth/v1/user` already
// returned for the signed-in check, so it costs no extra round trip and has no
// failure of its own to map. Anything it cannot read is a no.
//
// SCOPE: both apps, each with its own key. Run's from 27 October 2026; Lift's
// from its 2.0.1, which is the first Lift that asks and keeps the answer on the
// account. Lift 2.0.0 kept a coach switch on the phone, on by default, and
// wrote nothing here, so from the deploy that adds `lift` its users are refused
// until they update: they never said yes. Deploy it only once 2.0.1 is live on
// both stores (issue #10).
//
// LIMIT: `user_metadata` is writable by the user it belongs to. This stops a
// client that never asked; it does not stop somebody writing their own yes,
// which is their own consent to give.
//
// PRIVACY: reads one key of the metadata and keeps nothing.

import type { App } from "./surfaces.ts";

/**
 * The question's current version. Mirrors `kAiConsentVersion` in both apps'
 * `lib/src/features/coaching/domain/ai_consent.dart`: raise them together, or
 * the server refuses answers an app accepts (or the reverse).
 */
export const AI_CONSENT_VERSION = 1;

/**
 * Where each app keeps its answer in auth user metadata. An app missing here
 * is not checked by the server (see SCOPE above).
 */
export const CONSENT_KEYS: Partial<Record<App, string>> = {
  run: "run_ai_consent",
  lift: "lift_ai_consent",
};

/** Whether requests for `app`'s surfaces must carry a yes on the account. */
export function consentChecked(app: App): boolean {
  return CONSENT_KEYS[app] !== undefined;
}

/**
 * Whether `user` (the body `/auth/v1/user` returned) has agreed to the
 * current version of `app`'s question.
 *
 * Mirrors `AiConsent.fromJson` and `isCurrent`: the stored shape is
 * `{"version": 1, "at": "<ISO-8601 UTC>"}`. A version that is not a number, a
 * date that does not parse, an older version or a missing key all read as no.
 * A withdrawal is the key being removed, so it reads as no too.
 */
export function hasAiConsent(app: App, user: unknown): boolean {
  const key = CONSENT_KEYS[app];
  if (key === undefined) return false;
  if (typeof user !== "object" || user === null) return false;
  const meta = (user as { user_metadata?: unknown }).user_metadata;
  if (typeof meta !== "object" || meta === null) return false;
  const answer = (meta as Record<string, unknown>)[key];
  if (typeof answer !== "object" || answer === null || Array.isArray(answer)) {
    return false;
  }
  const { version, at } = answer as Record<string, unknown>;
  if (typeof version !== "number" || !Number.isFinite(version)) return false;
  if (typeof at !== "string" || Number.isNaN(Date.parse(at))) return false;
  return Math.trunc(version) >= AI_CONSENT_VERSION;
}
