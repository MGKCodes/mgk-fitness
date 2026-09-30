import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Support",
  description:
    "Get help with MGKFitness: Run. Contact MGKCodes Ltd about a recording problem, your data, or a subscription.",
};

// Apple and Google both require a support URL on a listing, and both require it
// to resolve. This one is written to be useful rather than to satisfy the field:
// the sections below are the things a runner actually writes in about, and the
// ones a support email cannot fix say so.
//
// **It named only Apple until 2026-09-11** -- iPhone models, iOS versions,
// "cancel it in your Apple ID settings", reportaproblem.apple.com. Written when
// iOS was the only target, and left standing when Android was wired up, so a
// Play reviewer following the listing's own support link would have found a
// page that did not admit their platform exists. Same defect as the paywall's
// Apple ID wording (4ae7615), found the same day, in the same way: by looking
// at the product as an Android user rather than as its author.
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
        the run, your phone model and its OS version, and whether the screen was
        locked or the app was in the background at the time.
      </p>
      <div className="card">
        <p>
          <strong>Before you write in</strong>, check the location setting. Run
          only ever asks to use your location while you are using the app, and
          that is all it needs: a run you start keeps recording with the screen
          locked and the phone in a pocket. It never asks for &ldquo;Always&rdquo;.
          What it does need is your precise location, because an approximate
          one is too coarse to draw a route.
        </p>
        <p>
          <strong>iPhone:</strong> Settings, Run, Location &rarr; While Using
          the App, with Precise Location on.
          <br />
          <strong>Android:</strong> Settings, Apps, Run, Permissions, Location
          &rarr; Allow only while using the app, with Use precise location on.
          While a run is recording, Android shows a &ldquo;Recording your
          run&rdquo; notification if notifications are allowed for Run. Some
          phones also hold a separate battery
          setting that stops apps in the background &mdash; if runs cut short,
          look for Run under battery optimisation and set it to unrestricted.
        </p>
      </div>

      <h2>Your data</h2>
      <p>
        Runs are stored on your phone. They are only uploaded if you turned
        backup on, which is off unless you chose it.
      </p>
      <p>
        You can delete everything permanently from inside the app: open the
        Profile tab, tap the gear at the top right for Settings, then Privacy
        &amp; legal, then Delete account. That erases your runs, plans and coach
        conversations from our systems, and from your phone unless you choose
        to keep that copy. It cannot be undone and we cannot reverse it for you
        afterwards, which is the point of it. If you have already uninstalled
        the app, see <a href="/run/delete-account">deleting your account</a>.
      </p>
      <p>
        What is collected and who receives it is set out in the{" "}
        <a href="/run/privacy">privacy policy</a>.
      </p>

      <h2>Subscriptions and refunds</h2>
      <p>
        The coach is an auto-renewing subscription bought through the App Store
        or Google Play, depending on where you installed the app. Recording runs
        is free and is not part of it.
      </p>
      <p>
        <strong>Cancel it in the store you bought it from</strong>, not here. We
        cannot cancel a subscription for you and we cannot issue a refund: the
        store takes the payment and handles both.
      </p>
      <p>
        <strong>iPhone:</strong> Settings, tap your name, then Subscriptions.
        Refunds go through{" "}
        <a href="https://reportaproblem.apple.com">reportaproblem.apple.com</a>.
        <br />
        <strong>Android:</strong> open the Play Store, tap your profile picture,
        then Payments &amp; subscriptions. Refunds go through{" "}
        <a href="https://support.google.com/googleplay/answer/2479637">
          Google Play support
        </a>
        .
      </p>
      <p>
        If you paid and the coach is still locked, that is ours to fix. Email us
        and say which store account you bought it with.
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
