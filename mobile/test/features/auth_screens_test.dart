import 'package:ff_garage/app/app.dart';
import 'package:ff_garage/core/config/app_config.dart';
import 'package:ff_garage/core/network/auth_failure.dart';
import 'package:ff_garage/core/providers/core_providers.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/providers/data_providers.dart';
import 'package:ff_garage/data/services/auth_gateway.dart';
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

Finder _field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  late FakeAuthGateway gateway;
  late FakeProfileRepository profiles;

  void useCustomer() {
    gateway = FakeAuthGateway();
    profiles = FakeProfileRepository(profileFor(UserRole.customer));
  }

  group('customer login', () {
    testWidgets('validates before calling the server', (tester) async {
      useCustomer();
      await tester.pumpWidget(_app(gateway, profiles));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();

      expect(find.text('Enter a valid email address'), findsNothing);
      expect(find.text('Enter your email address'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
      expect(gateway.lastEmail, isNull);
    });

    testWidgets('shows the server error and stays on the screen',
        (tester) async {
      useCustomer();
      gateway.signInError = AuthFailure.invalidCredentials;
      await tester.pumpWidget(_app(gateway, profiles));
      await tester.pumpAndSettle();

      await tester.enterText(_field('Email'), 'user@example.com');
      await tester.enterText(_field('Password'), 'wrong-password');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Incorrect email or password.'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('a successful sign-in moves to the customer home',
        (tester) async {
      useCustomer();
      await tester.pumpWidget(_app(gateway, profiles));
      await tester.pumpAndSettle();

      await tester.enterText(_field('Email'), 'user@example.com');
      await tester.enterText(_field('Password'), 'correct-password');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Hello, Test User'), findsOneWidget);
    });

    testWidgets('a driver account on the customer screen is turned away',
        (tester) async {
      gateway = FakeAuthGateway();
      profiles = FakeProfileRepository(profileFor(UserRole.driver));
      await tester.pumpWidget(_app(gateway, profiles));
      await tester.pumpAndSettle();

      await tester.enterText(_field('Email'), 'driver@example.com');
      await tester.enterText(_field('Password'), 'pw-123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.textContaining('not a customer account'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    });
  });

  group('driver login', () {
    testWidgets('signs in with a driver ID and reaches the driver home',
        (tester) async {
      gateway = FakeAuthGateway();
      profiles = FakeProfileRepository(profileFor(UserRole.driver));
      await tester.pumpWidget(_app(gateway, profiles));
      await tester.pumpAndSettle();

      await tester.tap(find.text('I am a driver'));
      await tester.pumpAndSettle();
      expect(find.text('Driver sign in'), findsOneWidget);
      // There is no registration option for drivers.
      expect(find.textContaining('Create'), findsNothing);

      await tester.enterText(_field('Driver ID'), 'Ravi01');
      await tester.enterText(_field('Password'), 'driver-pass');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(gateway.lastEmail, 'ravi01@drivers.ffgarage.invalid');
      expect(find.text('Your assigned jobs will appear here.'), findsOneWidget);
    });
  });

  group('registration', () {
    Future<void> fill(WidgetTester tester, {String confirm = 'password1'}) async {
      await tester.enterText(_field('Full name'), 'Asha Rao');
      await tester.enterText(_field('Email'), 'asha@example.com');
      await tester.enterText(_field('Mobile number'), '9876543210');
      await tester.enterText(_field('Password'), 'password1');
      await tester.enterText(_field('Confirm password'), confirm);
      await tester.ensureVisible(find.text('Create account').last);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
    }

    testWidgets('rejects mismatched passwords locally', (tester) async {
      useCustomer();
      await tester.pumpWidget(_app(gateway, profiles));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();

      await fill(tester, confirm: 'different1');

      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(gateway.lastEmail, isNull);
    });

    testWidgets('registers and signs in', (tester) async {
      useCustomer();
      await tester.pumpWidget(_app(gateway, profiles));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();

      await fill(tester);

      expect(gateway.lastMetadata, {
        'full_name': 'Asha Rao',
        'phone': '+919876543210',
      });
      expect(find.text('Hello, Test User'), findsOneWidget);
    });

    testWidgets('asks the user to confirm their email when required',
        (tester) async {
      useCustomer();
      gateway.signUpResult = SignUpResult.emailConfirmationRequired;
      await tester.pumpWidget(_app(gateway, profiles));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();

      await fill(tester);

      expect(find.text('Check your email'), findsOneWidget);
    });

    testWidgets('shows a duplicate-email error', (tester) async {
      useCustomer();
      gateway.signUpError = AuthFailure.emailAlreadyRegistered;
      await tester.pumpWidget(_app(gateway, profiles));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();

      await fill(tester);

      expect(find.textContaining('already exists'), findsOneWidget);
    });
  });

  group('profile', () {
    testWidgets('customer can edit the name and sign out', (tester) async {
      gateway = FakeAuthGateway(hasStoredSession: true);
      profiles = FakeProfileRepository(profileFor(UserRole.customer));
      await tester.pumpWidget(_app(gateway, profiles));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();

      await tester.enterText(_field('Full name'), 'New Name');
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      expect(profiles.lastFullName, 'New Name');
      expect(find.text('Profile updated.'), findsOneWidget);

      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      // Signing out asks first.
      expect(find.text('Sign out?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Sign out'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      expect(gateway.hasSession, isFalse);
    });

    testWidgets('driver sees read-only details', (tester) async {
      gateway = FakeAuthGateway(hasStoredSession: true);
      profiles = FakeProfileRepository(profileFor(UserRole.driver));
      await tester.pumpWidget(_app(gateway, profiles));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();

      expect(find.text('ravi01'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Save changes'), findsNothing);
    });
  });
}
