import 'package:health/health.dart';

/// **Every Health type this app reads, in one list, because the permission
/// request and the reads must not be allowed to drift apart.**
///
/// iOS grants read access per type, at the one moment the sheet is shown, and
/// then never mentions it again: a type left out of the request is not an
/// error, it is a query that quietly returns nothing forever. That is
/// indistinguishable from a runner who declined and from a phone with no data
/// (CLAUDE.md rule 6), so the failure has no symptom at all — which is exactly
/// why the list lives here and not inline at either call site.
///
/// Adding a type to this list widens the sheet the runner is shown, so it is a
/// product decision as much as a technical one. Nothing belongs here that the
/// app does not actually put on a screen.
///
/// - `WORKOUT` — runs recorded on a watch or in another app, imported into the
///   log. Distance and energy ride on the workout itself, so the quantity types
///   behind them are deliberately *not* requested.
/// - `STEPS` — the one figure on a run summary that a GPS trace cannot produce.
///   Strava's summary for the same 10 km carried 8,468 of them and ours carried
///   nothing, which is what put this here.
const List<HealthDataType> kHealthReadTypes = <HealthDataType>[
  HealthDataType.WORKOUT,
  HealthDataType.STEPS,
];

/// Read access for every type above.
///
/// Built from the list rather than written out beside it, because the plugin
/// throws `ArgumentError` when the two lengths disagree — so a type added above
/// and forgotten here would turn the app's only Health permission moment into a
/// crash. Read, and only read: this app writes nothing to Health.
List<HealthDataAccess> get kHealthReadAccess => List<HealthDataAccess>.filled(
  kHealthReadTypes.length,
  HealthDataAccess.READ,
);
