import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../../../core/units/distance.dart';
import '../../../core/units/unit_system.dart';
import '../domain/run_writer.dart';
import '../domain/run_draft.dart';

/// Adding a run by hand, and correcting one that already exists.
///
/// One screen for both, because they are the same form over the same validator
/// and the only difference is whether there is already a row. Two screens would
/// be two places for the rules to drift apart.
///
/// It edits in the runner's own units and stores metric (CLAUDE.md rule 4). It
/// never touches a trace: for a recorded run this changes the summary and
/// leaves what the device saw exactly as it was — see
/// `AppDatabase.updateRunDetails`.
class RunFormScreen extends StatefulWidget {
  const RunFormScreen({
    super.key,
    required this.editor,
    this.runId,
    this.initial,
    this.unit = UnitSystem.metric,
    this.onSaved,
    this.now = DateTime.now,
  });

  final RunWriter editor;

  /// The run being corrected, or null to add a new one.
  final String? runId;

  /// What to open with. For an edit this is the stored run; for an add it is
  /// usually null, and the form starts at "today, treadmill".
  final RunDraft? initial;

  final UnitSystem unit;

  /// Called after a successful write, with the run's id.
  final void Function(String runId)? onSaved;

  final DateTime Function() now;

  bool get isEdit => runId != null;

  @override
  State<RunFormScreen> createState() => _RunFormScreenState();
}

class _RunFormScreenState extends State<RunFormScreen> {
  late final TextEditingController _distance;
  late final TextEditingController _duration;
  late final TextEditingController _hr;
  late final TextEditingController _notes;

  late DateTime _startedAt;
  late String _type;
  int? _rpe;
  bool _saving = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    // A new run defaults to now rather than to nothing: a runner adding a
    // treadmill session has almost always just done it, and a wrong date is
    // easier to spot than an empty one is to remember.
    _startedAt = d?.startedAt ?? widget.now();
    _type = d?.type ?? kTypeTreadmill;
    _rpe = d?.rpe;
    _distance = TextEditingController(
      text: d?.distanceMeters == null
          ? ''
          : _distanceText(d!.distanceMeters!, widget.unit),
    );
    _duration = TextEditingController(text: _hms(d?.duration));
    _hr = TextEditingController(text: d?.avgHr?.toString() ?? '');
    _notes = TextEditingController(text: d?.notes ?? '');
  }

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _distance,
      _duration,
      _hr,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The form as a draft — the single thing the validator reads, so what is
  /// checked and what is written can never be different objects.
  RunDraft get _draft => RunDraft(
    startedAt: _startedAt,
    duration: _parseHms(_duration.text),
    distanceMeters: _parseDistance(_distance.text, widget.unit),
    type: _type,
    avgHr: int.tryParse(_hr.text.trim()),
    rpe: _rpe,
    notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
  );

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final id = widget.isEdit
          ? await _editExisting()
          : await widget.editor.add(_draft);
      if (!mounted) return;
      widget.onSaved?.call(id);
      Navigator.of(context).pop(id);
    } on RunDraftInvalid catch (e) {
      // Belt and braces: the button is disabled while invalid, so reaching
      // here means the two disagreed. Show it rather than swallow it.
      if (mounted) {
        setState(() => _failure = e.issues.first.message);
      }
    } catch (e) {
      if (mounted) setState(() => _failure = 'Could not save that run.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String> _editExisting() async {
    final id = widget.runId!;
    await widget.editor.edit(id, _draft);
    return id;
  }

  Future<void> _pickWhen() async {
    final now = widget.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _startedAt,
      firstDate: now.subtract(const Duration(days: 365 * 5)),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startedAt),
    );
    if (!mounted) return;
    setState(() {
      _startedAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _startedAt.hour,
        time?.minute ?? _startedAt.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final issues = _draft.issues(widget.now());
    final valid = issues.isEmpty;
    final unitLabel = widget.unit == UnitSystem.metric ? 'km' : 'mi';

    return Scaffold(
      appBar: AppBar(title: Text(widget.isEdit ? 'Edit run' : 'Add a run')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                children: <Widget>[
                  if (widget.isEdit)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Text(
                        'Changing the numbers here does not change the route. '
                        'What was recorded stays as it was recorded.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  _labeled('When', _whenField(issues)),
                  _labeled(
                    'Distance',
                    _numberField(_distance, unitLabel, 'distance', issues),
                  ),
                  _labeled(
                    'Time',
                    _textField(
                      _duration,
                      'duration',
                      issues,
                      hint: 'mm:ss or h:mm:ss',
                    ),
                  ),
                  _labeled('Kind', _typeField(issues)),
                  _labeled('Effort (optional)', _rpeField(issues)),
                  _labeled(
                    'Average heart rate (optional)',
                    _numberField(_hr, 'bpm', 'avg_hr', issues, decimal: false),
                  ),
                  _labeled(
                    'Notes (optional)',
                    TextField(
                      controller: _notes,
                      onChanged: (_) => setState(() {}),
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'How did it feel?',
                      ),
                    ),
                  ),
                  if (_failure != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _failure!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: PrimaryButton(
                label: _saving
                    ? 'Saving…'
                    : (valid
                          ? (widget.isEdit ? 'Save changes' : 'Add run')
                          : 'Fill in the details above'),
                onPressed: valid && !_saving ? _save : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- fields --------------------------------------------------------------

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

  Widget _issueText(String field, List<RunIssue> issues) {
    final issue = issues.where((i) => i.field == field).firstOrNull;
    if (issue == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 2),
      child: Text(
        issue.message,
        style: const TextStyle(color: AppColors.danger, fontSize: 12),
      ),
    );
  }

  Widget _whenField(List<RunIssue> issues) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      InkWell(
        onTap: _pickWhen,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          decoration: const InputDecoration(),
          child: Text(
            _whenLabel(_startedAt),
            style: const TextStyle(color: AppColors.textPrimary),
          ),
        ),
      ),
      _issueText('started_at', issues),
    ],
  );

  Widget _numberField(
    TextEditingController c,
    String suffix,
    String field,
    List<RunIssue> issues, {
    bool decimal = true,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      TextField(
        controller: c,
        onChanged: (_) => setState(() {}),
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(
            decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
          ),
        ],
        decoration: InputDecoration(suffixText: suffix),
      ),
      _issueText(field, issues),
    ],
  );

  Widget _textField(
    TextEditingController c,
    String field,
    List<RunIssue> issues, {
    String? hint,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      TextField(
        controller: c,
        onChanged: (_) => setState(() {}),
        keyboardType: TextInputType.datetime,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
        ],
        decoration: InputDecoration(hintText: hint),
      ),
      _issueText(field, issues),
    ],
  );

  Widget _typeField(List<RunIssue> issues) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Wrap(
        spacing: 8,
        children: <Widget>[
          for (final t in kRunTypes)
            ChoiceChip(
              label: Text(_typeLabel(t)),
              showCheckmark: false,
              selected: _type == t,
              onSelected: (_) => setState(() => _type = t),
            ),
        ],
      ),
      _issueText('type', issues),
    ],
  );

  Widget _rpeField(List<RunIssue> issues) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Row(
        children: <Widget>[
          for (var e = 1; e <= 10; e++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: e == 10 ? 0 : 3),
                child: ChoiceChip(
                  label: Center(child: Text('$e')),
                  showCheckmark: false,
                  labelPadding: EdgeInsets.zero,
                  selected: _rpe == e,
                  // Tapping the chosen effort again clears it, because it is
                  // optional and there would otherwise be no way back to "I
                  // would rather not say".
                  onSelected: (_) =>
                      setState(() => _rpe = _rpe == e ? null : e),
                ),
              ),
            ),
        ],
      ),
      _issueText('rpe', issues),
    ],
  );

  // ---- display <-> stored --------------------------------------------------

  static String _typeLabel(String type) => switch (type) {
    kTypeTreadmill => 'Treadmill',
    kTypeOutdoor => 'Outdoor',
    _ => 'Other',
  };

  /// Stored metres as the number the runner edits in. Two decimals, because
  /// one would round a 5.05 km treadmill session to 5.1 and then store the
  /// rounded value back on the next save.
  static String _distanceText(double meters, UnitSystem unit) =>
      (meters / _perUnit(unit)).toStringAsFixed(2);

  static double? _parseDistance(String text, UnitSystem unit) {
    final v = double.tryParse(text.trim());
    return v == null ? null : v * _perUnit(unit);
  }

  static double _perUnit(UnitSystem unit) =>
      unit == UnitSystem.metric ? metersPerKilometer : metersPerMile;

  /// `mm:ss` or `h:mm:ss`. Deliberately tolerant of a single number, which a
  /// runner typing "45" almost certainly means as minutes.
  static Duration? _parseHms(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final parts = t.split(':');
    if (parts.any((p) => p.isEmpty)) return null;
    final nums = parts.map(int.tryParse).toList();
    if (nums.any((n) => n == null)) return null;
    return switch (nums.length) {
      1 => Duration(minutes: nums[0]!),
      2 => Duration(minutes: nums[0]!, seconds: nums[1]!),
      3 => Duration(hours: nums[0]!, minutes: nums[1]!, seconds: nums[2]!),
      _ => null,
    };
  }

  static String _hms(Duration? d) {
    if (d == null) return '';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  }

  static String _whenLabel(DateTime d) {
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
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year}, $hh:$mm';
  }
}
