/// Where the suite's source is, and how somebody tells us about a problem.
///
/// Both apps are open source, in one public repository, and both say so from
/// Settings › About: a **Source code** row for the people who will read it,
/// and a **Report a problem** row for everybody else, who will not and should
/// not have to. Held here so the two apps say exactly the same thing.
library;

/// The public repository both apps, their shared packages and the backend
/// live in.
const String kSourceRepository = 'https://github.com/MGKCodes/mgk-fitness';

/// The apps' licence, as Settings prints it beside **Source code**. `web/` and
/// the exercise drawings are licensed differently (NOTICE.md), and neither is
/// what that row opens.
const String kSourceLicence = 'AGPL-3.0';

/// An app's own folder in the public repository, on `main`.
///
/// **Not the tag of the build that is running**, though every store build is
/// tagged. The tags are made by hand, so a build whose tag was never pushed
/// would open a 404, inside a shipped version, for as long as anybody has it
/// installed. The folder on `main` always opens, and the repository's README
/// says that each store build is tagged, for anybody after the exact one.
///
/// [package] is the app's directory under `apps/`: `mgk_run` or `mgk_lift`.
Uri sourceCodeUri(String package) =>
    Uri.parse('$kSourceRepository/tree/main/apps/$package');

/// An email to an app's support address, with the app, its version and the
/// phone's system already written in, so a report says what it is about
/// without anybody being asked.
///
/// Nothing else goes in: no account, no training, nothing the person cannot
/// see in the message before they send it.
///
/// Built by hand rather than with `Uri.queryParameters`, which writes a space
/// as `+`. Several mail apps show that `+` literally, so every word of the
/// subject would arrive joined by them.
Uri problemReportUri({
  required String to,
  required String product,
  required String version,
  required String system,
}) {
  final String subject = 'A problem with $product $version';
  final String body =
      'What happened:\n\n\n'
      'What you expected instead:\n\n\n'
      '$product $version on $system';
  return Uri.parse(
    'mailto:$to'
    '?subject=${Uri.encodeComponent(subject)}'
    '&body=${Uri.encodeComponent(body)}',
  );
}
