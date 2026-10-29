import 'dart:async';
import 'dart:convert';

import '../domain/plan_intake.dart';
import '../domain/standing_plan.dart';
import '../domain/standing_plan_store.dart';

/// Where the live plan is kept on this phone, as one piece of JSON.
abstract interface class PlanCache {
  /// The saved JSON, or null. Must not throw.
  Future<String?> read();

  /// Must not throw.
  Future<void> write(String json);

  /// Must not throw.
  Future<void> clear();
}

/// Forgets on restart. For tests and the preview harness.
class InMemoryPlanCache implements PlanCache {
  InMemoryPlanCache([this._json]);

  String? _json;

  @override
  Future<String?> read() async => _json;

  @override
  Future<void> write(String json) async => _json = json;

  @override
  Future<void> clear() async => _json = null;
}

/// The live plan, with a copy on the phone.
///
/// **Plans lived only on the server** (*Found while planning*): a failed load
/// left the plan null, which was an inconvenience while Plan was where a
/// planned session started, and is a missing session now that it starts from
/// Track — at the gym, in the basement, with no signal. So every load that
/// reaches the server saves what it read.
///
/// **And the copy is read first** (#2). In 2.0.0 it was read only when the
/// server failed, and a server on one bar of signal takes ten to thirty
/// seconds to fail. [watch] answers with the copy at once and asks the server
/// behind it, giving up after [patience] — but only when there is a copy to
/// fall back on. With nothing saved there is nothing to show instead, and a
/// slow answer is still the only one coming.
///
/// **Saved, never edited here.** The copy is only ever the server's last
/// answer, so it cannot disagree with it about anything but freshness; a
/// replacement goes to the server first and is saved from its reply.
///
/// **Only ever shown to whoever it belongs to.** It is saved with the
/// account it was read for, and [account] is asked before it is shown: a
/// plan left by someone who signed out is not on Track for the next person,
/// or for nobody.
class CachedStandingPlanStore implements StandingPlanStore {
  CachedStandingPlanStore({
    required StandingPlanStore remote,
    required PlanCache cache,
    String? Function()? account,
    this.patience = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _remote = remote,
       _cache = cache,
       _account = account,
       _clock = clock ?? DateTime.now;

  final StandingPlanStore _remote;
  final PlanCache _cache;

  /// Who is signed in, by id. Null skips the check: a test or a preview has
  /// nobody to ask.
  final String? Function()? _account;

  /// How long the server gets when there is a copy to show instead.
  final Duration patience;

  final DateTime Function() _clock;

  /// How many plans [replace] has saved, so a read that started before one
  /// can tell its answer is out of date.
  int _replaces = 0;

  /// What the file holds. 1 was the bare plan (2.0.0). 2 wraps it with whose
  /// it is and when the server gave it, which 1 cannot say, so a 1 is read as
  /// no copy and the next answer from the server replaces it.
  static const int _format = 2;

  /// The settled answer: the server's, or the copy when it did not answer.
  @override
  Future<StandingPlan?> active() async => (await watch().last).plan;

  @override
  Stream<PlanRead> watch() async* {
    final saved = await _saved();
    if (saved != null) {
      yield PlanRead(
        saved.plan,
        freshness: PlanFreshness.saved,
        checkedAt: saved.at,
      );
    }

    final replaces = _replaces;
    StandingPlan? plan;
    try {
      final asked = _remote.active();
      plan = await (saved == null ? asked : asked.timeout(patience));
    } on Object {
      // No signal, slow signal, or the server said no. The last plan it gave
      // is still the plan: nothing on the phone could have changed it.
      yield PlanRead(
        saved?.plan,
        freshness: PlanFreshness.unreachable,
        checkedAt: saved?.at,
      );
      return;
    }

    // A plan replaced while the server was being asked is newer than its
    // answer, which may be the week it replaced. The copy stays as replace
    // left it, and that is the answer.
    if (replaces != _replaces) {
      final replaced = await _saved();
      yield PlanRead(
        replaced?.plan,
        freshness: PlanFreshness.checked,
        checkedAt: replaced?.at,
      );
      return;
    }

    final now = _clock();
    if (plan == null) {
      // No plan any more — replaced elsewhere, or signed out. Kept, it would
      // put a session on Track that nobody is following.
      await _cache.clear();
    } else {
      await _cache.write(_encode(plan, now));
    }
    yield PlanRead(plan, freshness: PlanFreshness.checked, checkedAt: now);
  }

  Future<({StandingPlan plan, DateTime at})?> _saved() async {
    final json = await _cache.read();
    if (json == null) return null;
    try {
      final file = jsonDecode(json) as Map<String, Object?>;
      if (file['format'] != _format) {
        throw const FormatException('another version of the app wrote this');
      }
      final account = _account;
      if (account != null && file['owner'] != account()) {
        // Somebody else's plan, or a signed-out phone's.
        await _cache.clear();
        return null;
      }
      return (
        plan: planFromJson(file['plan']! as Map<String, Object?>),
        at: DateTime.parse(file['checkedAt']! as String).toLocal(),
      );
    } on Object {
      // A copy that cannot be read is no copy. Never a crash: the server is
      // asked next, and its answer is saved in this version's shape.
      await _cache.clear();
      return null;
    }
  }

  String _encode(StandingPlan plan, DateTime at) =>
      jsonEncode(<String, Object?>{
        'format': _format,
        'owner': _account?.call(),
        'checkedAt': at.toUtc().toIso8601String(),
        'plan': planToJson(plan),
      });

  @override
  Future<StandingPlan> replace(StandingPlan plan, {PlanIntake? intake}) async {
    final saved = await _remote.replace(plan, intake: intake);
    _replaces++;
    await _cache.write(_encode(saved, _clock()));
    return saved;
  }
}

/// A plan as the copy on the phone holds it.
///
/// **Without each slot's history.** That is read off the log (`SlotHistory`,
/// #4), and a copy of it here could only disagree with the log. A copy saved
/// before then still carries `sessionsAtSameTop`, `lastTopKg` and
/// `lastTopReps`; they are ignored rather than read, so it stays a format 2.
Map<String, Object?> planToJson(StandingPlan p) => <String, Object?>{
  'id': p.id,
  'name': p.name,
  'dayOrder': p.dayOrder,
  'weekdays': p.weekdays,
  'rationale': p.rationale,
  'startedAt': p.startedAt?.toIso8601String(),
  'slots': <String, Object?>{
    for (final e in p.slots.entries)
      e.key: <Object?>[
        for (final s in e.value)
          <String, Object?>{
            'id': s.id,
            'role': s.role,
            'movement': s.movement,
            'isMain': s.isMain,
            'sets': s.sets,
            'reps': s.reps,
          },
      ],
  },
};

StandingPlan planFromJson(Map<String, Object?> j) => StandingPlan(
  id: j['id']! as String,
  name: j['name']! as String,
  dayOrder: <String>[
    for (final d in j['dayOrder']! as List<Object?>) d! as String,
  ],
  weekdays: <int>[for (final d in j['weekdays']! as List<Object?>) d! as int],
  rationale: j['rationale'] as String?,
  startedAt: switch (j['startedAt']) {
    final String at => DateTime.parse(at),
    _ => null,
  },
  slots: <String, List<MovementSlot>>{
    for (final e in (j['slots']! as Map<String, Object?>).entries)
      e.key: <MovementSlot>[
        for (final raw in e.value! as List<Object?>)
          switch (raw! as Map<String, Object?>) {
            final s => MovementSlot(
              id: s['id']! as String,
              role: s['role']! as String,
              movement: s['movement']! as String,
              isMain: s['isMain']! as bool,
              sets: s['sets']! as int,
              reps: s['reps']! as int,
            ),
          },
      ],
  },
);
