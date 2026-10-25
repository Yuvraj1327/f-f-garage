import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'responsive_shell.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class FfGarageApp extends ConsumerWidget {
  const FfGarageApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'F&F Garage',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // Light is the only look of the app (the reference design has no dark mode).
      themeMode: ThemeMode.light,
      routerConfig: router,
      builder: (context, child) =>
          ResponsiveShell(child: child ?? const SizedBox.shrink()),
    );
  }
}
