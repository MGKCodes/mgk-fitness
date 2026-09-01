/// Whether the lifter wants the AI coach at all.
///
/// **Device-local on purpose, unlike units.** Units live in `core.user_settings`
/// because they are a display choice shared with Run and one person wants one
/// answer. This is not a display choice: it is consent to send what you write
/// to a third party, and consent belongs to the person on the device in front
/// of them, not to an account row that a restore could quietly flip back on.
///
/// Defaulting to on is deliberate. The coach is the paid half of the product,
/// and Guideline 5.1.2(i) asks for the disclosure to be *visible before the
/// data goes*, not for the feature to be off until found — which is why the
/// coach screen carries the disclosure at the point of use and this switch sits
/// next to it. See `docs/ai-disclosure.md`.
///
/// Neither method throws. A consent switch that cannot be read must fail
/// **safe for the product and honest for the person**: [load] answers the
/// default rather than an error, and the disclosure is on screen either way.
abstract interface class CoachPreferenceStore {
  /// Whether the coach is enabled. True when this device has never been asked.
  Future<bool> load();

  Future<void> save({required bool enabled});
}

/// Keeps the choice for the session only. What tests and the preview want, and
/// the fallback when there is no plugin to store it in.
class InMemoryCoachPreference implements CoachPreferenceStore {
  InMemoryCoachPreference({this.enabled = true});

  bool enabled;

  @override
  Future<bool> load() async => enabled;

  @override
  Future<void> save({required bool enabled}) async => this.enabled = enabled;
}
