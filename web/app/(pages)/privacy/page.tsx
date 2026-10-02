import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Privacy on this website",
  description:
    "What mgkfitness.mgkcodes.com collects: an email address if you join the waiting list, and nothing else. No cookies and no analytics.",
};

// The website's own privacy notice. The apps' policies are generated from each
// app's `docs/` because the app has to show the same words; nothing else shows
// these, so they are written here, like the support pages.
//
// **Not legally reviewed**, on the same terms as the apps' policies: every
// statement of fact below was checked against the site and the database rather
// than written from intent, and its legal form is unreviewed.
//
// What was checked, on 2 October 2026:
// - The site sets no cookie, uses no browser storage and loads nothing from a
//   third party: nothing in `app/` touches `document.cookie`, local or session
//   storage, and the font is served from this domain by `next/font`.
// - The waiting list is `core.waiting_list`. It keeps the address, a source and
//   a time, and is written only through `core.join_waiting_list`, which cannot
//   be made to say whether an address is on it.
// - The Supabase project is in eu-west-1, as both apps' policies say.
//
// **Two sentences here are promises, not descriptions**, and somebody has to
// keep them: the list is deleted once both apps are live and people have been
// told, and this page names whoever sends that email before it is sent.
// Nothing sends it yet.
//
// If the site starts to collect anything else, it is said here first.
export default function PrivacyPage() {
  return (
    <main>
      <p className="eyebrow">MGKFitness</p>
      <h1>Privacy on this website</h1>
      <p className="lede">
        This is mgkfitness.mgkcodes.com, the website for MGKFitness: Run and
        MGKFitness: Lift. It sets no cookies and runs no analytics. The one thing
        it asks you for is an email address, and only if you join the waiting
        list.
      </p>
      <p>
        <strong>Last updated:</strong> 2 October 2026 · <strong>Controller:</strong>{" "}
        MGKCodes Ltd · <strong>Contact:</strong>{" "}
        <a href="mailto:hello@mgkcodes.com">hello@mgkcodes.com</a>
      </p>
      <div className="card">
        <p>
          The apps have policies of their own, because they hold your training
          and this site does not: <a href="/run/privacy">Run&rsquo;s privacy policy</a>{" "}
          and <a href="/lift/privacy">Lift&rsquo;s privacy policy</a>.
        </p>
      </div>

      <h2>The waiting list</h2>
      <p>If you give us your email address on the home page, we keep:</p>
      <ul>
        <li>the address;</li>
        <li>when you gave it;</li>
        <li>that you gave it on this website.</li>
      </ul>
      <p>
        We use it for one thing: to tell you when Run and Lift are in the App
        Store and on Google Play. We do not add you to anything else, and we do
        not sell it or pass it to anybody for their own use.
      </p>
      <p>
        <strong>You asked to be told, so the basis is your consent</strong>, and
        you can take it back at any time. Email{" "}
        <a href="mailto:hello@mgkcodes.com">hello@mgkcodes.com</a> and we will
        remove your address.
      </p>
      <p>
        We keep the list until both apps are in the stores and we have told you
        so. Then we delete it.
      </p>
      <p>
        It is stored in our database at Supabase, in eu-west-1 (Ireland). The
        form can add an address and cannot read the list back, so nobody can use
        it to find out whether you are on it.
      </p>
      <p>
        Nothing sends email to the list yet. Before anything does, this page
        will name the provider that sends it.
      </p>

      <h2>What the site receives when you visit</h2>
      <ul>
        <li>
          <strong>Vercel</strong> hosts the site. To send you a page it receives
          your IP address and your browser&rsquo;s details, as any web host does,
          and may keep them in its logs. Vercel is a company in the United
          States, so this may be handled outside the UK.
        </li>
        <li>
          <strong>Supabase</strong> receives the same when you send the waiting
          list form or set a new password, because for those two things your
          browser talks to our database directly.
        </li>
      </ul>
      <p>
        That is all of it. There are <strong>no cookies</strong>, nothing is kept
        in your browser, and there is no analytics, advertising or tracking of
        any kind. The fonts and pictures come from this site, not from somebody
        else&rsquo;s.
      </p>

      <h2>Setting a new password here</h2>
      <p>
        The link in a password email opens a page on this site. It sends your new
        password to our sign-in service at Supabase, signs you out again and
        keeps nothing. What we hold about your account is in each app&rsquo;s
        policy.
      </p>

      <h2>If you email us</h2>
      <p>We use what you send to answer you, and for nothing else.</p>

      <h2>Your rights</h2>
      <p>
        Under UK GDPR you can ask to see what we hold about you, have it
        corrected or deleted, and withdraw consent. For the waiting list that is
        one email to <a href="mailto:hello@mgkcodes.com">hello@mgkcodes.com</a>.
      </p>
      <p>
        If you think we have handled your data wrongly, you can complain to the
        Information Commissioner&rsquo;s Office at{" "}
        <a href="https://ico.org.uk/make-a-complaint/">ico.org.uk</a>. We would
        rather you told us first, so that we can put it right.
      </p>

      <h2>Children</h2>
      <p>
        This site is not directed at children under 16 and we do not knowingly
        collect their data.
      </p>

      <h2>Changes</h2>
      <p>
        We will update this page when the site changes, and change the date at
        the top.
      </p>

      <h2>Contact</h2>
      <p>
        MGKCodes Ltd, at <a href="mailto:hello@mgkcodes.com">hello@mgkcodes.com</a>.
      </p>
    </main>
  );
}
