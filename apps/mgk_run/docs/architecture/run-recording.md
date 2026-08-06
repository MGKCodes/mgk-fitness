# Run recording

`geolocator` with `allowsBackgroundLocationUpdates` is sufficient on iOS. The
plugin risks that motivate a paid background-geolocation licence are Android
problems (Doze, OEM process killing), and Android is out of scope.

## Two non-negotiable requirements

1. **Persist every point to local SQLite as it arrives.** Never hold a run in
   memory. A crash or termination mid-run must not lose the run. This is the
   main thing a paid licence sells, and it is an afternoon of work.
2. **Put recording behind a `RunRecorder` interface**, with the `geolocator`
   implementation as one concrete class. If real-world use shows dropped points,
   swapping to `flutter_background_geolocation` becomes a one-class change, not a
   rewrite of the recording layer.

```dart
abstract class RunRecorder {
  Stream<RunPoint> get points;   // each emitted point is persisted immediately
  Future<void> start();
  Future<void> pause();
  Future<void> resume();
  Future<Run> stop();
}
```

## Point processing

Raw CoreLocation output produces jagged routes and inflated distance. Required:

- **Accuracy filtering** — discard points with poor `horizontalAccuracy`.
- **Smoothing** — reduce jitter before computing distance.
- **Autopause detection** — stop accumulating distance when the runner stops.
- **Gap handling** — tunnels and tree cover drop the signal; bridge sanely
  rather than drawing a straight line through a building.

## Elevation

Use **`CMAltimeter`** (barometric) via a platform channel, not GPS altitude. GPS
elevation gain is visibly wrong and users notice.

## Calories

A derived estimate from body mass and distance. **Label it as an estimate** in
the UI. Do not present it as a measurement.

## Treadmill / manual

No GPS path. Duration + distance entered by hand, or an indoor run synced from
HealthKit. Cadence/steps via `pedometer` can back out treadmill distance. The
plan and coaching layers must tolerate a session with **no route and no
splits**.

## Deduplication

**The highest-risk area in the app.** One run can arrive three times: from the
watch, from Runio's own recording, and from any other app writing to Health.

- Filter on **`HKSource` bundle identifier** plus **time-window overlap** before
  anything reaches the training log.
- This bug is invisible in single-device testing and makes the app look broken
  immediately in the wild. Build and test dedup with fixtures that simulate
  multiple sources for the same run.

## HealthKit permission gotcha

Read permissions are per-type, and Apple deliberately makes a **denied read
indistinguishable from no data**. You cannot detect that a user declined heart
rate — you receive an empty result. **Design for absence** rather than rendering
an error state.

## Testing

- Replay recorded GPS traces through the point processor and assert distance is
  within tolerance of a known-good value.
- Simulate crash-mid-run: kill the process and assert the run is recoverable
  from local storage.
- Dedup fixtures: same workout from watch + Runio + a third app → exactly one
  run in the log.
