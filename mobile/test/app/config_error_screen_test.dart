import 'package:ff_garage/app/config_error_screen.dart';
import 'package:ff_garage/core/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lists each problem and how to fix it, without any values',
      (tester) async {
    final config = AppConfig.fromMap(const {
      'SUPABASE_SERVICE_ROLE_KEY': 'super-secret-value',
    });
    await tester.pumpWidget(ConfigErrorApp(problems: config.problems));

    expect(find.text('App configuration needed'), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL is missing'), findsOneWidget);
    expect(find.textContaining('SUPABASE_ANON_KEY is missing'), findsOneWidget);
    expect(find.textContaining('SUPABASE_SERVICE_ROLE_KEY must not be'),
        findsOneWidget);
    expect(find.textContaining('copy mobile/.env.example'), findsOneWidget);
    expect(find.textContaining('super-secret-value'), findsNothing);
  });

  testWidgets('fits a small phone with a large font without overflowing',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.platformDispatcher.textScaleFactorTestValue = 2;

    await tester.pumpWidget(
      ConfigErrorApp(problems: AppConfig.fromMap(const {}).problems),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('App configuration needed'), findsOneWidget);
  });
}
