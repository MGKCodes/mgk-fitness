import 'unit_system.dart';

/// Kilograms in one pound (exact, by international definition).
const double kilogramsPerPound = 0.45359237;

/// An immutable mass — a loaded barbell, a dumbbell, a bodyweight.
///
/// The canonical representation is **kilograms**. Pounds are derived on demand.
/// This is the "store metric, convert at display" rule in code, and it is the
/// thing Liftio got wrong: its weights were unitless numbers that took their
/// meaning from whatever the account's display setting happened to be, so
/// switching the setting silently reinterpreted every set ever logged.
///
/// Displayed in [MassUnit], which is chosen **independently of** the distance
/// unit — kilometres with pounds, or miles with kilograms, are both ordinary.
///
/// ## A caveat that does not apply to distance
///
/// Plates are discrete and the conversion is not. 100 kg is 220.462 lb, and a
/// lifter working in pounds expects to see a number they could load. So
/// [inDisplayUnit] gives the true value and [displayValue] gives the one worth
/// showing.
///
/// Switching units therefore shows the closest the rounding can get, and the
/// next weight entered is a whole value in the new unit, stored as its exact
/// equivalent. That is the accepted trade: the alternative — storing the typed
/// number alongside its unit — removes the rounding and puts the ambiguity
/// back, because then every total, record and coach brief has to convert, and
/// the one that forgets is a silent wrong answer rather than a visible round.
class Mass implements Comparable<Mass> {
  const Mass.kilograms(this.kilograms);

  factory Mass.pounds(double pounds) =>
      Mass.kilograms(pounds * kilogramsPerPound);

  /// Reads a value the lifter typed, in whatever unit they are working in.
  factory Mass.inUnit(double value, MassUnit unit) =>
      unit.isMetric ? Mass.kilograms(value) : Mass.pounds(value);

  /// The canonical value, in kilograms.
  final double kilograms;

  double get pounds => kilograms / kilogramsPerPound;

  static const Mass zero = Mass.kilograms(0);

  /// The true magnitude in [unit]. Use this for arithmetic.
  double inDisplayUnit(MassUnit unit) => unit.isMetric ? kilograms : pounds;

  /// The magnitude worth putting on screen: snapped to [MassUnit.displayStep],
  /// so a bar reads `225 lb` rather than `220.5 lb`.
  ///
  /// Never use this for sums. Round at the edge, add in kilograms.
  double displayValue(MassUnit unit) {
    final step = unit.displayStep;
    return (inDisplayUnit(unit) / step).roundToDouble() * step;
  }

  /// `100 kg` / `225 lb`. Drops a trailing `.0`, because nobody writes it.
  String label(MassUnit unit) {
    final v = displayValue(unit);
    final text = v == v.roundToDouble()
        ? v.round().toString()
        : v.toStringAsFixed(1);
    return '$text ${unit.suffix}';
  }

  Mass operator +(Mass other) => Mass.kilograms(kilograms + other.kilograms);

  /// Scales by a rep count, for volume.
  Mass operator *(num factor) => Mass.kilograms(kilograms * factor);

  @override
  int compareTo(Mass other) => kilograms.compareTo(other.kilograms);

  @override
  bool operator ==(Object other) =>
      other is Mass && other.kilograms == kilograms;

  @override
  int get hashCode => kilograms.hashCode;

  @override
  String toString() => 'Mass(${kilograms}kg)';
}
