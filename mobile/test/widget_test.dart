import 'package:ff_garage/app/app.dart';
import 'package:ff_garage/core/config/app_config.dart';
import 'package:ff_garage/core/providers/core_providers.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/providers/data_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/fakes_driver.dart';
import 'support/fakes_notification.dart';

Widget _app(FakeAuthGateway gateway, FakeProfileRepository profiles) {
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(
        const AppConfig(
          apiBaseUrl: 'http://x',
          supabaseUrl: 'http://x',
          supabaseAnonKey: 'anon',
        ),
      ),
      authGatewayProvider.overrideWithValue(gateway),
      profileRepositoryProvider.overrideWithValue(profiles),
      driverWorkRepositoryProvider.overrideWithValue(FakeDriverWorkRepository()),
      notificationRepositoryProvider.overrideWithValue(FakeNotificationRepository()),
    ],
    child: const FfGarageApp(),
  );
}

void main() {
  testWidgets('signed-out users land on the customer login screen',
      (tester) async {
    await tester.pumpWidget(
      _app(FakeAuthGateway(), FakeProfileRepository(profileFor(UserRole.customer))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('a stored customer session opens the customer home',
      (tester) async {
    await tester.pumpWidget(
      _app(
        FakeAuthGateway(hasStoredSession: true),
        FakeProfileRepository(profileFor(UserRole.customer)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hello, Test User'), findsOneWidget);
  });

  testWidgets('a stored driver session opens the driver home', (tester) async {
    await tester.pumpWidget(
      _app(
        FakeAuthGateway(hasStoredSession: true),
        FakeProfileRepository(profileFor(UserRole.driver)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No jobs assigned to you right now.'), findsOneWidget);
  });

  testWidgets('a stored admin session opens the admin home', (tester) async {
    await tester.pumpWidget(
      _app(
        FakeAuthGateway(hasStoredSession: true),
        FakeProfileRepository(profileFor(UserRole.admin)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.byKey(const ValueKey('side-dashboard')), findsOneWidget);
  });

  testWidgets('an unreachable backend shows Retry instead of signing out',
      (tester) async {
    final gateway = FakeAuthGateway(hasStoredSession: true);
    final profiles = FakeProfileRepository(profileFor(UserRole.customer))
      ..error = networkError;
    await tester.pumpWidget(_app(gateway, profiles));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(gateway.signOutCalls, 0);

    profiles.error = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Hello, Test User'), findsOneWidget);
  });

  testWidgets('a revoked stored session ends on the login screen',
      (tester) async {
    final gateway = FakeAuthGateway(hasStoredSession: true);
    final profiles = FakeProfileRepository(profileFor(UserRole.customer))
      ..error = unauthorizedError;
    await tester.pumpWidget(_app(gateway, profiles));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(gateway.hasSession, isFalse);
  });
}
