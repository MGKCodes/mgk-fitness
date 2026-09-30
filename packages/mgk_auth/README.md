# mgk_auth

Signing in for the MGKCodes fitness suite. Lift and Run share one account
(one Supabase project, one Apple App ID group, one Google Cloud project), so
the way into it is written once, here.

- **`ProviderSignIn`**: Apple and Google into Supabase. Apple is native on iOS
  (a hashed nonce to Apple, the raw one to Supabase) and a browser sign-in on
  Android, back through `<package>://login-callback`. Google is native on both.
  Each app passes its own `ProviderIds`; where each id comes from is Lift's
  `docs/store-setup.md`, step 7.
- **`LocalDataGuard`**: whose training is on this phone. The first account to
  sign in owns it; a different account is asked to erase it or sign out before
  anything backs up. Each app supplies what "its training" means
  (`LocalTrainingData`) and where the owner is kept (`LocalDataOwnerStore`).

Not UI. The buttons are `mgk_ui`'s `ProviderSignInButton`, and the question a
second account is asked is `mgk_ui`'s `AnotherAccountScreen`.

Tests run a real `GoTrueClient` over a mock HTTP client, so they check what is
actually sent to Supabase, nonce included:

```
cd packages/mgk_auth && flutter test
```
