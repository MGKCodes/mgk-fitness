import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/ai_consent.dart';
import 'account_ai_consent.dart';

/// Web default (the preview harness only). No `dart:io`, so an answer the
/// account has not received yet lasts the session. The account's own answer is
/// read the same way as on a phone.
AiConsentStore createAiConsentStore({SupabaseClient? client}) =>
    AccountAiConsent(
      account: SupabaseAiConsentAccount(client: client),
      cache: InMemoryAiConsentCache(),
    );
