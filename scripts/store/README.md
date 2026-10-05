# Store scripts

Run and Lift on the App Store and Google Play, driven from Claude Code
(Matthew, 5 October 2026: "pretty much every part of my workflow to be done
through Claude Code").

```
python scripts/store/stores.py status      lift                  # where each version stands
python scripts/store/stores.py submit      lift --ios --build 52 --notes whats-new.txt --yes
python scripts/store/stores.py submit      lift --android --notes play-notes.txt --yes
python scripts/store/stores.py test-notes  lift --ios --build 52 --notes what-to-test.txt --yes
python scripts/store/stores.py testers     lift
python scripts/store/stores.py add-tester  lift --email someone@example.com --group "Internal" --yes
python scripts/store/stores.py listing     lift --yes            # text from apps/mgk_lift/store/listing.json
python scripts/store/stores.py screenshots lift --yes            # the pictures store-shots rendered
python scripts/store/stores.py release     lift --yes            # a version held for a manual release
```

**Nothing changes without `--yes`.** Every command first prints what it would
do; read the plan, then run it again with `--yes`.

**Releases go out on approval.** An iOS version is submitted to release itself
the moment Apple approves it, and an Android release goes to production for
everybody, live the moment Google approves it, as long as managed publishing
is off (Play Console › Publishing overview; check it once per app). `release`
is for later, should a version ever be held for a chosen moment instead.

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
  submission only with a version: attach it on the version's page before
  running `submit --ios` (Lift 2.0.0's Coach and Premium Coach).
- **Lift's first Android release.** Play takes only a draft for an app that has
  never rolled one out: `submit lift --android --draft`, then roll it out once
  in Play Console. Every later release can go from here.
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
