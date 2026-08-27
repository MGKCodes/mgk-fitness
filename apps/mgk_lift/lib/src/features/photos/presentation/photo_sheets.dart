import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/progress_photo.dart';

/// The three small decisions progress photos ask for, out of the two screens
/// that ask them.
///
/// **Extracted so they can be photographed.** All three were private methods on
/// a `State`, which meant the preview harness could not address them and no
/// screenshot of this app had ever contained one — including the two that the
/// exit sweep in [docs/navigation.md] had already caught shipping without a
/// dismiss affordance. A screen the review tool cannot reach is a screen that
/// gets reviewed once, by hand, and then never again.
///
/// They are functions rather than widgets because that is what the call sites
/// want: each is a question with an answer, awaited inline.

/// Camera or gallery. Returns true for the camera, false for the gallery, null
/// if dismissed.
///
/// Asked every time rather than remembered: the gallery is how you backfill a
/// photo you already took, and the camera is how you do this week — both are
/// normal and neither is the default.
Future<bool?> showPhotoSourceSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.surface,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.md),
            child: SheetHandle(bottomSpacing: 0),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.of(sheetContext).pop(true),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from photos'),
            onTap: () => Navigator.of(sheetContext).pop(false),
          ),
        ],
      ),
    ),
  );
}

/// What to do with one photo. Returns `'exclude'`, `'delete'`, or null.
///
/// The grab bar is load-bearing here more than anywhere: the loudest control on
/// this sheet deletes a photo that cannot be retaken, and it opens on a tap.
/// Somebody who mistapped needs to see a way out.
Future<String?> showPhotoActionsSheet(
  BuildContext context,
  ProgressPhoto photo,
) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surface,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.md),
            child: SheetHandle(bottomSpacing: 0),
          ),
          ListTile(
            leading: Icon(
              photo.isExcluded
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            title: Text(
              photo.isExcluded
                  ? 'Include in the sequence'
                  : 'Skip in the sequence',
            ),
            subtitle: const Text('The photo is kept either way'),
            onTap: () => Navigator.of(sheetContext).pop('exclude'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.danger),
            title: const Text(
              'Delete photo',
              style: TextStyle(color: AppColors.danger),
            ),
            onTap: () => Navigator.of(sheetContext).pop('delete'),
          ),
        ],
      ),
    ),
  );
}

/// The last word before a photo is gone. True to delete.
///
/// Blunt on purpose. There is no copy anywhere else, and a photo of your own
/// body from eight months ago cannot be retaken.
Future<bool?> confirmPhotoDelete(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Delete this photo?'),
      content: const Text(
        'It is only on this device, so this cannot be undone.',
      ),
      actions: <Widget>[
        AppTextButton(
          label: 'Keep it',
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}
