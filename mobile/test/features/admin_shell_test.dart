import 'package:ff_garage/app/router/app_routes.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/booking_journey.dart';
import '../support/pump_app.dart';

void _size(WidgetTester tester, double width, [double height = 900]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

const _entries = {
  'side-dashboard': 'Dashboard',
  'side-bookings': 'Bookings',
  'side-drivers': 'Drivers',
  'side-services': 'Services',
  'side-coupons': 'Coupons',
  'side-areas': 'Service Areas',
  'side-availability': 'Availability',
  'side-garage': 'Garage Details',
  'side-settings': 'Settings',
};

void main() {
  group('desktop', () {
    testWidgets('shows the full sidebar with every section, grouped',
        (tester) async {
      _size(tester, 1400);
      await AppHarness(role: UserRole.admin).pump(tester);

      for (final entry in _entries.entries) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey(entry.key)),
            matching: find.text(entry.value),
          ),
          findsOneWidget,
          reason: entry.value,
        );
      }
      for (final group in ['OVERVIEW', 'OPERATIONS', 'CATALOGUE', 'SETUP']) {
        expect(find.text(group), findsOneWidget);
      }
      expect(find.byType(Drawer), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('the menu button collapses it to icons and back',
        (tester) async {
      _size(tester, 1400);
      await AppHarness(role: UserRole.admin).pump(tester);
      expect(find.text('OPERATIONS'), findsOneWidget);

      await tapKey(tester, 'admin-menu');
      expect(find.text('OPERATIONS'), findsNothing);
      expect(find.byKey(const ValueKey('side-bookings')), findsOneWidget);
      expect(find.byTooltip('Bookings'), findsOneWidget);

      await tapKey(tester, 'admin-menu');
      expect(find.text('OPERATIONS'), findsOneWidget);
    });

    testWidgets('starts as a slim rail on a tablet', (tester) async {
      _size(tester, 800);
      await AppHarness(role: UserRole.admin).pump(tester);
      expect(find.text('OPERATIONS'), findsNothing);
      expect(find.byKey(const ValueKey('side-drivers')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every sidebar entry opens its existing screen',
        (tester) async {
      _size(tester, 1400);
      await AppHarness(role: UserRole.admin).pump(tester);

      await tapKey(tester, 'side-bookings');
      expect(find.byKey(const ValueKey('booking-search')), findsOneWidget);
      await tapKey(tester, 'side-drivers');
      expect(find.text('Add driver'), findsOneWidget);
      await tapKey(tester, 'side-services');
      expect(find.text('Add service'), findsOneWidget);
      await tapKey(tester, 'side-coupons');
      expect(find.byKey(const ValueKey('new-coupon')), findsOneWidget);
      await tapKey(tester, 'side-areas');
      expect(find.text('Add PIN code'), findsOneWidget);
      await tapKey(tester, 'side-availability');
      expect(find.text('Time slots'), findsOneWidget);
      await tapKey(tester, 'side-garage');
      expect(find.byKey(const ValueKey('garage-name')), findsOneWidget);
      await tapKey(tester, 'side-settings');
      expect(find.text('Change password'), findsOneWidget);
      await tapKey(tester, 'side-dashboard');
      expect(find.text('Quick actions'), findsOneWidget);
    });

    testWidgets('the current section is marked selected', (tester) async {
      _size(tester, 1400);
      await AppHarness(role: UserRole.admin).pump(tester);
      Finder selected(String key) => find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.selected == true,
            ),
          );
      expect(selected('side-dashboard'), findsOneWidget);
      expect(selected('side-drivers'), findsNothing);
      await tapKey(tester, 'side-drivers');
      expect(selected('side-drivers'), findsOneWidget);
      expect(selected('side-dashboard'), findsNothing);
    });
  });

  group('mobile', () {
    testWidgets('uses a drawer, not a squeezed sidebar', (tester) async {
      _size(tester, 400, 800);
      await AppHarness(role: UserRole.admin).pump(tester);
      expect(find.byKey(const ValueKey('side-drivers')), findsNothing);
      expect(find.byKey(const ValueKey('admin-menu')), findsOneWidget);

      await tapKey(tester, 'admin-menu');
      expect(find.byType(Drawer), findsOneWidget);
      for (final key in _entries.keys) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      expect(find.text('F&F Garage'), findsOneWidget);
    });

    testWidgets('choosing an entry closes the drawer and opens the screen',
        (tester) async {
      _size(tester, 400, 800);
      await AppHarness(role: UserRole.admin).pump(tester);
      await tapKey(tester, 'admin-menu');
      await tapKey(tester, 'side-drivers');
      expect(find.byType(Drawer), findsNothing);
      expect(find.text('Add driver'), findsOneWidget);
    });

    testWidgets('the dashboard does not overflow on a small phone',
        (tester) async {
      _size(tester, 320, 640);
      await AppHarness(role: UserRole.admin).pump(tester);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('top bar', () {
    testWidgets('shows the page title and the profile menu', (tester) async {
      _size(tester, 1400);
      await AppHarness(role: UserRole.admin).pump(tester);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Dashboard')),
        findsOneWidget,
      );
      await tapKey(tester, 'admin-profile-menu');
      expect(find.byKey(const ValueKey('admin-menu-settings')), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-menu-signout')), findsOneWidget);
    });

    testWidgets('Settings in the profile menu opens settings', (tester) async {
      _size(tester, 1400);
      await AppHarness(role: UserRole.admin).pump(tester);
      await tapKey(tester, 'admin-profile-menu');
      await tapKey(tester, 'admin-menu-settings');
      expect(find.text('Change password'), findsOneWidget);
    });

    testWidgets('Sign out asks first, then signs out', (tester) async {
      _size(tester, 1400);
      final harness = AppHarness(role: UserRole.admin);
      await harness.pump(tester);
      await tapKey(tester, 'admin-profile-menu');
      await tapKey(tester, 'admin-menu-signout');
      expect(find.text('Sign out?'), findsOneWidget);
      await tapText(tester, 'Cancel');
      expect(harness.gateway.hasSession, isTrue);

      await tapKey(tester, 'admin-profile-menu');
      await tapKey(tester, 'admin-menu-signout');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();
      expect(harness.gateway.hasSession, isFalse);
    });
  });

  group('role access', () {
    testWidgets('a driver cannot open any admin page', (tester) async {
      _size(tester, 1400);
      await AppHarness(role: UserRole.driver).pump(tester);
      for (final route in [
        AppRoutes.adminHome,
        AppRoutes.adminBookings,
        AppRoutes.adminDrivers,
        AppRoutes.adminServices,
        AppRoutes.adminCoupons,
        AppRoutes.adminAreas,
        AppRoutes.adminAvailability,
      ]) {
        goTo(tester, route);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('side-dashboard')), findsNothing,
            reason: route);
        expect(find.byKey(const ValueKey('nav-jobs')), findsOneWidget,
            reason: route);
      }
    });

    testWidgets('a customer cannot open the admin dashboard', (tester) async {
      await AppHarness(role: UserRole.customer).pump(tester);
      goTo(tester, AppRoutes.adminHome);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('side-dashboard')), findsNothing);
      expect(find.text('Quick actions'), findsNothing);
    });
  });
}
