import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../data/exercise_lookup.dart';
import '../domain/exercise.dart';
import 'exercise_thumb.dart';

/// Picks a movement to add to the session.
///
/// This replaced a bare text field. A text field is not wrong — a lifter must
/// always be able to type "smith machine incline press, feet up" — but making it
/// the *only* way wasted the 266-movement library and its form images, and made
/// every session start with spelling.
///
/// So: search the catalogue, or type your own. Both end in the same place, which
/// is a name on a session; the catalogue simply gets you there faster and brings
/// a picture with it.
class ExercisePickerSheet extends StatefulWidget {
  const ExercisePickerSheet({super.key, required this.lookup});

  final ExerciseLookup lookup;

  /// Returns the chosen movement's name, or null if dismissed.
  static Future<String?> show(
    BuildContext context, {
    required ExerciseLookup lookup,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExercisePickerSheet(lookup: lookup),
    );
  }

  @override
  State<ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<ExercisePickerSheet> {
  final TextEditingController _query = TextEditingController();
  late List<Exercise> _results = widget.lookup.search('');

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _results = widget.lookup.search(value));
  }

  /// True when what they typed is not already a catalogue name — the only case
  /// where offering "add your own" is useful rather than noise.
  bool get _canAddCustom {
    final typed = _query.text.trim();
    return typed.isNotEmpty && widget.lookup.find(typed) == null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * 0.85,
        child: GlassSurface(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SheetHandle(),
              const SectionLabel('Add exercise'),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _query,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  hintText: 'Search movements, muscles, equipment',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: AppColors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_canAddCustom) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                _CustomRow(
                  name: _query.text.trim(),
                  onTap: () => Navigator.of(context).pop(_query.text.trim()),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: _results.isEmpty
                    ? Center(
                        child: Text(
                          'Nothing matches that.\nAdd it as your own movement.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                        itemCount: _results.length,
                        itemBuilder: (context, i) => _ExerciseRow(
                          exercise: _results[i],
                          onTap: () =>
                              Navigator.of(context).pop(_results[i].name),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise, required this.onTap});

  final Exercise exercise;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: <Widget>[
            ExerciseThumb(asset: exercise.startImage, size: 44),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    exercise.name,
                    style: theme.textTheme.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    exercise.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The escape hatch: whatever they typed, added as-is.
class _CustomRow extends StatelessWidget {
  const _CustomRow({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: <Widget>[
            const Icon(Icons.add, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'Add "$name" as your own',
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
