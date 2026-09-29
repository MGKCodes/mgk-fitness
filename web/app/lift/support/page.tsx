import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Lift support",
  description:
    "Get help with MGKFitness: Lift. Contact MGKCodes Ltd about a workout, your data, or a subscription.",
};

// Apple and Google both require a support URL on a listing, and both require it
// to resolve. Like Run's, it is written for the questions people actually send:
// a workout that did not save, a timer that did not buzz, a subscription.
// Both stores are named throughout, because Run's page named only Apple until a
// Play reviewer would have found it (2026-09-11).
export default function LiftSupportPage() {
  return (
    <main>
      <p className="eyebrow">MGKFitness: Lift</p>
      <h1>Support</h1>
      <p className="lede">
        Email <a href="mailto:hello@mgkcodes.com">hello@mgkcodes.com</a>. It is
        read by the person who built the app, so please say what you were doing
        when it went wrong as well as what went wrong.
      </p>

      <h2>A workout did not save, or did not back up</h2>
      <p>
        Every set is saved on your phone the moment you tick it, with or without
        a signal. If you have an account, Lift backs your workouts up when you
        open the app, when you finish a workout, and when you change a saved
        workout. It never uploads while you are lifting.
      </p>
      <p>
        The summary after a workout says <strong>Saved on this phone</strong>{" "}
        until the backup has gone through, then <strong>Backed up</strong>. If
        the server refused a workout, Settings lists it with the reason. Include
        that reason, and the date of the workout, if you write in.
      </p>

      <h2>The rest timer did not buzz</h2>
      <p>
        With the phone locked or the app in the background, the buzz comes as a
        notification, so Lift needs permission to send one. It asks the first
        time a rest starts.
      </p>
      <div className="card">
        <p>
          <strong>iPhone:</strong> Settings, Lift, Notifications, Allow
          Notifications on. A Focus mode such as Fitness or Do Not Disturb can
          hold the alert back: add Lift to the Focus mode&rsquo;s allowed apps.
          <br />
          <strong>Android:</strong> Settings, Apps, Lift, Notifications on. Some
          phones stop background apps to save battery: look for Lift under
          battery optimisation and set it to unrestricted. On Android 14 and
          later, allowing <strong>Alarms &amp; reminders</strong> for Lift makes
          the alert land on the second rather than a little late.
        </p>
      </div>

      <h2>Your data</h2>
      <p>
        Tracking needs no account, and with no account nothing leaves your
        phone. Signing in backs your workouts up to our servers so they survive a
        lost phone.
      </p>
      <p>
        You can delete everything permanently from inside the app: Profile, then
        Settings, then Privacy &amp; legal, then Delete account. If you have
        already uninstalled the app, see{" "}
        <a href="/lift/delete-account">deleting your account</a>. What is
        collected, and who receives it, is set out in the{" "}
        <a href="/lift/privacy">privacy policy</a>, and what the AI coach is sent
        in the <a href="/lift/ai-disclosure">AI disclosure</a>.
      </p>

      <h2>Subscriptions and refunds</h2>
      <p>
        The coach, training plans and progress photos are an auto-renewing
        subscription, Coach or Premium Coach, bought through the App Store or
        Google Play depending on where you installed the app. Tracking, saved
        workouts, history and stats are free and are not part of it.
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
        and say which store account you bought it with. The same goes if you
        subscribed to Liftio, which Lift replaced: sign in with the account you
        used then, and if it does not come back, tell us.
      </p>

      <h2>Health and safety</h2>
      <p>
        Lift is not a medical device and its coach does not give medical advice.
        See the <a href="/lift/terms">terms of use</a>. If something hurts, stop,
        and speak to a doctor rather than to us.
      </p>
    </main>
  );
}
