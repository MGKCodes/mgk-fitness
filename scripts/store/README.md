# Store scripts

Run and Lift on the App Store and Google Play, driven from Claude Code
(Matthew, 5 October 2026: "pretty much every part of my workflow to be done
through Claude Code").

```
python scripts/store/stores.py status      lift                  # where each version stands
python scripts/store/stores.py links       lift                  # the public store pages, and whether each is live
python scripts/store/stores.py prepare     lift --build 52 --yes # open the version without submitting it
python scripts/store/stores.py submit      lift --ios --build 52 --notes whats-new.txt --yes
python scripts/store/stores.py submit      lift --android --notes play-notes.txt --yes
python scripts/store/stores.py test-notes  lift --ios --build 52 --notes what-to-test.txt --yes
python scripts/store/stores.py testers     lift
python scripts/store/stores.py add-tester  lift --email someone@example.com --group "Internal" --yes
python scripts/store/stores.py listing     lift --yes            # text from apps/mgk_lift/store/listing.json
python scripts/store/stores.py screenshots lift --yes            # the pictures store-shots rendered, and Play's icon
python scripts/store/stores.py release     lift --yes            # a version held for a manual release
python scripts/store/stores.py release-type run --automatic --yes  # a version already submitted: release on approval
```

**Nothing changes without `--yes`.** Every command first prints what it would
do; read the plan, then run it again with `--yes`.

**Releases go out on approval.** An iOS version is submitted to release itself
the moment Apple approves it, and an Android release goes to production for
everybody, live the moment Google approves it, as long as managed publishing
is off (Play Console › Publishing overview; check it once per app). `release`
is for later, should a version ever be held for a chosen moment instead.
`release-type --automatic` or `--manual` switches a version that is already
submitted (Run 1.0.0 went in held, before these scripts).

**An iOS version in four steps,** when anything has to be added in App Store
Connect before review (a first subscription always does):

1. `prepare --build N` creates the version, set to release on approval, with
   the build attached. It also opens the app information (name, subtitle, age
   rating) for changes.
2. `listing` and `screenshots` fill it from the repository.
3. In App Store Connect: what the API cannot do (below).
4. `submit --ios --build N` sends it for review, using the version as it is.
   If a draft submission was started in App Store Connect (its Draft
   Submissions panel, where a first subscription is added), the version goes
   into that draft and the whole draft is sent, so nothing in it is split off.
   Don't press Submit for Review on such a draft by hand first.

## The keys

Two keys of their own, made for these scripts and nothing else, kept in
`C:\Users\matty\.mgk-fitness\` (or wherever `MGK_STORE_KEYS` points). Never in
the repository, never pasted into a chat. Codemagic keeps its own, so either
can be revoked without touching the builds.

### App Store Connect

1. App Store Connect › Users and Access › Integrations › App Store Connect API
   › Team Keys › the + button.
2. Name it `Claude Code`, with **App Manager** access, and generate it.
3. Download the key, `AuthKey_<KEY ID>.p8`. Apple offers it **once**.
4. Save it in `C:\Users\matty\.mgk-fitness\`, and beside it an `asc.json`:

   ```json
   { "issuer_id": "<the Issuer ID at the top of that page>", "key_id": "<the key's Key ID>" }
   ```

A team key reaches every app on the team, Frunt's included. The scripts can
only name Run and Lift (`_common.APPS`), which is the point of going through
them.

### Google Play

1. Google Cloud console, in the project that owns
   `mgk-fitness-play-publisher` › IAM & Admin › Service accounts › that account
   › Keys › Add key › Create new key › JSON.
2. Save the file as `C:\Users\matty\.mgk-fitness\play-service-account.json`.
3. Play Console › Users and permissions › the service account: for Run and
   Lift it needs *Release to production, exclude devices, and use Play App
   Signing*, *Release apps to testing tracks*, and *Manage store presence*
   (for the listing and the pictures).

### Check

```
python scripts/store/stores.py status run
python scripts/store/stores.py status lift
```

Both stores answer, or the script says which key is missing or refused.

## What stays in the consoles

- **The privacy and rating questionnaires**: Apple's App Privacy, Play's Data
  safety, and both age ratings. The answers are drafted in each app's
  `docs/store-listing.md`.
- **A subscription's first review.** Apple takes a subscription's first
  submission only with a version: attach it on the version's page (made by
  `prepare`) before running `submit --ios` (Lift 2.0.0's Coach and Premium
  Coach).
- **App Review's sign-in and contact.** `listing` sends the notes; the demo
  login's address and password, and the contact's name, phone and email, are
  typed in on the version page, so no password passes through here.
- **Lift's first Android release.** Play treats an app as a draft until it is
  first published, and takes only draft releases for it; rolling a build out
  on internal testing does not end that (5 October 2026). So: `submit lift
  --android --draft`, then start the rollout once in Play Console ›
  Production. Every later release can go from here.
- **Sending to Google for review, sometimes.** Play can refuse to send a
  change for review from the API ("Changes cannot be sent for review
  automatically"), for instance while changes made in Play Console are waiting
  to be sent. The scripts then commit it unsent, as Play's message asks, and
  say so: press *Send changes for review* in Play Console › Publishing
  overview, which sends it with whatever else is waiting.
- **Play's internal testers by email.** Play keeps those lists out of its API;
  `testers` shows only Google Groups.

Play's release notes take 500 characters, so `--notes` for Android needs a
shorter file than iOS's What's New.

## Tests

```
python -m unittest discover -s scripts/store -p "test_*.py"
```

Offline: signing against generated keys, the two apps, and that nothing is sent
without `--yes`.
