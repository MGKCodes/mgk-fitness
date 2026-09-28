import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Delete your account",
  description:
    "Delete your MGKFitness: Run account and the data held with it, from " +
    "inside the app or by asking us.",
};

// **Google Play requires this page to exist, at a URL, for any app that offers
// account creation.** The Data safety form has a field for it, and the rule
// behind the field is specific: a person who has uninstalled the app must still
// be able to ask for their account and data to be deleted. So "open the app and
// tap Delete account" does not satisfy it on its own, however good that path is
// — it is unreachable for exactly the person the rule is written for.
//
// Apple has no equivalent URL requirement (it requires the in-app path, which
// exists), which is why this page did not exist until Play was wired up.
//
// The email route below is deliberately the second option rather than the
// first: the in-app button does the deletion immediately and completely, and a
// request we service by hand is strictly worse for the person asking. It is
// here because it has to work for someone who no longer has the app.
export default function RunDeleteAccountPage() {
  return (
    <main>
      <p className="eyebrow">MGKFitness: Run</p>
      <h1>Delete your account</h1>
      <p className="lede">
        You can erase your account and everything held with it. There are two
        ways, and the first is faster, complete, and needs nothing from us.
      </p>

      <h2>If you still have the app</h2>
      <p>
        Open <strong>Profile</strong>, then <strong>Settings</strong>, then{" "}
        <strong>Delete account</strong>. It happens immediately.
      </p>

      <h2>If you have uninstalled it</h2>
      <p>
        Email <a href="mailto:hello@mgkcodes.com">hello@mgkcodes.com</a> from
        the address your account uses, with <strong>Delete my Run account</strong>{" "}
        as the subject. We will confirm when it is done.
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
        We action these within <strong>30 days</strong> and in practice within a
        few working days.
      </p>

      <h2>What gets deleted</h2>
      <p>
        Everything Run holds about you, on our systems and on your phone:
      </p>
      <ul>
        <li>your runs, including routes, distances and paces</li>
        <li>your training profile, plans and session history</li>
        <li>
          your coach conversations, including the rolling summary written from
          them
        </li>
        <li>your login, unless you also use another MGKFitness app</li>
      </ul>
      <p>
        <strong>It cannot be undone</strong>, by you or by us. There is no
        recovery window and no backup we can restore from, which is the point
        of it rather than a limitation.
      </p>

      <h2>If you also use MGKFitness: Lift</h2>
      <p>
        Deleting your Run account erases Run&rsquo;s data and keeps your login,
        so Lift and everything in it survives. Delete that account from inside
        Lift in the same way. When the last one goes, the login goes with it.
      </p>

      <h2>What survives, and why</h2>
      <p>
        Three things outlive the deletion, and none of them is training data or
        anything you wrote:
      </p>
      <ul>
        <li>
          <strong>Your usage records</strong> &mdash; how many AI requests you
          made and what they cost. They are the meter behind the fair-use
          limits, and erasing them would let a deletion reset a spend cap. They
          hold no training data and none of your messages, and they are pruned
          after 31 days whether you delete your account or not.
        </li>
        <li>
          <strong>Your subscription record.</strong> It is held by the App Store
          or Google Play, not by us. Deleting your account does not cancel a
          subscription &mdash; cancel that in the store you bought it from,
          before deleting, or you will keep being charged for a coach that is
          gone.
        </li>
        <li>
          <strong>Anything we are required to keep</strong>, such as a record of
          a payment, for as long as the law requires it.
        </li>
      </ul>

      <p>
        What is collected in the first place is set out in the{" "}
        <a href="/run/privacy">privacy policy</a>. Other questions go to{" "}
        <a href="/run/support">support</a>.
      </p>
    </main>
  );
}
