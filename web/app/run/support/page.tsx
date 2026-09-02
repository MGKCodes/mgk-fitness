import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Support",
  description:
    "Get help with MGKFitness: Run. Contact MGKCodes Ltd about a recording problem, your data, or a subscription.",
};

// Apple requires a support URL on every listing, and requires it to resolve.
// This one is written to be useful rather than to satisfy the field: the three
// sections below are the three things a runner actually writes in about, and
// the last two are the ones a support email cannot fix, so they say so.
export default function RunSupportPage() {
  return (
    <main>
      <p className="eyebrow">MGKFitness: Run</p>
      <h1>Support</h1>
      <p className="lede">
        Email <a href="mailto:hello@mgkcodes.com">hello@mgkcodes.com</a>. It is
        read by the person who built the app, so please say what you were doing
        when it went wrong rather than only what went wrong.
      </p>

      <h2>A run did not record properly</h2>
      <p>
        The most useful things to include are the date and rough start time of
        the run, your iPhone model and iOS version, and whether the screen was
        locked or the app was in the background at the time.
      </p>
      <div className="card">
        <p>
          <strong>Before you write in:</strong> open Settings on your phone,
          find Run, and check Location is set to Always. Recording stops when
          the app is backgrounded if it is set to While Using.
        </p>
      </div>

      <h2>Your data</h2>
      <p>
        Runs are stored on your phone. They are only uploaded if you turned
        backup on, which is off unless you chose it.
      </p>
      <p>
        You can delete everything permanently from inside the app: Profile,
        then Settings, then Delete account. That erases your runs, plans and
        coach conversations from our systems as well as your phone. It cannot
        be undone and we cannot reverse it for you afterwards, which is the
        point of it.
      </p>
      <p>
        What is collected and who receives it is set out in the{" "}
        <a href="/run/privacy">privacy policy</a>.
      </p>

      <h2>Subscriptions and refunds</h2>
      <p>
        The coach is an auto-renewing subscription bought through the App
        Store. Recording runs is free and is not part of it.
      </p>
      <p>
        <strong>Cancel it in your Apple ID settings</strong>, not here. We
        cannot cancel a subscription for you, and we cannot issue a refund:
        Apple takes the payment and handles both. Open Settings on your phone,
        tap your name, then Subscriptions. Refunds go through{" "}
        <a href="https://reportaproblem.apple.com">reportaproblem.apple.com</a>.
      </p>
      <p>
        If you paid and the coach is still locked, that is ours to fix. Email
        us and say which Apple ID you bought it with.
      </p>

      <h2>Health and safety</h2>
      <p>
        Run is not a medical device and its coaching is not medical advice. See
        the <a href="/run/medical-disclaimer">medical disclaimer</a>. If
        something hurts, stop, and speak to a doctor rather than to us.
      </p>
    </main>
  );
}
