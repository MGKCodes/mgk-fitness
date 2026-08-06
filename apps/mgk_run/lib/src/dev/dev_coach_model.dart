import 'package:flutter/foundation.dart';

import '../features/coaching/data/coach_service.dart';

/// A model the **debug build** can point the coach at, so two models can be
/// compared by tapping rather than by editing a Supabase secret and waiting.
///
/// Choosing a model is the one job the production design deliberately makes
/// slow: every id is server-side configuration (ADR-0007), which is right for a
/// shipped app and miserable while deciding. Without this, each comparison is a
/// dashboard round trip, so in practice you compare two models instead of ten.
///
/// **The app cannot pick a model on its own.** What it sends is a request, and
/// the coach function honours it only if the id appears verbatim in the
/// server's `COACH_MODEL_ALLOWLIST`. With that secret unset — production — the
/// request is ignored entirely. So this list is a convenience, never an
/// authority: adding an entry here grants nothing until the server publishes
/// the same id.
class CoachModelChoice {
  const CoachModelChoice({
    required this.id,
    required this.label,
    required this.blurb,
  });

  /// The OpenRouter id, exactly as the API lists it. These are **dated** for
  /// most providers, and a slug without its date is a different string that
  /// resolves to nothing: OpenRouter answers 404 and the coach surfaces
  /// `coach_upstream`. Copy them, do not retype them.
  final String id;

  /// What to call it in the list.
  final String label;

  /// Price per million tokens, in and out, so the cost of the thing being
  /// compared is visible next to the answer it produced.
  final String blurb;
}

/// The candidates, cheapest first.
///
/// Deliberately spans two orders of magnitude. The point of the exercise is to
/// find where quality actually falls off, and that question is unanswerable
/// from a list of models that all cost roughly the same.
///
/// PRIVACY: several of these are served outside the UK/EU. That is acceptable
/// for a dev account talking about invented training, and it is NOT acceptable
/// for the `chat` surface in production, which carries a runner's own words
/// about their body. Deciding a production chat model is a separate question
/// from this list — see docs/privacy-policy.md before promoting any of them.
const List<CoachModelChoice> coachModelChoices = <CoachModelChoice>[
  CoachModelChoice(
    id: 'nex-agi/nex-n2-mini',
    label: 'Nex N2 Mini',
    blurb: r'$0.025 / $0.10 — the cheapest thing that claims structured output',
  ),
  CoachModelChoice(
    id: 'google/gemini-3.1-flash-lite-20260507',
    label: 'Gemini 3.1 Flash Lite',
    blurb: r'$0.25 / $1.50 — the current COACH_MODEL default',
  ),
  CoachModelChoice(
    id: 'minimax/minimax-m3-20260531',
    label: 'MiniMax M3',
    blurb: r'$0.30 / $1.20',
  ),
  CoachModelChoice(
    id: 'qwen/qwen3.7-plus-20260602',
    label: 'Qwen 3.7 Plus',
    blurb: r'$0.32 / $1.28',
  ),
  CoachModelChoice(
    id: 'z-ai/glm-5.2-20260616',
    label: 'GLM 5.2',
    blurb: r'$0.77 / $2.42',
  ),
  CoachModelChoice(
    id: 'google/gemini-3.6-flash-20260721',
    label: 'Gemini 3.6 Flash',
    blurb: r'$1.50 / $7.50 — the COACH_CHAT_MODEL candidate',
  ),
  CoachModelChoice(
    id: 'anthropic/claude-sonnet-5-20260630',
    label: 'Claude Sonnet 5',
    blurb: r'$2.00 / $10.00 — the quality ceiling worth measuring against',
  ),
];

/// The model the debug build is currently asking for, or null for "whatever the
/// server is configured to use".
///
/// A top-level notifier for the same reason [devPersona] is one: it is read
/// deep inside the data layer and written from a leaf of Settings, and
/// threading a controller between them would put dev plumbing in the signature
/// of everything in between.
///
/// Always null in a release build — see [setDevCoachModel].
final ValueNotifier<String?> devCoachModel = ValueNotifier<String?>(null);

/// Asks the coach for [id], or null to let the server decide.
///
/// A **no-op in release**, so no call site can make the shipped app name a
/// model even by mistake. That matters more here than for a persona: a shipped
/// build that asked for a model would be a client choosing what the account
/// pays per token.
/// Writes both the notifier the UI watches and the field [CoachService] reads,
/// so there is one call site and they cannot disagree. A listener would be the
/// alternative and would have to be registered somewhere at startup — one more
/// piece of dev plumbing in production wiring.
void setDevCoachModel(String? id) {
  if (!kDebugMode) return;
  final next = (id != null && id.trim().isEmpty) ? null : id;
  devCoachModel.value = next;
  CoachService.debugModelOverride = next;
}
