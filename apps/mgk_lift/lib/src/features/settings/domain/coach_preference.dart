/// Whether the lifter wants the AI coach shown at all.
///
/// **Not the consent any more.** Until 2.0.1 this switch was the only answer
/// Lift kept about the coach, on the phone and on by default, and it was
/// called consent. It was not one: nobody had said yes, and the coach's server
/// had nothing to check. The yes is now asked for and kept on the account
/// (`AiConsentStore`, issue #10). This is what is left: whether the coach mark
/// is there, and whether Plan offers to build anything.
///
/// The two still meet at one point. Turning this off takes the account's yes
/// back, because the switch has always promised that off means nothing leaves
/// the app. Turning it on does not give one; the coach asks before it first
/// sends.
///
/// **Device-local on purpose, unlike units.** Units live in `core.user_settings`
/// because they are a display choice shared with Run. Whether this phone shows
/// a coach is this phone's.
///
/// Defaulting to on is deliberate. The coach is the paid half of the product,
/// and showing it sends nothing: the first request asks first.
///
/// Neither method throws. A switch that cannot be read answers the default
/// rather than an error, and the consent is checked before every request
/// regardless of what this says.
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
