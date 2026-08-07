import 'package:meta/meta.dart';

/// What the coach proposed for one week, before anything has checked it.
///
/// These types exist so the untrusted shape has a name. A model's answer
/// arrives as JSON, becomes a [WeekProposal], and only becomes a plan by
/// passing through the validator — which is the whole of ADR-0003 in three
/// classes: **the model proposes, the validator disposes.**
///
/// **There is no weight in here, and there is none in the schema that produces
/// it.** A movement carries an [intensityPct] — a proportion of what the lifter
/// can already do — and the kilograms are worked out from their own log. A
/// prompt asking a model not to invent a number is a request; having nowhere to
/// put one is a guarantee.
@immutable
class WeekProposal {
  const WeekProposal({required this.sessions});

  final List<ProposedSession> sessions;

  /// Reads the shape the `lift_week` surface returns.
  ///
  /// Forgiving about junk and strict about types: anything malformed becomes a
  /// value the validator can reject with a sentence, rather than an exception
  /// thrown three layers below the screen that has to explain it.
  static WeekProposal fromJson(Map<String, Object?> json) {
    final raw = json['sessions'];
    return WeekProposal(
      sessions: <ProposedSession>[
        if (raw is List)
          for (final s in raw)
            if (s is Map<String, Object?>) ProposedSession.fromJson(s),
      ],
    );
  }
}

@immutable
class ProposedSession {
  const ProposedSession({
    required this.weekday,
    required this.kind,
    required this.movements,
    required this.rationale,
  });

  /// 1 = Monday through 7 = Sunday, matching ISO and the coach surfaces.
  final int weekday;

  /// `push`, `pull`, `legs`, `upper`, `lower`, `full-body`.
  final String kind;

  final List<ProposedMovement> movements;

  /// Why this session looks like this, shown to the lifter.
  final String rationale;

  static ProposedSession fromJson(Map<String, Object?> json) {
    final raw = json['movements'];
    return ProposedSession(
      weekday: _int(json['weekday']) ?? 0,
      kind: (json['kind'] as String? ?? '').trim(),
      movements: <ProposedMovement>[
        if (raw is List)
          for (final m in raw)
            if (m is Map<String, Object?>) ProposedMovement.fromJson(m),
      ],
      rationale: (json['rationale'] as String? ?? '').trim(),
    );
  }
}

@immutable
class ProposedMovement {
  const ProposedMovement({
    required this.name,
    required this.sets,
    required this.reps,
    this.intensityPct,
    this.note,
  });

  final String name;
  final int sets;
  final int reps;

  /// How hard, as a percentage of this lifter's estimated one-rep max.
  ///
  /// **Null is the expected answer more often than not** — accessory work,
  /// machines, anything bodyweight, and any movement they have never logged.
  /// A percentage on a movement with no history resolves to no weight at all,
  /// so a model that fills every slot produces a plan that looks complete and
  /// is mostly empty.
  final int? intensityPct;

  /// A cue or an effort instruction. Never a weight — the prompt forbids it
  /// and [PlanValidator] does not read one out of it.
  final String? note;

  static ProposedMovement fromJson(Map<String, Object?> json) =>
      ProposedMovement(
        name: (json['name'] as String? ?? '').trim(),
        sets: _int(json['sets']) ?? 0,
        reps: _int(json['reps']) ?? 0,
        intensityPct: _int(json['intensity_pct']),
        note: (json['note'] as String?)?.trim(),
      );
}

/// Accepts an int, or a double that is exactly one. Providers occasionally
/// return `3.0` for an integer field, and rejecting that would fail a week over
/// a JSON encoder's choice rather than over anything about the training.
int? _int(Object? value) {
  if (value is int) return value;
  if (value is double && value == value.roundToDouble()) return value.toInt();
  return null;
}
