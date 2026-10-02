"use client";

import { useId, useState, type FormEvent } from "react";
import { PUBLISHABLE_KEY, SUPABASE_URL } from "../supabase";

type Stage = "asking" | "sending" | "joined" | "refused" | "failed";

/**
 * Puts an address on the list, through `core.join_waiting_list`: the one thing
 * the publishable key may do to that table. It answers the same whether or not
 * the address was already there, so this cannot tell either.
 */
async function join(email: string): Promise<Stage> {
  try {
    const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/join_waiting_list`, {
      method: "POST",
      headers: {
        apikey: PUBLISHABLE_KEY,
        "Content-Type": "application/json",
        "Content-Profile": "core",
      },
      body: JSON.stringify({ p_email: email }),
    });
    if (response.ok) return "joined";
    // 400 is the table's own checks turning the address down.
    return response.status === 400 ? "refused" : "failed";
  } catch {
    return "failed";
  }
}

const says: Record<Stage, string> = {
  // What the address is for and how to take it back, said where it is given.
  asking:
    "We will only use it to tell you when Run and Lift are live. To come off the list, email hello@mgkcodes.com.",
  sending: "Adding you…",
  joined: "You are on the list. We will email you when they are live.",
  refused: "That does not look like an email address.",
  failed: "That did not save. Try again in a minute, or email hello@mgkcodes.com.",
};

/**
 * The waiting list's form. It only collects: nothing sends the email yet.
 */
export function WaitingList() {
  const id = useId();
  const [stage, setStage] = useState<Stage>("asking");

  async function send(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    // A field no person sees or fills. Something that fills it is thanked and
    // sent nowhere, so it has no reason to try again differently.
    if (form.get("company")) return setStage("joined");
    setStage("sending");
    setStage(await join(String(form.get("email") ?? "")));
  }

  return (
    <form className="list" onSubmit={send}>
      <label htmlFor={id}>Email address</label>
      <div className="field">
        <input
          id={id}
          type="email"
          name="email"
          autoComplete="email"
          placeholder="you@example.com"
          required
          disabled={stage === "joined"}
          aria-invalid={stage === "refused"}
        />
        <input className="trap" type="text" name="company" tabIndex={-1} autoComplete="off" aria-hidden="true" />
        <button type="submit" disabled={stage === "sending" || stage === "joined"}>
          {stage === "joined" ? "On the list" : "Tell me when it is live"}
        </button>
      </div>
      <p className="note" role="status">
        {says[stage]}
      </p>
    </form>
  );
}
