import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// A circular avatar: the photo if there is one, the initials if there is a
/// name, and the generic mark if there is neither.
///
/// **All three are ordinary states.** The intro accepts any name and accepts
/// none, and the photo is optional by design, so the fallbacks are not failures
/// to be apologised for — the icon is what somebody who gave neither should
/// see, and it should look deliberate.
///
/// Greyscale like everything else (ADR-0009): the initials sit in silver on the
/// elevated surface, which is the same pairing the rest of the app uses for a
/// filled control.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.photo,
    required this.name,
    this.size = 40,
    this.onTap,
  });

  /// The stored file, or null. Read by the caller so this stays synchronous —
  /// an avatar that resolves a Future rebuilds into place after the rest of
  /// the screen has drawn, which reads as a flicker.
  final File? photo;

  final String? name;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initials = initialsFor(name);
    final Widget inner;

    if (photo != null) {
      inner = Image.file(
        photo!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // The file keeps one path for the life of the install, so Flutter's
        // image cache would hand back the previous photo after a change. The
        // key changes with the file's modification time, which a copy updates.
        key: ValueKey<String>('${photo!.path}:${_stamp(photo!)}'),
        errorBuilder: (_, _, _) =>
            AvatarInitials(initials: initials, size: size),
      );
    } else {
      inner = AvatarInitials(initials: initials, size: size);
    }

    final circle = ClipOval(
      child: SizedBox(width: size, height: size, child: inner),
    );

    if (onTap == null) return circle;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: circle),
    );
  }

  static int _stamp(File f) {
    try {
      return f.lastModifiedSync().millisecondsSinceEpoch;
    } on Object {
      return 0;
    }
  }
}
