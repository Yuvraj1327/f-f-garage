import 'package:ff_garage/app/app.dart';
import 'package:ff_garage/core/config/app_config.dart';
import 'package:ff_garage/core/network/auth_failure.dart';
import 'package:ff_garage/core/providers/core_providers.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/providers/data_providers.dart';
import 'package:ff_garage/data/services/auth_gateway.dart';
import 'package:ff_garage/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

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
    ],
    child: const FfGarageApp(),
  );
}

final _googleButton = find.byKey(const ValueKey('google-sign-in'));

Future<void> _openRegister(WidgetTester tester) async {
  await tester.tap(find.text('New here? Create an account'));
  await tester.pumpAndSettle();
}

Future<void> _tapGoogle(WidgetTester tester) async {
  await tester.ensureVisible(_googleButton);
  await tester.tap(_googleButton);
  await tester.pumpAndSettle();
}

void main() {
  late FakeAuthGateway gateway;

  FakeProfileRepository customer() =>
      FakeProfileRepository(profileFor(UserRole.customer));

  setUp(() => gateway = FakeAuthGateway());

  group('the button', () {
    testWidgets('is on the sign-in and the sign-up screens', (tester) async {
      await tester.pumpWidget(_app(gateway, customer()));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsOneWidget);

      await _openRegister(tester);
      await tester.ensureVisible(_googleButton);
      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('driver sign-in has no Google option', (tester) async {
      await tester.pumpWidget(_app(gateway, customer()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I am a driver'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsNothing);
    });

    testWidgets('admin sign-in has no Google option', (tester) async {
      await tester.pumpWidget(_app(gateway, customer()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Admin sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsNothing);
    });
  });

  group('signing in', () {
    testWidgets('success loads the profile and opens the customer home',
        (tester) async {
      await tester.pumpWidget(_app(gateway, customer()));
      await tester.pumpAndSettle();

      await _tapGoogle(tester);

      expect(gateway.googleCalls, 1);
      expect(find.text('Hello, Test User'), findsOneWidget);
      // The session is kept, so the next start restores it (see restore test).
      expect(gateway.hasSession, isTrue);
    });

    testWidgets('success from the sign-up screen does the same',
        (tester) async {
      await tester.pumpWidget(_app(gateway, customer()));
      await tester.pumpAndSettle();
      await _openRegister(tester);

      await _tapGoogle(tester);

      expect(find.text('Hello, Test User'), findsOneWidget);
    });

    testWidgets('closing the account chooser is not an error', (tester) async {
      gateway.googleResult = GoogleSignInResult.cancelled;
      await tester.pumpWidget(_app(gateway, customer()));
      await tester.pumpAndSettle();

      await _tapGoogle(tester);

      expect(gateway.googleCalls, 1);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.byType(MessageBanner), findsNothing);
      // The button works again.
      expect(
        tester.widget<OutlinedButton>(_googleButton).onPressed,
        isNotNull,
      );
    });

    testWidgets('a Web redirect keeps the button disabled, without an error',
        (tester) async {
      gateway.googleResult = GoogleSignInResult.redirecting;
      await tester.pumpWidget(_app(gateway, customer()));
      await tester.pumpAndSettle();

      await _tapGoogle(tester);

      expect(find.byType(MessageBanner), findsNothing);
      expect(tester.widget<OutlinedButton>(_googleButton).onPressed, isNull);
    });

    for (final failure in [
      AuthFailure.network,
      AuthFailure.googleNotConfigured,
      AuthFailure.googleFailed,
      AuthFailure.accountDisabled,
    ]) {
      testWidgets('shows "${failure.message}" and stays signed out',
          (tester) async {
        gateway.googleError = failure;
        await tester.pumpWidget(_app(gateway, customer()));
        await tester.pumpAndSettle();

        await _tapGoogle(tester);

        expect(find.text(failure.message), findsOneWidget);
        expect(find.text('Welcome back'), findsOneWidget);
        expect(gateway.hasSession, isFalse);
      });
    }

    testWidgets('an error can be followed by a successful retry',
        (tester) async {
      gateway.googleError = AuthFailure.network;
      await tester.pumpWidget(_app(gateway, customer()));
      await tester.pumpAndSettle();
      await _tapGoogle(tester);
      expect(find.text(AuthFailure.network.message), findsOneWidget);

      gateway.googleError = null;
      await _tapGoogle(tester);
      expect(find.text('Hello, Test User'), findsOneWidget);
    });

    testWidgets('a Google account that belongs to a driver is turned away',
        (tester) async {
      await tester.pumpWidget(
        _app(gateway, FakeProfileRepository(profileFor(UserRole.driver))),
      );
      await tester.pumpAndSettle();

      await _tapGoogle(tester);

      expect(find.textContaining('not a customer account'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(gateway.signOutCalls, 1);
      expect(gateway.hasSession, isFalse);
    });

    testWidgets('an administrator account is not let in either',
        (tester) async {
      await tester.pumpWidget(
        _app(gateway, FakeProfileRepository(profileFor(UserRole.admin))),
      );
      await tester.pumpAndSettle();

      await _tapGoogle(tester);

      expect(find.textContaining('not a customer account'), findsOneWidget);
      expect(gateway.hasSession, isFalse);
    });

    testWidgets('a disabled account is refused after Google signs it in',
        (tester) async {
      await tester.pumpWidget(
        _app(
          gateway,
          FakeProfileRepository(profileFor(UserRole.customer, isActive: false)),
        ),
      );
      await tester.pumpAndSettle();

      await _tapGoogle(tester);

      expect(find.text(AuthFailure.accountDisabled.message), findsOneWidget);
      expect(gateway.hasSession, isFalse);
    });
  });

  group('session persistence', () {
    testWidgets('a stored Google session is restored on the next start',
        (tester) async {
      gateway = FakeAuthGateway(hasStoredSession: true);
      await tester.pumpWidget(_app(gateway, customer()));
      await tester.pumpAndSettle();

      expect(find.text('Hello, Test User'), findsOneWidget);
      expect(gateway.googleCalls, 0);
    });
  });
}
