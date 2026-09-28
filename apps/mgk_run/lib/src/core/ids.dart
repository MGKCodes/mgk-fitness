import 'dart:math';

/// Identity for a row this device owns.
///
/// The device generates run ids rather than the backend, matching the
/// convention `run.runs.id` is built on: a run is the same row on the phone and
/// in the backup, with no round trip to find out what it is called. That part
/// was always right. What was wrong was using a **clock reading as the
/// identity**.
///
/// Both generators this replaces were `DateTime.now().microsecondsSinceEpoch` —
/// and a timestamp is not an identity, it is a description of when something
/// happened. Two rows written inside one clock tick get the same id, and since
/// both writers upsert, the second silently overwrites the first. On Windows
/// the tick is coarse enough that three inserts in a loop routinely collide,
/// which is how this was found: a test asserting the log's order failed about
/// one run in three because two of its three runs were the same row.
///
/// A hand-entered run is unlikely to race a human's other taps, but nothing
/// about the writer is limited to hand entry — the coach logs runs from
/// conversation, and a restore or an import writes many at once. Those are
/// exactly the programmatic bursts a clock cannot separate.
///
/// So: the timestamp stays, because sortable and human-readable ids are worth
/// keeping and every existing id has that shape, and **entropy is appended** so
/// two rows in one tick cannot be one row. `Random()` rather than
/// `Random.secure()` deliberately — this is a local row identifier, not a
/// token, and nothing about it needs to be unguessable.
String newLocalId([String prefix = '']) {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final entropy = _random.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
  return '$prefix$stamp-$entropy';
}

final Random _random = Random();
