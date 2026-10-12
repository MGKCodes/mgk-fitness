/// How long since [at], roughly: "just now", "3 min ago", "2h ago", "4d ago".
///
/// Rough, and deliberately so. "3 minutes ago" is the answer to "did that
/// work"; a timestamp to the second is not. Backup's *last checked* and the
/// plan's *synced* say it the same way, so it lives once.
///
/// Track's "left open yesterday" is a different question — which day — and has
/// its own wording.
String roughlyAgo(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}
