/// Signing in for the MGKCodes fitness suite.
///
/// Apple and Google through Supabase ([ProviderSignIn]), an email address with
/// the address first ([EmailSignIn], with its steps in [EmailSignInFlow]), the
/// rule for a new password ([PasswordCheck]), the account's name
/// ([displayNameOf]), and the one rule about whose training is on a phone
/// ([LocalDataGuard]), shared by Lift and Run.
library;

export 'src/account_name.dart';
export 'src/email_address.dart';
export 'src/email_sign_in.dart';
export 'src/email_sign_in_flow.dart';
export 'src/local_data.dart';
export 'src/password_rule.dart';
export 'src/provider_sign_in.dart';
