import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Every control acknowledges the finger** — principle 9.
///
/// Material's buttons acknowledge a tap through `Feedback.forTap`, which gives
/// Android a haptic and iOS nothing, so a raw `FilledButton` is silent under
/// the finger on the platform Lift ships to first. The `mgk_ui` wrappers go
/// through `PressScale`, which settles on a spring and ticks on both. This
/// fails on a raw button in presentation code, so the sweep that removed them
/// cannot quietly drift back.
///
/// An `InkWell` inside a `PressScale` is allowed: the ripple is Material's, the
/// feel is ours.
void main() {
  test('no raw Material button in presentation code', () {
    final raw = RegExp(
      r'\b(FilledButton|OutlinedButton|ElevatedButton)(\.icon)?\(|'
      r'\bTextButton\.icon\(|\bInkWell\(',
    );
    final offenders = <String>[];
    for (final file in Directory('lib/src').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (!file.path.replaceAll(r'\', '/').contains('/presentation/')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//') || !raw.hasMatch(line)) continue;
        final above = lines.sublist((i - 6).clamp(0, i), i + 1).join('\n');
        if (above.contains('PressScale(')) continue;
        offenders.add('${file.path}:${i + 1}  ${line.trim()}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use AppFilledButton, AppOutlinedButton, AppTextButton or '
          'PrimaryButton, or wrap the tappable in PressScale.',
    );
  });
}
