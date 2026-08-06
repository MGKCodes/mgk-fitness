import '../../recording/domain/run_point.dart';
import '../../recording/domain/run_split.dart';
import '../../recording/domain/run_summary.dart';

/// Maps rows from the `runio` schema (snake_case JSON from PostgREST) into the
/// domain models. Pure and fixture-tested — the Supabase client that fetches the
/// rows can't run off-device, but the mapping is where the bugs would hide.

double _toDouble(Object? v) => (v as num).toDouble();
double? _toDoubleOrNull(Object? v) => (v as num?)?.toDouble();
int _toInt(Object? v) => (v as num).toInt();
int? _toIntOrNull(Object? v) => (v as num?)?.toInt();

RunSummary runSummaryFromRow(
  Map<String, dynamic> row, {
  List<RunPoint> points = const <RunPoint>[],
  List<RunSplit> splits = const <RunSplit>[],
}) => RunSummary(
  id: row['id'] as String?,
  startedAt: DateTime.parse(row['started_at'] as String),
  duration: Duration(seconds: _toInt(row['duration_s'])),
  distanceMeters: _toDouble(row['distance_m']),
  avgPaceSecondsPerKm: _toDoubleOrNull(row['avg_pace_s_per_km']),
  elevationGainMeters: _toDoubleOrNull(row['elevation_gain_m']),
  avgHr: _toIntOrNull(row['avg_hr']),
  maxHr: _toIntOrNull(row['max_hr']),
  caloriesEst: _toDoubleOrNull(row['calories_est']),
  type: (row['type'] as String?) ?? 'outdoor',
  points: points,
  splits: splits,
);

RunPoint runPointFromRow(Map<String, dynamic> row) => RunPoint(
  latitude: _toDouble(row['lat']),
  longitude: _toDouble(row['lng']),
  accuracyMeters: _toDouble(row['accuracy_m']),
  altitudeMeters: _toDoubleOrNull(row['altitude_m']),
  timestamp: DateTime.parse(row['recorded_at'] as String),
);

RunSplit runSplitFromRow(Map<String, dynamic> row) => RunSplit(
  index: _toInt(row['seq']),
  distanceMeters: _toDouble(row['distance_m']),
  duration: Duration(seconds: _toInt(row['duration_s'])),
  avgHr: _toIntOrNull(row['avg_hr']),
);
