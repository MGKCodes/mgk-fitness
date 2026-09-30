import 'package:mgk_auth/mgk_auth.dart';

/// Run's ids for signing in with Apple and with Google.
///
/// Where each comes from, and where else it has to be, is Lift's
/// `docs/store-setup.md`, step 7: both apps sign into one account, so the
/// providers were set up once, for the suite. None is a secret: every sign-in
/// sends them to Google or Apple in the clear, and Supabase trusts a token only
/// because its audience is on the list in the dashboard.
///
/// **The iOS client's reversed form is also a URL scheme** in
/// `ios/Runner/Info.plist`, and the redirect is an intent filter in the
/// Android manifest. Change one here and change it there.
const ProviderIds runProviderIds = ProviderIds(
  // `Supabase`, the web client: Android's serverClientId, and the audience.
  googleServerClientId:
      '365688330886-s5g8kf5kvmpo5qao0atqepufvfbkhmca.apps.googleusercontent.com',
  // `Run iOS`.
  googleIosClientId:
      '365688330886-vmjfroatcea25al1ggm524bhcfkkqqht.apps.googleusercontent.com',
  redirect: 'com.mgkcodes.fitness.run://login-callback',
  // The bundle id: who Apple issues this app's native codes to.
  appleClientId: 'com.mgkcodes.fitness.run',
);
