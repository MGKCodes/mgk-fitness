import 'package:meta/meta.dart';
import 'package:mgk_units/mgk_units.dart';

/// One movement, ready to be lifted.
///
/// **The end of the untrusted road.** A movement reaches this type only after
/// something has checked it: [SwapValidator] for a mid-session swap,
/// [SessionPrescription] for a day of a standing plan. Either way the name has
/// been found in the catalogue and the weight, if there is one, was worked out
/// from this lifter's own logged sets rather than proposed by a model.
///
/// A null [target] is a real answer, not a missing one — see
/// [SessionPrescription.startingAdvice].
@immutable
class PlannedMovement {
  const PlannedMovement({
    required this.name,
    required this.sets,
    required this.reps,
    this.target,
    this.note,
  });

  final String name;
  final int sets;
  final int reps;

  /// Derived here from the lifter's own log — never read from the model, which
  /// has nowhere to put one. Null means "no number worth giving", which is a
  /// prescription rather than a gap.
  final Mass? target;

  final String? note;
}

/// A graded substitution: what the coach said, and whatever it offered that
/// survived checking.

/// A movement with a resolved target, rendered for a person.
extension PlannedMovementDisplay on PlannedMovement {
  /// `3 × 5 @ 85 kg`, or plain `3 × 8` when there is no number worth giving.
  ///
  /// The targetless form is not a degraded one. Most accessory work is
  /// programmed exactly like that, and a plan that padded it with a made-up
  /// weight to look complete would be worse in the way this whole path exists
  /// to prevent.
  String render(MassUnit unit) {
    final base = '$sets × $reps';
    final t = target;
    if (t == null) return base;
    final value = t.inDisplayUnit(unit);
    final rounded = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$base @ $rounded ${unit.isMetric ? 'kg' : 'lb'}';
  }
}
