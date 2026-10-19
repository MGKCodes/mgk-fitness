/// Signing in for the MGKCodes fitness suite.
///
/// Apple and Google through Supabase ([ProviderSignIn]), an email address with
/// the address first ([EmailSignIn]) and the rule for a new password
/// ([PasswordCheck]), and the one rule about whose training is on a phone
/// ([LocalDataGuard]), shared by Lift and Run.
library;

export 'src/email_sign_in.dart';
export 'src/local_data.dart';
export 'src/password_rule.dart';
export 'src/provider_sign_in.dart';
