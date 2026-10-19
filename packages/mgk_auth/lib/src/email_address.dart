/// Two small judgements about a typed address, made before anything is sent.
library;

/// Whether [email] could be an address: one `@`, something either side of it,
/// a dot in the part after it, and no spaces.
///
/// **Deliberately loose.** A strict pattern rejects real addresses, and the
/// server is the arbiter. This only stops the lookup being asked about
/// something that plainly is not one.
bool looksLikeEmail(String email) {
  final value = email.trim();
  final at = value.indexOf('@');
  if (at < 1 || at != value.lastIndexOf('@')) return false;
  final domain = value.substring(at + 1);
  if (domain.isEmpty || !domain.contains('.')) return false;
  if (domain.startsWith('.') || domain.endsWith('.')) return false;
  return !value.contains(RegExp(r'\s'));
}

/// The domains a typo is most likely to have been aiming at.
///
/// UK-first, because that is where the apps are used most, then the large
/// international mail services. A domain on this list is never "corrected".
const List<String> _commonDomains = <String>[
  'gmail.com',
  'googlemail.com',
  'icloud.com',
  'me.com',
  'mac.com',
  'hotmail.com',
  'hotmail.co.uk',
  'outlook.com',
  'live.com',
  'live.co.uk',
  'msn.com',
  'yahoo.com',
  'yahoo.co.uk',
  'btinternet.com',
  'sky.com',
  'virginmedia.com',
  'talktalk.net',
  'aol.com',
  'protonmail.com',
  'proton.me',
];

/// The address [email] was probably meant to be, when its domain is one or two
/// keystrokes from a common one: `you@gmial.com` gives `you@gmail.com`. Null
/// when the domain is already common, or nothing is close enough to suggest.
///
/// Run's ADR-0047, edge cases: "A likely typo of a common domain gets 'Did
/// you mean …?'". Only ever offered, never applied: an address nobody else
/// uses is still somebody's address.
String? suggestEmail(String email) {
  final value = email.trim();
  if (!looksLikeEmail(value)) return null;
  final at = value.lastIndexOf('@');
  final local = value.substring(0, at);
  final domain = value.substring(at + 1).toLowerCase();
  if (_commonDomains.contains(domain)) return null;

  String? best;
  var bestDistance = 3;
  for (final candidate in _commonDomains) {
    final distance = _distance(domain, candidate);
    if (distance < bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  // Two edits is a typo in a ten-letter domain and a different domain in a
  // six-letter one: `me.com` is two from `mx.co`, which is not a slip.
  if (best == null || (bestDistance == 2 && domain.length < 8)) return null;
  return '$local@$best';
}

/// Edits between [a] and [b], counting a swap of two neighbours as one, which
/// is the commonest slip on a phone keyboard (`gmial`).
int _distance(String a, String b) {
  final rows = a.length + 1;
  final cols = b.length + 1;
  final d = List<List<int>>.generate(
    rows,
    (i) => List<int>.generate(cols, (j) => i == 0 ? j : (j == 0 ? i : 0)),
  );
  for (var i = 1; i < rows; i++) {
    for (var j = 1; j < cols; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var best = d[i - 1][j] + 1;
      if (d[i][j - 1] + 1 < best) best = d[i][j - 1] + 1;
      if (d[i - 1][j - 1] + cost < best) best = d[i - 1][j - 1] + cost;
      if (i > 1 &&
          j > 1 &&
          a[i - 1] == b[j - 2] &&
          a[i - 2] == b[j - 1] &&
          d[i - 2][j - 2] + 1 < best) {
        best = d[i - 2][j - 2] + 1;
      }
      d[i][j] = best;
    }
  }
  return d[a.length][b.length];
}
