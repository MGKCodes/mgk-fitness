/// A runner flagging something the coach said.
///
/// **Why the app has this at all.** Google Play's policy on AI-generated
/// content asks that people can report or flag it without leaving the app, so
/// that what a model says to them can be reviewed and acted on. The coach's
/// replies are model output shown to somebody about their body; a reply that
/// is unsafe, wrong or offensive needs a way back to us that is not an email.
///
/// What is kept is the reply, the reason and any note, with the account that
/// sent it. Not the conversation around it: the reply is what is being
/// reported, and the rest of a transcript is the runner's own words about
/// their health, which a report does not need.
library;

/// Why a reply is being reported. The codes are the `coach.reports.reason`
/// values the table accepts.
enum CoachReportReason {
  harmful('harmful', 'Harmful or unsafe'),
  wrong('wrong', 'Wrong or misleading'),
  offensive('offensive', 'Offensive'),
  other('other', 'Something else');

  const CoachReportReason(this.code, this.label);

  /// What is stored.
  final String code;

  /// What the runner is shown.
  final String label;
}

/// One report, as the runner made it.
class CoachReport {
  const CoachReport({required this.reply, required this.reason, this.note});

  /// The longest reply stored, in characters. Longer is cut, not refused: a
  /// report of a long reply is still a report.
  static const int maxReply = 8000;

  /// The longest note, which the field also enforces as it is typed.
  static const int maxNote = 1000;

  final String reply;
  final CoachReportReason reason;
  final String? note;

  /// The row inserted into `coach.reports`.
  ///
  /// **No `user_id` and no `created_at`.** Both default on the server, and
  /// the user is `auth.uid()`: a client that sent its own could claim to be
  /// somebody else, and the table's policy only lets it insert as itself.
  Map<String, Object?> toRow() {
    final trimmedNote = note?.trim();
    return <String, Object?>{
      'app': 'run',
      'reply': _cut(reply, maxReply),
      'reason': reason.code,
      'note': trimmedNote == null || trimmedNote.isEmpty
          ? null
          : _cut(trimmedNote, maxNote),
    };
  }

  /// [text] cut to [max] characters, counting code points so an emoji is
  /// never split in half.
  static String _cut(String text, int max) {
    final runes = text.runes;
    return runes.length <= max ? text : String.fromCharCodes(runes.take(max));
  }
}

/// Where a report goes.
abstract interface class CoachReporter {
  /// Sends [report]. Throws when it did not arrive, so the screen can say it
  /// did not send and keep what the runner wrote.
  Future<void> report(CoachReport report);
}
