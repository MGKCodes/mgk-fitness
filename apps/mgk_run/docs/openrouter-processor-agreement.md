# The OpenRouter processor agreement

Blocker 2 of the four standing between the legal pages and a published URL, and
the one with the longest lead time, because it depends on somebody else
answering. Start it before anything else in
[app-store-1.0.0.md](app-store-1.0.0.md)'s Gate 2.

**What it blocks:** `docs/privacy-policy.md` names OpenRouter as a sub-processor
receiving special-category health data. Naming a processor in a policy is a
claim that an Article 28 arrangement exists. Until one does, the policy is
describing something that has not been agreed.

---

## We are not asking from zero

Worth being clear about this before writing the email, because it changes the
question from "what do you do with our data" to "confirm in writing what we have
already built against".

The technical control is in place and guarded by a test
(`supabase/functions/coach/surfaces_test.ts`):

```ts
export const PROVIDER_ROUTING = {
  require_parameters: true,
  data_collection: "deny",
  allow_fallbacks: true,
} as const;
```

`data_collection: "deny"` is the load-bearing one. OpenRouter defaults it to
`"allow"`, which permits providers that may train on the request; the coach
sends injury notes, symptoms and whatever the runner typed, so that default was
wrong here and was changed deliberately. The reasoning is written out in full in
`surfaces.ts` and is worth restating in the email, because it is the argument
rather than a preference: explicit consent under Art. 9(2)(a) is what makes
sending the data lawful at all, it does not stretch to a third party training on
it (a different purpose, Art. 5(1)(b)), and **a provider that trains is acting
as a controller rather than a processor**, which breaks the Art. 28 chain the
policy describes.

Also relevant to how the questions are framed:

- Requests are made **server-side**, from a Supabase Edge Function, so
  OpenRouter never sees the runner's IP address or device.
- We never send name, email, account identifier, or raw GPS traces.
- The specific model is a server-side `COACH_MODEL` secret and can change
  without an app release, which is exactly why we name the gateway rather than
  one downstream provider.

---

## What their own policy already tells us

Read before sending, because it changes two of the questions from open to
pointed:

- **They do offer a DPA.** Their privacy policy says "if you have a Data
  Processing Agreement with us, the terms of that agreement and our separate
  agreements with Model Providers govern how your data is handled." So question
  1 is asking for a document that exists, not asking whether one could.
- **They hold separate agreements with model providers.** That is the mechanism
  behind `data_collection: "deny"`, and it is exactly what question 2 needs
  pinned down — a routing filter over provider-declared policy is a different
  thing from a warranty backed by those agreements.
- **OpenRouter, Inc. is a US entity**, 169 Madison Avenue, New York, NY 10016.
  So question 5 is live rather than precautionary: our storage is `eu-west-1`
  and the processor is not.

**Their contact address is Cloudflare-obfuscated on every public page**, so it
cannot be read from the site — it renders as `[email protected]` in the
policy, the terms and the DMCA notice alike. Confirm it from a logged-in account
page or a reply to an existing thread before sending.

## The email

**A draft is already in Gmail** with the body below and **no recipient**, left
empty on purpose so it cannot go to a guessed address.



> **Subject:** Data processing agreement — special-category (health) data,
> UK GDPR
>
> Hello,
>
> We run a running-coach app that sends training context and users' own messages
> to models through OpenRouter. That content is health data, and therefore
> special-category personal data under UK GDPR, so we need a processor
> arrangement in place before we publish our privacy policy and submit to the
> App Store.
>
> All our requests are made server-to-server and set
> `provider: { data_collection: "deny", require_parameters: true,
> allow_fallbacks: true }`.
>
> Five questions:
>
> 1. **Do you offer a Data Processing Agreement / Article 28 processor
>    agreement**, and can you send the current version? If there is a standard
>    one we can sign, that is ideal.
>
> 2. **What does `data_collection: "deny"` guarantee contractually**, as opposed
>    to on a best-effort basis? Specifically: is it a routing filter applied
>    against provider-declared policy, or something you warrant? We have built on
>    the assumption that a request sent with `deny` is never routed to a provider
>    that retains or trains on it, and we would like that confirmed in writing.
>
> 3. **Do you maintain a list of sub-processors** (the providers eligible to
>    serve a request under `data_collection: "deny"`), and will you notify us of
>    changes to it? We name OpenRouter in our published policy rather than one
>    downstream provider, because our model is a configuration choice — but a
>    regulator may ask who is downstream, and we would like to be able to answer.
>
> 4. **What does OpenRouter itself retain**, separately from the model provider?
>    Request and response bodies, prompts, or only metadata such as token counts
>    and model ids? If bodies are retained, for how long, and can that be
>    disabled for our account?
>
> 5. **Where is our data processed and stored**, and do you rely on the UK
>    International Data Transfer Agreement / EU Standard Contractual Clauses for
>    transfers outside the UK and EEA? Our own storage is in `eu-west-1`
>    (Ireland).
>
> Happy to sign an NDA first if that helps.
>
> Thanks,
> Matthew Kay — MGKCodes Ltd — hello@mgkcodes.com

---

## What each answer changes

| Answer | What it changes |
|---|---|
| **A DPA exists and covers special-category data** | Nothing in the policy. Sign it, file it, and this blocker closes. |
| **`deny` is contractual** | Nothing. It confirms what the code already assumes. |
| **`deny` is best-effort only** | The policy has to stop implying providers never retain. This is the answer that costs a rewrite, and the reason to ask before publishing rather than after. |
| **A sub-processor list exists** | Link or reproduce it. Strengthens the policy's "we name the gateway" position rather than weakening it. |
| **OpenRouter retains request bodies** | Must be disclosed in *Who we share it with*, and the retention period added to *Retention*. |
| **Transfers outside UK/EEA** | The policy currently says only that our own storage is `eu-west-1`. A named transfer mechanism has to be added. |

---

## If the answers are bad

Two of the outcomes above are not editorial. If `deny` turns out to be
best-effort, or OpenRouter retains bodies with no way to switch it off, then the
honest options are:

1. **Contract directly with a single model provider** who will sign an Art. 28
   agreement, and drop the gateway. Costs the model flexibility
   [ADR-0007](decisions/0007-secrets-via-backend-proxy.md) was written to buy.
2. **Keep the gateway and say so plainly** in the policy — that content may be
   retained by the provider serving the request. This is disclosure, not a fix,
   and it is a poor answer for special-category data.
3. **Ship 1.0.0 without the coach.** The tracker does not call a model at all,
   and since the account removal the app already opens on a working tracker with
   no account. The most drastic option, and the one worth remembering exists —
   the recorder is not blocked on any of this.

Do not resolve this by dropping `data_collection: "deny"`. As `surfaces.ts` puts
it: an outage is a bad evening, and training on somebody's injury notes is not
something to trade for one.
