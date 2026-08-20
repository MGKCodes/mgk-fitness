import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../domain/intake_slots.dart';
import '../domain/plan_shape.dart';
import '../domain/runner_profile.dart';

/// The editable end of onboarding. Extraction is sometimes wrong and the plan
/// is built on these numbers, so every gathered slot is shown and editable
/// (onboarding.md). The same Dart sanity checks that guarded the conversation
/// guard this screen — "Build my plan" stays disabled until the profile is
/// complete and sane. Distances edit in km; metric is what gets stored.
class ProfileConfirmationScreen extends StatefulWidget {
  const ProfileConfirmationScreen({
    super.key,
    required this.slots,
    required this.onConfirm,
    this.onBack,
    this.now = DateTime.now,
  });

  final IntakeSlots slots;
  final void Function(RunnerProfile profile) onConfirm;

  /// Called to return to the conversation. Null falls back to the default
  /// route back button (used when this screen is pushed on its own).
  final VoidCallback? onBack;

  final DateTime Function() now;

  @override
  State<ProfileConfirmationScreen> createState() =>
      _ProfileConfirmationScreenState();
}

class _ProfileConfirmationScreenState extends State<ProfileConfirmationScreen> {
  late final TextEditingController _goalKm;
  late final TextEditingController _weeklyKm;
  late final TextEditingController _longestKm;
  late final TextEditingController _ttKm;
  late final TextEditingController _ttTime;
  late final TextEditingController _injury;

  DateTime? _eventDate;
  int? _daysPerWeek;
  late Set<int> _weekdays;

  /// What the runner repeats every week — the substance of a rhythm.
  ///
  /// Held rather than rebuilt from the form, because there is no field for it:
  /// these arrive from intake and are shown back for checking. They used to be
  /// dropped here, which quietly turned a parkrun runner into a runner with no
  /// rhythm at all by the time the profile was built.
  late List<PlanCommitment> _commitments;

  static const _weekdayLabels = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void initState() {
    super.initState();
    final s = widget.slots;
    _goalKm = TextEditingController(text: _km(s.goalDistanceMeters));
    _weeklyKm = TextEditingController(text: _km(s.currentWeeklyMeters));
    _longestKm = TextEditingController(text: _km(s.longestRecentMeters));
    _ttKm = TextEditingController(text: _km(s.timeTrialDistanceMeters));
    _ttTime = TextEditingController(text: _mmss(s.timeTrialDuration));
    _injury = TextEditingController(text: s.injuryNotes ?? '');
    _eventDate = s.eventDate;
    _daysPerWeek = s.daysPerWeek;
    _weekdays = {...?s.availableWeekdays};
    _commitments = <PlanCommitment>[...?s.commitments];
  }

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _goalKm,
      _weeklyKm,
      _longestKm,
      _ttKm,
      _ttTime,
      _injury,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The current edits as slots — the single source the validator reads.
  ///
  /// `shape` and `commitments` are carried through rather than rebuilt: neither
  /// has a field on this screen, and dropping them changed what the runner was
  /// while they were checking it. A rhythm arrived here and left as a log.
  IntakeSlots get _current => IntakeSlots(
    shape: widget.slots.shape,
    commitments: _commitments.isEmpty ? null : _commitments,
    goalDistanceMeters: _metersFromKm(_goalKm.text),
    eventDate: _eventDate,
    currentWeeklyMeters: _metersFromKm(_weeklyKm.text),
    longestRecentMeters: _metersFromKm(_longestKm.text),
    daysPerWeek: _daysPerWeek,
    availableWeekdays: _weekdays.isEmpty ? null : _weekdays,
    timeTrialDistanceMeters: _metersFromKm(_ttKm.text),
    timeTrialDuration: _durationFromMmss(_ttTime.text),
    injuryNotes: _injury.text.trim().isEmpty ? null : _injury.text.trim(),
  );

  /// No stated constraint on which days they can run. Not a guess about the
  /// runner — a statement that they did not restrict anything, which is what
  /// leaving the row blank means.
  static const Set<int> _anyDay = <int>{1, 2, 3, 4, 5, 6, 7};

  void _confirm() {
    final s = _current;
    if (!s.isComplete(widget.now())) return;
    widget.onConfirm(
      RunnerProfile(
        // Nullable on RunnerProfile, and null is a real answer rather than
        // missing data (ADR-0011): a runner keeping a rhythm is not training
        // toward a distance, and one without a race has no date. These were
        // force-unwrapped, so "Build my plan" threw for every shape but block.
        goalDistanceMeters: s.goalDistanceMeters,
        eventDate: s.eventDate,
        // **The other four were left force-unwrapped**, and each one is a crash
        // the moment `isComplete` is true without it — which is not a rare
        // state, it is the normal one:
        //
        //  - `availableWeekdays` is required by *nothing*, so it is null
        //    whenever the runner was not asked which days. Building a real plan
        //    hit exactly this: "Build my plan" threw a null check, the framework
        //    swallowed it, and the button read as dead.
        //  - the other three are required only for a shape with weeks, so a
        //    runner who picks "just record my runs" reaches this line with all
        //    three null.
        //
        // Defaults rather than `!`, and honest ones: no stated constraint means
        // every day is available, and nothing said about volume is zero rather
        // than a number nobody gave.
        currentWeeklyMeters: s.currentWeeklyMeters ?? 0,
        longestRecentMeters: s.longestRecentMeters ?? 0,
        daysPerWeek: s.daysPerWeek ?? 0,
        availableWeekdays: s.availableWeekdays ?? _anyDay,
        commitments: _commitments,
        timeTrialDistanceMeters: s.timeTrialDistanceMeters,
        timeTrialDuration: s.timeTrialDuration,
        injuryNotes: s.injuryNotes,
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = widget.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate ?? now.add(const Duration(days: 84)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _eventDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final slots = _current;
    final now = widget.now();
    final issues = slots.sanityIssues(now);
    final complete = slots.isComplete(now);
    // The validator's own view of what this runner is, so the fields shown and
    // the button's enabled state can never disagree about it.
    final shape = slots.resolvedShape;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm your details'),
        leading: widget.onBack == null
            ? null
            : AppIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Back',
                onPressed: widget.onBack,
              ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                children: <Widget>[
                  Text(
                    "Here's what I heard. Fix anything I got wrong, then I'll "
                    'build your plan.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // The form follows the shape, because asking for the wrong
                  // things is the app not listening (ADR-0011). A runner who
                  // said "parkrun every Saturday, no races" was still shown
                  // "Goal distance" and "Event date — Pick a date", which is
                  // precisely the question the intake prompt goes out of its
                  // way never to ask them.
                  if (shape.progresses)
                    _numberField(
                      'Goal distance',
                      _goalKm,
                      'km',
                      'goal',
                      issues,
                    ),
                  // Only a block has one. A horizon is a distance with no race
                  // entered, which is the whole distinction between them.
                  if (shape == PlanShape.block) _dateField(issues),
                  if (shape == PlanShape.rhythm) _commitmentsField(),
                  _numberField(
                    'Weekly volume now',
                    _weeklyKm,
                    'km',
                    'weekly_volume',
                    issues,
                  ),
                  _numberField(
                    'Longest recent run',
                    _longestKm,
                    'km',
                    'longest_run',
                    issues,
                  ),
                  _daysField(issues),
                  _weekdaysField(),
                  _timeTrialField(issues),
                  _labeled(
                    'Injury notes (optional)',
                    TextField(
                      controller: _injury,
                      onChanged: (_) => setState(() {}),
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Anything I should train around',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: PrimaryButton(
                label: complete ? 'Build my plan' : 'Fill in the details above',
                onPressed: complete ? _confirm : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labeled(String label, Widget field) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        field,
      ],
    ),
  );

  Widget _issueText(String slot, List<SlotIssue> issues) {
    final issue = issues.where((i) => i.slot == slot).firstOrNull;
    if (issue == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 2),
      child: Text(
        issue.message,
        style: const TextStyle(color: AppColors.danger, fontSize: 12),
      ),
    );
  }

  Widget _numberField(
    String label,
    TextEditingController c,
    String suffix,
    String slot,
    List<SlotIssue> issues,
  ) => _labeled(
    label,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: c,
          onChanged: (_) => setState(() {}),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(suffixText: suffix),
        ),
        _issueText(slot, issues),
      ],
    ),
  );

  Widget _dateField(List<SlotIssue> issues) => _labeled(
    'Event date',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(14),
          child: InputDecorator(
            decoration: const InputDecoration(),
            child: Text(
              _eventDate == null ? 'Pick a date' : _dateLabel(_eventDate!),
              style: TextStyle(
                color: _eventDate == null
                    ? AppColors.textTertiary
                    : AppColors.textPrimary,
              ),
            ),
          ),
        ),
        _issueText('event_date', issues),
      ],
    ),
  );

  /// What the runner repeats every week, shown back for checking.
  ///
  /// Read-only for now, and deliberately visible rather than perfect: these
  /// were extracted correctly and then dropped without ever being displayed, so
  /// a runner could not tell that the app had heard "parkrun" at all. Editing
  /// them needs a field this screen does not have yet; showing them is what
  /// makes "here's what I heard" true.
  Widget _commitmentsField() => _labeled(
    'Every week',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_commitments.isEmpty)
          Text(
            'Nothing regular yet.',
            style: TextStyle(color: AppColors.textTertiary),
          ),
        for (final c in _commitments)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _commitmentLabel(c),
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
      ],
    ),
  );

  /// "parkrun, Saturdays, 5.0 km, timed" — their word for it first, because it
  /// is what they call it and a plan that renamed it would be describing
  /// something they do not recognise.
  static String _commitmentLabel(PlanCommitment c) {
    const days = <String>[
      'Mondays',
      'Tuesdays',
      'Wednesdays',
      'Thursdays',
      'Fridays',
      'Saturdays',
      'Sundays',
    ];
    final parts = <String>[
      if (c.label != null && c.label!.trim().isNotEmpty) c.label!.trim(),
      days[c.weekday - 1],
      if (c.distanceMeters != null)
        '${(c.distanceMeters! / 1000).toStringAsFixed(1)} km',
      if (c.timed) 'timed',
    ];
    return parts.join(' · ');
  }

  Widget _daysField(List<SlotIssue> issues) => _labeled(
    'Days per week',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (var d = 1; d <= 7; d++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: d == 7 ? 0 : 4),
                  child: ChoiceChip(
                    label: Center(child: Text('$d')),
                    showCheckmark: false,
                    selected: _daysPerWeek == d,
                    onSelected: (_) => setState(() => _daysPerWeek = d),
                  ),
                ),
              ),
          ],
        ),
        _issueText('days_per_week', issues),
      ],
    ),
  );

  Widget _weekdaysField() => _labeled(
    'Which days',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (var day = 1; day <= 7; day++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: day == 7 ? 0 : 4),
                  child: FilterChip(
                    label: Center(child: Text(_weekdayLabels[day - 1])),
                    // Seven chips across a phone leave ~46px each, so a leading
                    // checkmark crowds the letter out and the row reads
                    // "✓ ✓ W ✓ F ✓ ✓" — you can only tell which days are selected
                    // by counting positions. The selected fill carries the state.
                    showCheckmark: false,
                    selected: _weekdays.contains(day),
                    onSelected: (on) => setState(() {
                      on ? _weekdays.add(day) : _weekdays.remove(day);
                    }),
                  ),
                ),
              ),
          ],
        ),
        // Blank is a real answer, and it used to look like an unfinished form
        // over a button that did nothing. Saying so costs one line.
        if (_weekdays.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Leave blank if any day works.',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ),
      ],
    ),
  );

  Widget _timeTrialField(List<SlotIssue> issues) => _labeled(
    'Recent race or time trial',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _ttKm,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(suffixText: 'km'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _ttTime,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'mm:ss'),
              ),
            ),
          ],
        ),
        _issueText('time_trial', issues),
      ],
    ),
  );

  // ---- metric <-> display helpers -----------------------------------------

  static String _km(double? meters) =>
      meters == null ? '' : (meters / 1000).toStringAsFixed(1);

  static double? _metersFromKm(String text) {
    final km = double.tryParse(text.trim());
    return km == null ? null : km * 1000;
  }

  static String _mmss(Duration? d) {
    if (d == null) return '';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static Duration? _durationFromMmss(String text) {
    final parts = text.trim().split(':');
    if (parts.length != 2) return null;
    final m = int.tryParse(parts[0]);
    final s = int.tryParse(parts[1]);
    if (m == null || s == null) return null;
    return Duration(minutes: m, seconds: s);
  }

  static String _dateLabel(DateTime d) {
    const months = <String>[
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
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
