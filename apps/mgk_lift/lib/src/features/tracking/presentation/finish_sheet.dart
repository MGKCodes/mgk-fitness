import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../domain/session.dart';
import '../domain/workout_library.dart';

/// What Finish can offer to do about a workout, worked out before the sheet
/// opens (R3, R4). Null when there is nothing to offer.
sealed class SaveOffer {
  const SaveOffer();
}

/// From a saved workout whose movements changed today: *"Save to Push for
/// next time? + Dips, − Cable Fly"*, on.
final class UpdateWorkout extends SaveOffer {
  const UpdateWorkout({
    required this.workoutName,
    required this.change,
    this.editedMeanwhile = false,
  });

  final String workoutName;
  final MovementChange change;

  /// Changed on another phone while this session ran. The line says so, the
  /// switch starts off, and on replaces that edit — the session's changes
  /// were made against a workout that no longer exists, so neither silently
  /// beats the other.
  final bool editedMeanwhile;
}

/// The workout the session came from was deleted while it ran: *"Save
/// today's session as a new workout?"*, off.
final class SaveAsNewWorkout extends SaveOffer {
  const SaveAsNewWorkout({required this.workoutName, required this.change});

  final String workoutName;
  final MovementChange change;
}

/// Started blank: *Save as a workout*, off, with a name when switched on.
final class SaveAsWorkout extends SaveOffer {
  const SaveAsWorkout({required this.suggestedName});

  final String suggestedName;
}

/// What the lifter decided at Finish.
class FinishDecision {
  const FinishDecision({this.save = false, this.name});

  /// Whether to do what the [SaveOffer] offered.
  final bool save;

  /// The name for a new workout, as typed. Null for an update.
  final String? name;
}

/// The one look before a session ends — and, when the session changed the
/// workout it came from, the one question about it.
///
/// **Finish used to be a single tap with no way back**, on a button in the
/// header, and it kept every unticked set as though it had happened. Unticked
/// sets are now dropped (decision D3), so this says so **first**, in the one
/// place the lifter can still do something about it: keep going and tick them.
///
/// **Saving is asked here, and only here (R4).** The workout used to learn
/// from the session on its own, with an Undo on the summary; the summary also
/// offered to save a blank session, and so did the foot of the running list.
/// Now the sheet asks the one question there is, with the answer most people
/// want already set, and nothing is left pending on the summary.
///
/// Returns the decision, or null to keep going.
class FinishSheet extends StatefulWidget {
  const FinishSheet({
    super.key,
    required this.session,
    required this.massUnit,
    this.offer,
    this.title,
    this.actionLabel = 'Finish',
  });

  final Session session;
  final MassUnit massUnit;
  final SaveOffer? offer;

  /// `Finish Push?`, or `Save Push?` for an edit to a past session.
  final String? title;
  final String actionLabel;

  static Future<FinishDecision?> show(
    BuildContext context, {
    required Session session,
    required MassUnit massUnit,
    SaveOffer? offer,
    String? title,
    String actionLabel = 'Finish',
  }) => showGlassSheet<FinishDecision>(
    context: context,
    builder: (_) => FinishSheet(
      session: session,
      massUnit: massUnit,
      offer: offer,
      title: title,
      actionLabel: actionLabel,
    ),
  );

  @override
  State<FinishSheet> createState() => _FinishSheetState();
}

class _FinishSheetState extends State<FinishSheet> {
  /// On by default only for the ordinary update: the answer most people want
  /// to "you swapped the flyes for dips". A conflict, or a new workout, is a
  /// decision nobody should make by not noticing a switch.
  late bool _save = switch (widget.offer) {
    UpdateWorkout(editedMeanwhile: false) => true,
    _ => false,
  };

  /// Owned by the sheet and disposed with it, after the route has gone. See
  /// `save_workout_prompt.dart` for what disposing one any earlier did.
  late final TextEditingController _name = TextEditingController(
    text: switch (widget.offer) {
      SaveAsWorkout(:final suggestedName) => suggestedName,
      SaveAsNewWorkout(:final workoutName) => workoutName,
      _ => '',
    },
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _asksForName =>
      widget.offer is SaveAsWorkout || widget.offer is SaveAsNewWorkout;

  void _done() {
    final typed = _name.text.trim();
    Navigator.of(context).pop(
      FinishDecision(
        save: widget.offer != null && _save,
        name: _asksForName && typed.isNotEmpty ? typed : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.session;
    final unticked = session.untickedSets;
    final sets = session.completedSets;
    final volume = session.volumeKg;
    // Movements with nothing ticked go too — the same rule, one level up. Said
    // here as well, because an untouched card is exactly the thing somebody
    // forgets is on the page. Seen on the emulator: two movements added and
    // never started, and the sheet said nothing about them.
    final empty = session.exercises
        .where((e) => !e.sets.any((s) => s.isCompleted))
        .length;
    final kept = session.exercises.length - empty;
    final offer = widget.offer;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SheetHandle(),
            Text(
              widget.title ?? 'Finish ${session.name}?',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              <String>[
                '$sets ${sets == 1 ? 'set' : 'sets'}',
                if (volume > 0) Mass.kilograms(volume).label(widget.massUnit),
                '$kept ${kept == 1 ? 'movement' : 'movements'}',
              ].join(' · '),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (unticked > 0 || empty > 0) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              AppCard(
                color: AppColors.elevated,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (unticked > 0)
                      _Dropped(
                        '$unticked ${unticked == 1 ? 'set isn\'t' : 'sets aren\'t'} '
                        'ticked, so ${unticked == 1 ? 'it won\'t' : 'they won\'t'} '
                        'be saved.',
                      ),
                    if (unticked > 0 && empty > 0)
                      const SizedBox(height: AppSpacing.sm),
                    if (empty > 0)
                      _Dropped(
                        '$empty ${empty == 1 ? 'movement has' : 'movements have'} '
                        'nothing logged, so ${empty == 1 ? 'it won\'t' : 'they won\'t'} '
                        'be kept.',
                      ),
                  ],
                ),
              ),
            ],
            if (offer != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _SaveRow(
                offer: offer,
                value: _save,
                onChanged: (on) => setState(() => _save = on),
                name: _name,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: widget.actionLabel, onPressed: _done),
            const SizedBox(height: AppSpacing.xs),
            AppTextButton(
              label: 'Keep going',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The question, as a switch: what it would do, the change it is about, and a
/// name when it makes a new workout.
class _SaveRow extends StatelessWidget {
  const _SaveRow({
    required this.offer,
    required this.value,
    required this.onChanged,
    required this.name,
  });

  final SaveOffer offer;
  final bool value;
  final ValueChanged<bool> onChanged;
  final TextEditingController name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String title, List<String> lines, bool named) = switch (offer) {
      UpdateWorkout(
        :final workoutName,
        :final change,
        editedMeanwhile: false,
      ) =>
        (
          'Save to $workoutName for next time',
          <String>[change.describe()],
          false,
        ),
      UpdateWorkout(:final workoutName, :final change) => (
        'Save to $workoutName anyway',
        <String>[
          'It was changed on another phone while you trained. Saving '
              'replaces that.',
          change.describe(),
        ],
        false,
      ),
      SaveAsNewWorkout(:final workoutName, :final change) => (
        "Save today's session as a new workout",
        <String>[
          '$workoutName was deleted while you trained.',
          change.describe(),
        ],
        true,
      ),
      SaveAsWorkout() => (
        'Save as a workout',
        <String>['Start it in one tap next time.'],
        true,
      ),
    };

    return AppCard(
      color: AppColors.elevated,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MergeSemantics(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: theme.textTheme.titleSmall),
                      for (final line in lines) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          line,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Switch(value: value, onChanged: onChanged),
              ],
            ),
          ),
          AnimatedSize(
            duration: AppMotion.base,
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: named && value
                ? Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.sm,
                      right: AppSpacing.xs,
                      bottom: AppSpacing.xs,
                    ),
                    child: TextField(
                      controller: name,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// One line about something Finish will leave out.
class _Dropped extends StatelessWidget {
  const _Dropped(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      const Icon(
        Icons.radio_button_unchecked,
        size: 18,
        color: AppColors.textSecondary,
      ),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ),
    ],
  );
}
