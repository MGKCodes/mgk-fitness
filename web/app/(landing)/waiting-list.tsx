"use client";

import { useId, useState, type FormEvent } from "react";

/**
 * The waiting list's form.
 *
 * **It does not save anything yet.** An address collected for launch news is
 * personal data, so the list needs a table to hold it, wording that says what
 * the address is for, and a line in both apps' privacy policies before it can
 * take one. Until then sending the form says the list is not open, which is
 * true, rather than thanking somebody for an address that went nowhere.
 */
export function WaitingList() {
  const id = useId();
  const [asked, setAsked] = useState(false);

  function send(event: FormEvent) {
    event.preventDefault();
    setAsked(true);
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
        />
        <button type="submit">Tell me when it is live</button>
      </div>
      <p className="note" role="status">
        {asked
          ? "The list is not open yet. Come back soon."
          : "An email when Run and Lift are in the stores."}
      </p>
    </form>
  );
}
