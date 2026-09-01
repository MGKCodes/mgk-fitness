import 'unit_system.dart';

/// Metres in one foot (exact, by international definition).
const double metresPerFoot = 0.3048;

/// An immutable vertical measurement — climb over a run, or a high point.
///
/// The canonical representation is **metres**. Feet are derived on demand, the
/// same rule [Distance], [Pace] and [Mass] follow.
///
/// ## Why it exists as a type rather than a conversion
///
/// The running app showed elevation in metres to everybody, including runners
/// working in miles, because there was nowhere to put the conversion. The
/// obvious fix — a local `* 3.28` on the screen that displays climb — is the
/// bug this package was extracted to prevent: the in-run readout, the finish
/// screen and the coach's brief would each have needed their own, and the one
/// that was forgotten would have shown a second number for the same thing.
///
/// ## It follows the DISTANCE unit, not one of its own
///
/// There is no `ElevationUnit`. A runner who chose miles gets feet, because
/// nobody measures their route in miles and their climb in metres. That is why
/// every method here takes a [UnitSystem] rather than a unit of its own, and it
/// is the difference from [Mass] — which genuinely is chosen independently,
/// since kilometres with pounds is an ordinary combination and miles with
/// metres of climb is not.
///
/// ## Rounding is to whole units, and that is not a caveat
///
/// Unlike a barbell there is nothing discrete to snap to, but there is also no
/// audience for a decimal: `312 m` and `1024 ft` are what a runner wants, and
/// `312.4 m` reads as false precision from a sensor that does not have it. So
/// [label] rounds and [inDisplayUnit] does not, and sums happen in metres.
class Elevation implements Comparable<Elevation> {
  const Elevation.metres(this.metres);

  factory Elevation.feet(double feet) => Elevation.metres(feet * metresPerFoot);

  /// Reads a value in whatever system the runner is working in.
  factory Elevation.inSystem(double value, UnitSystem system) =>
      system.isMetric ? Elevation.metres(value) : Elevation.feet(value);

  /// The canonical value, in metres.
  final double metres;

  double get feet => metres / metresPerFoot;

  static const Elevation zero = Elevation.metres(0);

  /// The true magnitude in [system]. Use this for arithmetic.
  double inDisplayUnit(UnitSystem system) => system.isMetric ? metres : feet;

  /// Short suffix for a vertical measurement, e.g. `m` or `ft`.
  static String suffix(UnitSystem system) => system.isMetric ? 'm' : 'ft';

  /// `312 m` / `1024 ft`, rounded to whole units.
  String label(UnitSystem system) =>
      '${inDisplayUnit(system).round()} ${suffix(system)}';

  Elevation operator +(Elevation other) =>
      Elevation.metres(metres + other.metres);

  @override
  int compareTo(Elevation other) => metres.compareTo(other.metres);

  @override
  bool operator ==(Object other) =>
      other is Elevation && other.metres == metres;

  @override
  int get hashCode => metres.hashCode;

  @override
  String toString() => 'Elevation(${metres}m)';
}
