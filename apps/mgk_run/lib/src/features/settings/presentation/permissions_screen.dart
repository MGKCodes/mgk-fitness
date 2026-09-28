import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../health/domain/workout_source.dart';
import 'permissions_section.dart';

/// Location and Health, one tap off the settings index.
///
/// The section inside used to sit on the index itself, which cost four rows
/// and a five-line paragraph about iOS Settings paths — text nobody reads
/// until the one day they need it, on a screen everybody opens. That is the
/// textbook case for pushing a level down: the index now says what the
/// permissions are *set to*, and this screen says what to do about it.
class PermissionsScreen extends StatelessWidget {
  const PermissionsScreen({super.key, this.health});

  /// Injected for tests; the real reader otherwise.
  final WorkoutSource? health;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permissions')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: <Widget>[PermissionsSection(health: health, startIndex: 0)],
        ),
      ),
    );
  }
}
