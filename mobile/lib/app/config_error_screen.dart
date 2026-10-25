import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

/// Shown instead of the app when `.env` is missing or unusable. It lists what
/// is wrong (names only, never values) and how to fix it, so a developer is not
/// left with a blank screen or a crash.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.problems});

  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'F&F Garage',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: ConfigErrorScreen(problems: problems),
    );
  }
}

class ConfigErrorScreen extends StatelessWidget {
  const ConfigErrorScreen({super.key, required this.problems});

  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Icon(Icons.settings_outlined, size: 48, color: scheme.error),
                const SizedBox(height: 16),
                Text('App configuration needed', style: textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                  'The app cannot start because its settings are incomplete.',
                ),
                const SizedBox(height: 16),
                for (final problem in problems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline, size: 20, color: scheme.error),
                        const SizedBox(width: 8),
                        Expanded(child: Text(problem)),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  'To fix it: copy mobile/.env.example to mobile/.env, fill in '
                  'the public values, then restart the app. Never put a '
                  'service-role key, database password or payment secret in '
                  'this file.',
                  style: textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
