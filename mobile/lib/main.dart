import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/config_error_screen.dart';
import 'core/config/app_config.dart';
import 'core/providers/core_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load `.env` before anything reads configuration. A missing file is not an
  // error here: the empty configuration is reported on screen below.
  try {
    await dotenv.load(isOptional: true);
  } catch (_) {
    // An unreadable file is treated like a missing one.
  }

  final config = AppConfig.fromDotenv();
  // Refuse to start on missing values or when a server secret was put in `.env`.
  final problems = config.problems;
  if (problems.isNotEmpty) {
    runApp(ConfigErrorApp(problems: problems));
    return;
  }

  try {
    await Supabase.initialize(
      url: config.supabaseUrl,
      anonKey: config.supabaseAnonKey,
    );
  } catch (_) {
    runApp(
      const ConfigErrorApp(
        problems: [
          'Supabase could not be started with SUPABASE_URL and '
              'SUPABASE_ANON_KEY. Check both values.',
        ],
      ),
    );
    return;
  }

  runApp(
    ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(config)],
      child: const FfGarageApp(),
    ),
  );
}
