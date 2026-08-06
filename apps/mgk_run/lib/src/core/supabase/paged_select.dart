/// Reads every row of a PostgREST query, a page at a time.
///
/// PostgREST answers an unbounded `select()` with at most 1000 rows and says
/// nothing about it. No error, no flag — just a short list that looks complete.
///
/// That was found by restoring real data and counting: a seeded run holding
/// 1081 trace points came back with exactly 1000, and a truncated trace draws
/// as a route that simply stops. The coach's transcript is the worse case,
/// because retention caps it at 1000 turns — precisely the boundary — so a
/// runner at their limit would lose the oldest of their own conversation with
/// no sign anything had gone.
///
/// So anything that can exceed a thousand rows pages explicitly. A page shorter
/// than [pageSize] is the end; anything else is another request.
library;

const int pageSize = 1000;

/// Calls [fetch] with successive inclusive ranges until it returns a short
/// page, and returns everything it gave.
///
/// [fetch] is a closure rather than a query object because PostgREST builders
/// are single-use: `.range()` has to be applied to a freshly built query each
/// time, and reusing one silently returns the first page for ever.
Future<List<Map<String, dynamic>>> fetchAllPages(
  Future<List<dynamic>> Function(int from, int to) fetch,
) async {
  final all = <Map<String, dynamic>>[];
  var from = 0;
  while (true) {
    final page = await fetch(from, from + pageSize - 1);
    all.addAll(page.map((e) => Map<String, dynamic>.from(e as Map)));
    if (page.length < pageSize) return all;
    from += pageSize;
  }
}
