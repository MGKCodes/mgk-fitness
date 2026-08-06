import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// Lift — the Flutter rewrite of Liftio.
///
/// This is a shell, deliberately. The migration sequence is database first,
/// then Run (which already worked and only had to move), then this — so that
/// the rewrite lands into a system that has already been proven by code that
/// runs, rather than one designed speculatively around it.
///
/// What it does do is prove the wiring: the theme, fonts and components all
/// come from `mgk_ui`, so the day real screens arrive they inherit the suite's
/// design language rather than growing a second one.
void main() {
  runApp(const MgkLiftApp());
}

class MgkLiftApp extends StatelessWidget {
  const MgkLiftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lift',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const _ShellScreen(),
    );
  }
}

class _ShellScreen extends StatelessWidget {
  const _ShellScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionLabel('Lift'),
              const SizedBox(height: 12),
              Text('Nothing here yet', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'The workspace, the design system and the database are in '
                'place. Screens come next.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
