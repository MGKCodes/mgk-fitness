import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/ai_consent.dart';
import 'account_ai_consent.dart';
import 'file_ai_consent_cache.dart';

/// Native default: the account's metadata, and a file for anything the account
/// has not received yet.
///
/// [client] is the one the caller already holds, so the answer is read for the
/// same session the request would be sent on. Null resolves the app's client
/// per call.
AiConsentStore createAiConsentStore({SupabaseClient? client}) =>
    AccountAiConsent(
      account: SupabaseAiConsentAccount(client: client),
      cache: FileAiConsentCache(),
    );
