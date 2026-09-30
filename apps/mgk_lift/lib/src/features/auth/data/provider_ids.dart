import 'package:mgk_auth/mgk_auth.dart';

/// Lift's ids for signing in with Apple and with Google.
///
/// Where each comes from, and where else it has to be, is Lift's
/// `docs/store-setup.md`, step 7. None is a secret: every sign-in sends them
/// to Google or Apple in the clear, and Supabase trusts a token only because
/// its audience is on the list in the dashboard.
///
/// **The iOS client's reversed form is also a URL scheme** in
/// `ios/Runner/Info.plist`, and the redirect is an intent filter in the
/// Android manifest. Change one here and change it there.
const ProviderIds liftProviderIds = ProviderIds(
  // `Supabase`, the web client: Android's serverClientId, and the audience.
  googleServerClientId:
      '365688330886-s5g8kf5kvmpo5qao0atqepufvfbkhmca.apps.googleusercontent.com',
  // `Lift iOS`.
  googleIosClientId:
      '365688330886-ql9t29qtqbq15ove1nv3b0irh5dhr7vu.apps.googleusercontent.com',
  redirect: 'com.mgkcodes.liftio://login-callback',
);
