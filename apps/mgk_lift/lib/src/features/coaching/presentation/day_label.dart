/// When something happened, said the way a person says it.
///
/// **Calendar days, not elapsed hours.** Something at 11pm and something at 1am
/// are twenty-six hours apart and are "yesterday" and "today" — a duration
/// would call both of them "1d" and be useless to anybody trying to remember
/// which evening they meant.
///
/// The ladder narrows as it goes back: today and yesterday are named, the rest
/// of the week is a weekday because "Tuesday" is how somebody recalls a
/// conversation, and past that a date, because the fourth Tuesday back is not a
/// thing anyone remembers.
///
/// [now] is passed rather than read so a screenshot taken on a Saturday shows
/// what it showed on a Thursday. Reading the wall clock here is the fault the
/// lift screen board caught twice — and a third time on the read-back screen's
/// title, which disagreed with the row that opened it.
///
/// **This belongs in `mgk_ui`, and cannot go there yet.** mgk_run has a
/// character-for-character copy in `chat_widgets.dart`, and two run files
/// import both that and `package:mgk_ui/mgk_ui.dart` — so exporting this name
/// from the shared package makes those ambiguous imports and stops the run app
/// compiling the moment the branches meet. Consolidating needs both apps in
/// hand at once, which is a cross-lane change and not this plan's to make.
String dayLabel(DateTime at, DateTime now) {
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(at.year, at.month, at.day)).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return _weekdays[at.weekday - 1];
  return '${at.day} ${_months[at.month - 1]}';
}

const List<String> _weekdays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
