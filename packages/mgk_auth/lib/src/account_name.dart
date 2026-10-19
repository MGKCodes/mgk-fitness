/// The account's name, and the two facts about an account the sign-in needs:
/// whether it was just made, and what Google called its owner.
///
/// Run's ADR-0047, "The name belongs to the account": one name for the
/// MGKFitness account, shown by both apps and used by Run's coach, kept in the
/// user's metadata as [kDisplayNameKey].
library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Where the account's name is kept in the user's metadata.
///
/// **Not `name`**, which Supabase overwrites with Google's profile on every
/// Google sign-in. Run kept the coach's name there until 1.0.2; [displayNameOf]
/// still reads it where Google cannot have written it.
const String kDisplayNameKey = 'display_name';

/// The account's name, or null where it has none.
///
/// [kDisplayNameKey] first. Failing that, the `name` Run used to write, but
/// only on an account with no Google identity: on one with, `name` is
/// whatever Google last sent, which the runner never chose.
String? displayNameOf(User? user) {
  final metadata = user?.userMetadata;
  final chosen = _trimmed(metadata?[kDisplayNameKey]);
  if (chosen != null) return chosen;
  if (hasIdentity(user, 'google')) return null;
  return _trimmed(metadata?['name']);
}

/// Whether [user] can sign in with [provider] (`apple`, `google`, `email`).
///
/// Either record answers: `identities` is what the deletion's revocation
/// reads, and the `providers` list is there on a session restored without them.
bool hasIdentity(User? user, String provider) {
  if (user == null) return false;
  if (user.identities?.any((i) => i.provider == provider) ?? false) {
    return true;
  }
  final providers = user.appMetadata['providers'];
  return providers is List && providers.contains(provider);
}

/// The first name Google gave, to start the name step filled in, or null.
///
/// Only for an account with a Google identity, and only the first word of the
/// name Google sent: nobody has to use the name their provider holds, and a
/// first name is what the step asks for. **Never Apple's**: nothing asks for a
/// name after Sign in with Apple, so there is nothing to fill in.
String? googleFirstNameOf(User? user) {
  if (!hasIdentity(user, 'google')) return null;
  final metadata = user?.userMetadata;
  final full =
      _trimmed(metadata?['full_name']) ??
      _trimmed(metadata?['name']) ??
      _trimmed(metadata?['given_name']);
  if (full == null) return null;
  return full.split(RegExp(r'\s+')).first;
}

/// Whether [user]'s account was made by the sign-in that just happened.
///
/// **Read from the account, for every way in** (the ADR's point 7), not from
/// which button was pressed: Apple and Google make an account or sign into one
/// without saying which, and Apple's browser flow on Android finishes after
/// its call has returned.
///
/// True when the account was created within [window] of its latest sign-in.
/// Generous on purpose: an email account is made at one moment and signed in
/// when its code is typed, which can be minutes later. A returning account was
/// made days ago, so the window does not have to be tight to tell them apart.
bool accountIsNew(User? user, {Duration window = const Duration(minutes: 30)}) {
  if (user == null) return false;
  final created = DateTime.tryParse(user.createdAt);
  final signedIn = DateTime.tryParse(user.lastSignInAt ?? '');
  if (created == null || signedIn == null) return false;
  return signedIn.difference(created) <= window;
}

String? _trimmed(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
