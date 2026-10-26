import 'package:ff_garage/app/router/app_routes.dart';
import 'package:ff_garage/app/theme/app_theme.dart';
import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/core/network/auth_failure.dart';
import 'package:ff_garage/core/preferences/app_preferences.dart';
import 'package:ff_garage/core/widgets/app_nav.dart';
import 'package:ff_garage/core/widgets/status_badge.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/booking_journey.dart';
import '../support/fakes_driver.dart';
import '../support/fakes_garage.dart';
import '../support/pump_app.dart';

Finder _nav(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

List<String> _navLabels(WidgetTester tester) => tester
    .widgetList<NavigationDestination>(find.byType(NavigationDestination))
    .map((d) => d.label)
    .toList();

ThemeMode _themeMode(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

Brightness _brightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first)).brightness;

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav-settings')));
  await tester.pumpAndSettle();
}

void main() {
  group('role-based bottom navigation', () {
    test('each role has exactly its own items', () {
      List<String> labels(UserRole r) =>
          navItemsFor(r).map((i) => i.label).toList();
      expect(labels(UserRole.customer),
          ['Home', 'My Bookings', 'Support', 'Settings']);
      expect(labels(UserRole.driver),
          ['My Jobs', 'History', 'Earnings', 'Settings']);
      expect(labels(UserRole.admin),
          ['Dashboard', 'Bookings', 'Drivers', 'Services', 'Settings']);
    });

    testWidgets('customer bar', (tester) async {
      await AppHarness(role: UserRole.customer).pump(tester);
      expect(_navLabels(tester),
          ['Home', 'My Bookings', 'Support', 'Settings']);
    });

    testWidgets('driver bar moves between jobs, history, earnings, settings',
        (tester) async {
      await AppHarness(role: UserRole.driver).pump(tester);
      expect(_navLabels(tester), ['My Jobs', 'History', 'Earnings', 'Settings']);

      await tester.tap(_nav('History'));
      await tester.pumpAndSettle();
      expect(find.text('No finished jobs yet.'), findsOneWidget);
      expect(_navLabels(tester).length, 4);

      await tester.tap(_nav('Earnings'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('earnings-note')), findsOneWidget);

      await tester.tap(_nav('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Change password'), findsOneWidget);

      await tester.tap(_nav('My Jobs'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No jobs assigned'), findsOneWidget);
    });

    testWidgets('admin bar opens the management screens', (tester) async {
      await AppHarness(role: UserRole.admin).pump(tester);
      expect(_navLabels(tester),
          ['Dashboard', 'Bookings', 'Drivers', 'Services', 'Settings']);

      await tester.tap(_nav('Drivers'));
      await tester.pumpAndSettle();
      expect(find.text('Add driver'), findsOneWidget);
      expect(_navLabels(tester).length, 5);

      await tester.tap(_nav('Services'));
      await tester.pumpAndSettle();
      expect(find.text('Add service'), findsOneWidget);

      await tester.tap(_nav('Bookings'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('booking-search')), findsOneWidget);

      await tester.tap(_nav('Dashboard'));
      await tester.pumpAndSettle();
      expect(find.text('Service areas'), findsOneWidget);
    });

    testWidgets('the other admin modules stay reachable from the dashboard',
        (tester) async {
      await AppHarness(role: UserRole.admin).pump(tester);
      expect(find.text('Service areas'), findsOneWidget);
      expect(find.text('Availability'), findsOneWidget);
      expect(find.text('Garage details'), findsOneWidget);
    });
  });

  group('settings screen', () {
    testWidgets('customer sees account, theme, notifications, help, about',
        (tester) async {
      useTallScreen(tester);
      await AppHarness(role: UserRole.customer).pump(tester);
      await _openSettings(tester);

      expect(find.text('Edit profile'), findsOneWidget);
      expect(find.text('Change password'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('System default'), findsOneWidget);
      expect(find.byKey(const ValueKey('pref-badge')), findsOneWidget);
      expect(find.text('Help & Support'), findsOneWidget);
      expect(find.text('About App'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);
      // Business settings are not for customers.
      expect(find.byKey(const ValueKey('settings-garage')), findsNothing);
    });

    testWidgets('driver gets no customer notification switches or garage',
        (tester) async {
      useTallScreen(tester);
      await AppHarness(role: UserRole.driver).pump(tester);
      await _openSettings(tester);

      expect(find.text('ravi01'), findsOneWidget);
      expect(find.byKey(const ValueKey('pref-badge')), findsNothing);
      expect(find.byKey(const ValueKey('settings-garage')), findsNothing);
      expect(find.text('Change password'), findsOneWidget);
    });

    testWidgets('admin also sees the garage details', (tester) async {
      useTallScreen(tester);
      await AppHarness(role: UserRole.admin).pump(tester);
      await _openSettings(tester);
      expect(find.byKey(const ValueKey('settings-garage')), findsOneWidget);
      expect(find.byKey(const ValueKey('pref-badge')), findsNothing);
    });

    testWidgets('the profile page has no role field to change',
        (tester) async {
      useTallScreen(tester);
      await AppHarness(role: UserRole.customer).pump(tester);
      await _openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('settings-profile')));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Full name'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Role'), findsNothing);
    });

    testWidgets('a customer cannot open the garage details by address',
        (tester) async {
      await AppHarness(role: UserRole.customer).pump(tester);
      goTo(tester, AppRoutes.settingsGarage);
      await tester.pumpAndSettle();
      expect(find.text('Garage name'), findsNothing);
      expect(find.text('Hello, Test User'), findsOneWidget);
    });

    testWidgets('about and privacy pages open', (tester) async {
      useTallScreen(tester);
      await AppHarness(role: UserRole.customer).pump(tester);
      await _openSettings(tester);

      await tester.tap(find.byKey(const ValueKey('settings-about')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Version'), findsOneWidget);
      // The garage's saved details appear here too.
      expect(find.text('Phone: +919876543210'), findsOneWidget);

      goTo(tester, AppRoutes.settingsPrivacy);
      await tester.pumpAndSettle();
      expect(find.text('What we collect'), findsOneWidget);
    });

    testWidgets('help & support opens the support screen', (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(role: UserRole.driver);
      await harness.pump(tester);
      await _openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('settings-help')));
      await tester.pumpAndSettle();
      expect(find.text('+919876543210'), findsOneWidget);
    });

    testWidgets('logout asks first, then returns to sign-in', (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(role: UserRole.customer);
      await harness.pump(tester);
      await _openSettings(tester);

      await tester.tap(find.byKey(const ValueKey('settings-logout')));
      await tester.pumpAndSettle();
      expect(find.text('Sign out?'), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Sign out'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      expect(harness.gateway.hasSession, isFalse);
    });
  });

  group('theme', () {
    testWidgets('light is the default', (tester) async {
      await AppHarness(role: UserRole.customer).pump(tester);
      expect(_themeMode(tester), ThemeMode.light);
      expect(_brightness(tester), Brightness.light);
    });

    testWidgets('dark applies at once and is saved', (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(role: UserRole.customer);
      await harness.pump(tester);
      await _openSettings(tester);

      await tester.tap(find.byKey(const ValueKey('theme-dark')));
      await tester.pumpAndSettle();

      expect(_themeMode(tester), ThemeMode.dark);
      expect(_brightness(tester), Brightness.dark);
      expect(harness.preferences.getString(ThemeController.key), 'dark');
    });

    testWidgets('the choice survives an app restart', (tester) async {
      useTallScreen(tester);
      final saved = MemoryPreferences();
      final first = AppHarness(role: UserRole.customer, preferences: saved);
      await first.pump(tester);
      await _openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('theme-dark')));
      await tester.pumpAndSettle();

      // "Restart": a brand-new app that reads the same saved settings.
      await tester.pumpWidget(const SizedBox());
      await AppHarness(role: UserRole.customer, preferences: saved)
          .pump(tester);
      expect(_themeMode(tester), ThemeMode.dark);
      expect(_brightness(tester), Brightness.dark);
    });

    testWidgets('the choice is kept through logout and the next sign-in',
        (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(role: UserRole.customer);
      await harness.pump(tester);
      await _openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('theme-dark')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('settings-logout')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Sign out'),
      ));
      await tester.pumpAndSettle();
      // The sign-in screen is dark too.
      expect(find.text('Welcome back'), findsOneWidget);
      expect(_themeMode(tester), ThemeMode.dark);

      await enter(tester, 'Email', 'user@example.com');
      await enter(tester, 'Password', 'Whatever#123');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Hello, Test User'), findsOneWidget);
      expect(_themeMode(tester), ThemeMode.dark);
    });

    testWidgets('system default follows the phone', (tester) async {
      useTallScreen(tester);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final harness = AppHarness(role: UserRole.customer);
      await harness.pump(tester);
      expect(_brightness(tester), Brightness.light); // default is Light

      await _openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('theme-system')));
      await tester.pumpAndSettle();
      expect(_themeMode(tester), ThemeMode.system);
      expect(_brightness(tester), Brightness.dark);
      expect(harness.preferences.getString(ThemeController.key), 'system');

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(_brightness(tester), Brightness.light);
    });

    for (final role in UserRole.values) {
      testWidgets('dark theme renders the ${role.name} home and settings',
          (tester) async {
        useTallScreen(tester);
        final saved = MemoryPreferences()
          ..setString(ThemeController.key, 'dark');
        await AppHarness(role: role, preferences: saved).pump(tester);
        expect(_brightness(tester), Brightness.dark);
        await _openSettings(tester);
        expect(find.text('Settings'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('status badges use tinted colours on the dark theme',
        (tester) async {
      Future<Color?> badgeFill(ThemeData theme) async {
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: StatusBadge(label: 'Done', tone: BadgeTone.success),
          ),
        ));
        final box = tester.widget<DecoratedBox>(find
            .descendant(
              of: find.byType(StatusBadge),
              matching: find.byType(DecoratedBox),
            )
            .first);
        return (box.decoration as BoxDecoration).color;
      }

      final light = await badgeFill(AppTheme.light());
      final dark = await badgeFill(AppTheme.dark());
      expect(dark, isNot(light));
      expect(dark!.a, lessThan(1)); // translucent tint, not a pastel block
    });

    test('unknown or missing saved values fall back to light', () {
      expect(ThemeController.parse(null), ThemeMode.light);
      expect(ThemeController.parse('purple'), ThemeMode.light);
      expect(ThemeController.parse('dark'), ThemeMode.dark);
      expect(ThemeController.parse('system'), ThemeMode.system);
    });
  });

  group('notification preferences', () {
    testWidgets('are saved and switch the unread badge off', (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(role: UserRole.customer);
      await harness.pump(tester);
      await _openSettings(tester);

      await tester.tap(find.byKey(const ValueKey('pref-badge')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pref-auto-refresh')));
      await tester.pumpAndSettle();

      expect(harness.preferences.getBool(NotificationPrefsController.badgeKey),
          isFalse);
      expect(harness.preferences.getBool(NotificationPrefsController.refreshKey),
          isFalse);
    });
  });

  group('change password', () {
    Future<void> openPassword(WidgetTester tester) async {
      await _openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('settings-password')));
      await tester.pumpAndSettle();
    }

    Future<void> fill(WidgetTester tester,
        {String current = 'OldPass#1234',
        String next = 'NewPass#5678',
        String? confirm}) async {
      await tester.enterText(
          find.byKey(const ValueKey('current-password')), current);
      await tester.enterText(find.byKey(const ValueKey('new-password')), next);
      await tester.enterText(
          find.byKey(const ValueKey('confirm-password')), confirm ?? next);
    }

    testWidgets('changes the password after checking the current one',
        (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(role: UserRole.customer);
      await harness.pump(tester);
      await openPassword(tester);

      await fill(tester);
      await tapText(tester, 'Update password');

      expect(harness.gateway.changedTo, 'NewPass#5678');
      expect(harness.gateway.changeEmail, 'user@example.com');
      expect(find.textContaining('Password changed'), findsOneWidget);
    });

    testWidgets('a driver is checked against their driver-ID sign-in',
        (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(role: UserRole.driver);
      await harness.pump(tester);
      await openPassword(tester);

      await fill(tester);
      await tapText(tester, 'Update password');

      expect(harness.gateway.changeEmail, contains('ravi01'));
      expect(harness.gateway.changedTo, 'NewPass#5678');
    });

    testWidgets('a wrong current password is refused', (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(role: UserRole.customer);
      await harness.pump(tester);
      await openPassword(tester);

      await fill(tester, current: 'not-my-password');
      await tapText(tester, 'Update password');

      expect(find.text('Your current password is not correct.'),
          findsOneWidget);
      expect(harness.gateway.changedTo, isNull);
    });

    testWidgets('checks length, match and difference before calling the server',
        (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(role: UserRole.customer);
      await harness.pump(tester);
      await openPassword(tester);

      await fill(tester, next: 'short', confirm: 'short');
      await tapText(tester, 'Update password');
      expect(find.text('Use at least 8 characters'), findsOneWidget);

      await fill(tester, confirm: 'Different#999');
      await tapText(tester, 'Update password');
      expect(find.text('Passwords do not match'), findsOneWidget);

      await fill(tester, current: 'SamePass#123', next: 'SamePass#123');
      await tapText(tester, 'Update password');
      expect(find.text('Choose a different password from the current one'),
          findsOneWidget);
      expect(harness.gateway.changedTo, isNull);
    });

    testWidgets('shows a weak-password or network failure from the server',
        (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(role: UserRole.customer);
      await harness.pump(tester);
      await openPassword(tester);

      harness.gateway.changePasswordError = AuthFailure.weakPassword;
      await fill(tester);
      await tapText(tester, 'Update password');
      expect(find.textContaining('too weak'), findsOneWidget);

      harness.gateway.changePasswordError = AuthFailure.network;
      await tapText(tester, 'Update password');
      expect(find.textContaining('Unable to reach the server'), findsOneWidget);
    });
  });

  group('garage details (admin)', () {
    Future<void> openGarage(WidgetTester tester) async {
      await _openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('settings-garage')));
      await tester.pumpAndSettle();
    }

    testWidgets('loads the current details and saves changes', (tester) async {
      useTallScreen(tester);
      final garage = FakeGarageSettingsRepository();
      await AppHarness(role: UserRole.admin, garage: garage).pump(tester);
      await openGarage(tester);

      expect(find.text('F&F Two Wheeler Garage'), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('garage-name')), 'F&F Garage Pune');
      await tester.enterText(
          find.byKey(const ValueKey('garage-phone')), '+91 98765 11111');
      await tester.enterText(
          find.byKey(const ValueKey('garage-email')), 'hello@ffgarage.in');
      await tapText(tester, 'Save');

      expect(garage.saves, 1);
      expect(garage.current.name, 'F&F Garage Pune');
      expect(garage.current.phone, '+91 98765 11111');
      expect(garage.current.email, 'hello@ffgarage.in');
      expect(find.text('Garage details saved.'), findsOneWidget);
    });

    testWidgets('does not save a blank name or a bad email', (tester) async {
      useTallScreen(tester);
      final garage = FakeGarageSettingsRepository();
      await AppHarness(role: UserRole.admin, garage: garage).pump(tester);
      await openGarage(tester);

      await tester.enterText(find.byKey(const ValueKey('garage-name')), '  ');
      await tester.enterText(
          find.byKey(const ValueKey('garage-email')), 'not-an-email');
      await tapText(tester, 'Save');

      expect(find.text('Enter the garage name'), findsOneWidget);
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(garage.saves, 0);
    });

    testWidgets('shows the server error when saving fails', (tester) async {
      useTallScreen(tester);
      final garage = FakeGarageSettingsRepository();
      await AppHarness(role: UserRole.admin, garage: garage).pump(tester);
      await openGarage(tester);

      garage.error = forbiddenError;
      await tapText(tester, 'Save');
      expect(find.text('No access'), findsOneWidget);
    });

    testWidgets('a load failure offers Retry', (tester) async {
      useTallScreen(tester);
      final garage = FakeGarageSettingsRepository()
        ..error = const ApiException(
          type: ApiErrorType.network,
          message: 'No connection.',
        );
      await AppHarness(role: UserRole.admin, garage: garage).pump(tester);
      await openGarage(tester);
      expect(find.text('Retry'), findsOneWidget);

      garage.error = null;
      await tapText(tester, 'Retry');
      expect(find.byKey(const ValueKey('garage-name')), findsOneWidget);
    });

    testWidgets('opens from the dashboard too', (tester) async {
      useTallScreen(tester);
      await AppHarness(role: UserRole.admin).pump(tester);
      await tapText(tester, 'Garage details');
      expect(find.byKey(const ValueKey('garage-name')), findsOneWidget);
    });
  });

  group('driver history and earnings', () {
    testWidgets('earnings shows real counts and no invented amounts',
        (tester) async {
      useTallScreen(tester);
      final now = DateTime.now();
      final harness = AppHarness(
        role: UserRole.driver,
        driverWork: FakeDriverWorkRepository(jobs: [
          driverJob(),
          driverJob(
            id: 'done1',
            number: 2,
            status: BookingStatus.completed,
            next: null,
            date: DateTime(now.year, now.month, now.day),
          ),
        ]),
      );
      await harness.pump(tester);
      await tester.tap(_nav('Earnings'));
      await tester.pumpAndSettle();

      expect(find.text('Completed today'), findsOneWidget);
      expect(find.text('Jobs finished in total'), findsOneWidget);
      expect(find.textContaining('Payouts are not recorded'), findsOneWidget);
      expect(find.textContaining('₹'), findsNothing);
    });

    testWidgets('earnings reports a load failure with Retry', (tester) async {
      final work = FakeDriverWorkRepository()..error = networkError;
      await AppHarness(role: UserRole.driver, driverWork: work).pump(tester);
      await tester.tap(_nav('Earnings'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
