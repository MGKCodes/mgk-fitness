# Naming

What each app is called, where each name is written down, and which of them can
still change. Runio and Liftio were retired as user-facing names on 2026-08-21.

## The names

| | run | lift |
|---|---|---|
| Store listing | `MGKFitness: Run` | `MGKFitness: Lift` |
| Home screen (`CFBundleDisplayName`, `android:label`) | `Run` | `Lift` |
| Bundle ID / `applicationId` | `com.mgkcodes.fitness.run` | `com.mgkcodes.liftio` |
| Dart package | `mgk_run` | `mgk_lift` |

## MGKFitness is a placeholder

It is not the right name. It is a name good enough to stop the absence of one
delaying releases, chosen on the understanding that a real consumer name
replaces it later.

Everything is built so that replacement is cheap. The platform half is written
down **once**, in `packages/mgk_ui/lib/src/brand/app_brand.dart`:

```dart
const String kPlatformName = 'MGKFitness';
```

Each app composes its own name from it in `lib/src/core/brand.dart`, and all
copy interpolates those consts. **Never type the platform name into a string.**

### What a rename costs

Change the const, then these six things by hand, because none of them can read
Dart:

1. `apps/mgk_run/ios/Runner/Info.plist` — `CFBundleDisplayName`, `CFBundleName`
2. `apps/mgk_lift/ios/Runner/Info.plist` — the same two keys
3. `apps/mgk_run/android/app/src/main/AndroidManifest.xml` — `android:label`
4. `apps/mgk_lift/android/app/src/main/AndroidManifest.xml` — `android:label`
5. App Store Connect and Play Console listing names and subtitles
6. `apps/mgk_run/docs/privacy-policy.md` and `medical-disclaimer.md`, **and
   whatever is published at the policy URL** — the in-app copy mirrors these
   word for word, and a reviewer does check that they match

Items 1–4 only change if the *app* half changes. Renaming only the platform
leaves the phone alone entirely — see below.

## Why the home screen drops the platform name

iOS truncates an icon label at roughly twelve characters. `MGKFitness: Run` and
`MGKFitness: Lift` would both render as `MGKFitness:…`, which makes two apps
from the same suite indistinguishable on the same home screen — the exact
opposite of what a shared brand is for.

So the store listing carries the platform name and the phone carries the app
name. The useful side effect is that renaming `kPlatformName` later does not
touch the device at all.

`kAppName` must stay identical to `CFBundleDisplayName` and `android:label`,
because copy sends people to *Settings › Run › Location*, and that sentence
becomes a lie the moment the two drift.

## The bundle identifier exception

`com.mgkcodes.liftio` names a product that no longer exists, and it always will.
A bundle identifier cannot be changed — a new one is a new app, with no users,
no reviews and no purchase history, and Lift is already live.

This is a deliberate exception to *"bundle identifiers name the structure, not
the product"*, not an oversight to tidy up later. Run needed no exception: it
was already `com.mgkcodes.fitness.run`.

## Writing the names in prose

First mention in a document gets the full product name. After that, say **"the
app"**.

**Never write a bare "Run" or "Lift" into a sentence.** Both apps are named
after nouns their own domain already uses, so *"your Run data"* and *"your run
data"* are the same phrase carrying different meanings and the reader cannot
tell which was meant. The full name and "the app" both dodge it; the bare app
name does not.

The coach is bound by this too — `intro_script.dart` names the product once, at
the greeting, and never again.

## What keeps the old names on purpose

These are **not** drift, and should not be swept:

- **Dart package names** (`mgk_run`, `mgk_lift`) and identifiers such as
  `RunioApp`. Renaming them is churn with no user-visible payoff.
- **ADRs, changelogs and architecture docs.** They are dated records of what was
  decided when, written when the apps were called Runio and Liftio. Rewriting
  them would falsify the history they exist to preserve.
- **Comments in `apps/mgk_lift` referring to Liftio.** Every one of them points
  at the *frozen React Native app* as a source — "Ported from Liftio", "GENERATED
  from Liftio's imageSeedData.ts". That app is a real, distinct predecessor and
  the references are accurate.
