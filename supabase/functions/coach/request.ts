// The request guards the handler applies before anything reaches a prompt.
//
// Pure functions, split out of `index.ts` because importing that module starts
// the server, so nothing in it can be unit-tested directly. Each one is a
// finding from the 2026-09-29 pre-release review, and each says which.

import type { Body } from "./surfaces.ts";

/**
 * The most a request body may weigh, in bytes.
 *
 * Every field of the body becomes prompt text, and not every surface clamps
 * every field, so the body itself is bounded. 256 KiB is several times the
 * largest real request -- a plan with its history -- and caps what one call can
 * put in front of the model, whatever a client sends.
 */
export const MAX_BODY_BYTES = 256 * 1024;

/**
 * The body as a JSON object, or the status and error to refuse it with.
 *
 * A body that is not a JSON object is refused here rather than failing inside
 * a prompt builder, where it used to surface as "openrouter unreachable", a 502,
 * and a request counted against the runner's allowance.
 */
export function parseBody(
  raw: string,
): { body: Body } | { error: string; status: number } {
  if (new TextEncoder().encode(raw).length > MAX_BODY_BYTES) {
    return { error: "request_too_large", status: 413 };
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return { error: "bad_request", status: 400 };
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    return { error: "bad_request", status: 400 };
  }
  return { body: parsed as Body };
}

/**
 * Whether this request must name a conversation.
 *
 * Only a Lift chat turn. Lift's planning surfaces -- lift_intake, lift_plan,
 * lift_swap -- never sent one, in any version of the client, so requiring it for
 * every Lift surface answered all three with 400 from the day it shipped
 * (2026-09-01) and a lifter could not build a plan. `lift_plan` reads the
 * summary, which is keyed by user and app; an empty id reads no turns.
 */
export function conversationRequired(
  surface: string,
  hasMemory: boolean,
  conversation: string,
): boolean {
  return surface === "lift_chat" && hasMemory && conversation === "";
}

/**
 * The provider's error code, for a log line, and nothing else.
 *
 * Takes the raw body text or an already-parsed `error` value. Returns the code
 * or type when there is one and a fixed word when there is not -- never the
 * message. A moderation refusal carries `flagged_input`, which is what the
 * runner typed, and the handler used to log 300 characters of the body.
 */
export function errorCode(error: unknown): string {
  let value = error;
  if (typeof value === "string") {
    try {
      value = JSON.parse(value);
    } catch {
      return "unparsed";
    }
  }
  if (value !== null && typeof value === "object") {
    const record = value as Record<string, unknown>;
    const inner = (record.error ?? record) as Record<string, unknown>;
    const code = inner?.code ?? inner?.type;
    if (typeof code === "string" || typeof code === "number") {
      return String(code).slice(0, 60);
    }
  }
  return "no_code";
}
