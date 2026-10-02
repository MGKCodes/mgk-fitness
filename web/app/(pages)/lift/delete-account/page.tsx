import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Delete your Lift account",
  description:
    "Delete your MGKFitness: Lift data, or your whole MGKFitness account, " +
    "from inside the app or by asking us.",
};

// **Google Play requires this page, at a URL, for any app that offers account
// creation**, and the rule behind the Data safety field is specific: somebody
// who has uninstalled the app must still be able to ask for deletion. So the
// email route has to exist, even though the in-app one is faster and complete.
// Same reasoning as Run's page, which met the requirement first.
//
// Lift's in-app deletion asks HOW MUCH, because one login serves both apps:
// Lift's data only, or the whole account. This page describes both, in the
// words the screen uses.
export default function LiftDeleteAccountPage() {
  return (
    <main>
      <p className="eyebrow">MGKFitness: Lift</p>
      <h1>Delete your account</h1>
      <p className="lede">
        You can erase your Lift data, or your whole MGKFitness account. There are
        two ways, and the first is faster, complete, and needs nothing from us.
      </p>

      <h2>If you still have the app</h2>
      <p>
        Open <strong>Profile</strong>, then <strong>Settings</strong>, then{" "}
        <strong>Privacy &amp; legal</strong>, then{" "}
        <strong>Delete account</strong>. It asks which you mean:
      </p>
      <ul>
        <li>
          <strong>Delete my Lift data</strong> erases everything Lift holds and
          keeps your login, so MGKFitness: Run keeps working.
        </li>
        <li>
          <strong>Delete my whole MGKFitness account</strong> erases everything
          in both apps, and the login itself.
        </li>
      </ul>
      <p>
        You type DELETE to confirm, and it happens immediately. If Run holds no
        data for you, the first choice removes the login as well, since nothing
        is left for it to be for. The app tells you which happened.
      </p>

      <h2>If you have uninstalled it</h2>
      <p>
        Email{" "}
        <a href="mailto:lift@mgkfitness.mgkcodes.com">
          lift@mgkfitness.mgkcodes.com
        </a>{" "}
        from the address your account uses, with{" "}
        <strong>Delete my Lift account</strong>{" "}
        as the subject, and say whether you mean Lift&rsquo;s data or the whole
        account. We confirm when it is done.
      </p>
      <div className="card">
        <p>
          It has to come from the account&rsquo;s own email address. That is the
          only thing tying the request to the account, and we would rather
          refuse a request we cannot place than delete somebody else&rsquo;s
          training.
        </p>
      </div>
      <p>
        We act on these within <strong>30 days</strong>, and in practice within
        a few working days.
      </p>

      <h2>What gets deleted</h2>
      <p>Deleting your Lift data erases:</p>
      <ul>
        <li>your workouts, their movements and sets, and your saved workouts</li>
        <li>your training plans and the answers you gave to build them</li>
        <li>your progress photos, the picture files as well as the records</li>
        <li>
          your coach conversations, including the rolling summary written from
          them
        </li>
      </ul>
      <p>Deleting your whole account erases all of that, and also:</p>
      <ul>
        <li>everything MGKFitness: Run holds for you</li>
        <li>your login</li>
      </ul>
      <p>
        <strong>It cannot be undone</strong>, by you or by us. There is no
        recovery window and no backup we can restore from. Your phone keeps its
        own copy of your workouts until you uninstall the app.
      </p>

      <h2>What survives, and why</h2>
      <ul>
        <li>
          <strong>Usage records</strong>: how many AI requests you made and what
          they cost. They are the meter behind the fair-use limits, hold no
          training and none of your messages, and are pruned after 31 days
          whether you delete your account or not.
        </li>
        <li>
          <strong>Your subscription</strong>, which the App Store or Google Play
          holds, not us. Deleting your account does not cancel it: cancel it in
          the store first, or you keep being charged for a coach that is gone.
        </li>
        <li>
          <strong>Anything we are required to keep</strong>, such as a record of
          a payment, for as long as the law requires it.
        </li>
      </ul>

      <p>
        What is collected in the first place is set out in the{" "}
        <a href="/lift/privacy">privacy policy</a>. Other questions go to{" "}
        <a href="/lift/support">support</a>.
      </p>
    </main>
  );
}
