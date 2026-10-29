import 'package:ff_garage/app/router/app_routes.dart';
import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/core/widgets/filter_pill.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/booking_journey.dart';
import '../support/fakes.dart';
import '../support/fakes_booking.dart';
import '../support/fakes_catalog.dart';
import '../support/fakes_driver.dart';
import '../support/pump_app.dart';

Finder _navLabel(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

Finder _card(String key, String value) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.text(value),
    );

void main() {
  group('customer bottom navigation', () {
    testWidgets('shows Home, My Bookings, Support and Settings', (tester) async {
      final harness = AppHarness(role: UserRole.customer);
      await harness.pump(tester);

      expect(find.byType(NavigationBar), findsOneWidget);
      for (final label in ['Home', 'My Bookings', 'Support', 'Settings']) {
        expect(_navLabel(label), findsOneWidget);
      }
    });

    testWidgets('moves between the real screens and keeps the bar',
        (tester) async {
      final harness = AppHarness(role: UserRole.customer);
      await harness.pump(tester);

      await tester.tap(_navLabel('My Bookings'));
      await tester.pumpAndSettle();
      expect(find.byType(FilterPill), findsWidgets);
      expect(find.byType(NavigationBar), findsOneWidget);

      await tester.tap(_navLabel('Support'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Help & support'), findsWidgets);

      await tester.tap(_navLabel('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Settings')),
        findsOneWidget,
      );

      await tester.tap(_navLabel('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Hello, Test User'), findsOneWidget);
    });
  });

  group('customer home and service list', () {
    testWidgets('shows real catalogue services in Popular Services',
        (tester) async {
      final harness = AppHarness(
        role: UserRole.customer,
        catalog: FakeCatalogRepository([
          service(),
          service(id: 's2', name: 'Brake Check'),
        ]),
      );
      await harness.pump(tester);

      expect(find.text('Hello, Test User'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Popular Services'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Popular Services'), findsOneWidget);
      expect(find.text('Brake Check'), findsWidgets);
    });

    testWidgets('searching the service list filters it, and can come up empty',
        (tester) async {
      final harness = AppHarness(
        role: UserRole.customer,
        catalog: FakeCatalogRepository([
          service(),
          service(id: 's2', name: 'Brake Check'),
        ]),
      );
      await harness.pump(tester);
      goTo(tester, AppRoutes.browseServices);
      await tester.pumpAndSettle();

      expect(find.text('General Service'), findsOneWidget);
      expect(find.text('Brake Check'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'brake');
      await tester.pumpAndSettle();
      expect(find.text('General Service'), findsNothing);
      expect(find.text('Brake Check'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No services match your search.'), findsOneWidget);
    });
  });

  group('driver dashboard summary', () {
    testWidgets("shows Today's Summary with the real open-job count",
        (tester) async {
      final harness = AppHarness(
        role: UserRole.driver,
        driverWork: FakeDriverWorkRepository(jobs: [
          driverJob(),
          driverJob(id: 'b2', number: 2),
        ]),
      );
      await harness.pump(tester);

      expect(find.text("Today's Summary"), findsOneWidget);
      expect(find.text('Open jobs'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('is left out when the jobs cannot be loaded', (tester) async {
      final work = FakeDriverWorkRepository()
        ..error = const ApiException(
          type: ApiErrorType.network,
          message: 'No connection.',
        );
      final harness = AppHarness(role: UserRole.driver, driverWork: work);
      await harness.pump(tester);

      expect(find.text("Today's Summary"), findsNothing);
      expect(find.text('No connection.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('admin dashboard', () {
    testWidgets('shows booking, revenue and driver figures from the server',
        (tester) async {
      final ravi = driverAccount();
      final sam = driverAccount(id: 'd2', loginId: 'sam02', name: 'Sam', active: false);
      final bookings = FakeAdminBookingRepository(
        drivers: [ravi, sam],
        bookings: [
          booking(id: 'a', number: 1, status: BookingStatus.completed),
          booking(id: 'b', number: 2, status: BookingStatus.cancelled),
          booking(id: 'c', number: 3, status: BookingStatus.confirmed),
          booking(id: 'd', number: 4),
        ],
      );
      final drivers = FakeAdminDriverRepository(drivers: [ravi, sam]);
      final harness = AppHarness(
        role: UserRole.admin,
        adminDrivers: drivers,
        adminBookings: bookings,
        dashboard: FakeDashboardRepository(bookings, drivers,
            collected: 1500, refunded: 200),
      );
      await harness.pump(tester);

      expect(_card('stat-total', '4'), findsOneWidget);
      expect(_card('stat-completed', '1'), findsOneWidget);
      expect(_card('stat-pending', '2'), findsOneWidget);
      expect(_card('stat-drivers', '1'), findsOneWidget);
      expect(_card('stat-revenue', '₹1300'), findsOneWidget);
      expect(find.textContaining('₹1500 collected, ₹200 refunded'), findsOneWidget);
      // The management cards are gone: the sidebar is the navigation.
      expect(find.text('Manage'), findsNothing);
    });

    testWidgets('lists the status breakdown and the recent bookings',
        (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(
        role: UserRole.admin,
        adminBookings: FakeAdminBookingRepository(bookings: [
          booking(id: 'a', number: 1, status: BookingStatus.completed),
          booking(id: 'b', number: 2, status: BookingStatus.cancelled),
        ]),
      );
      await harness.pump(tester);

      expect(find.byKey(const ValueKey('status-row-completed')), findsOneWidget);
      expect(find.byKey(const ValueKey('status-row-cancelled')), findsOneWidget);
      expect(find.byKey(const ValueKey('recent-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('recent-b')), findsOneWidget);
      // At most the newest few are fetched for this panel.
      expect(harness.adminBookings.lists.last.offset, 0);
    });

    testWidgets('an empty garage shows empty states, not fake numbers',
        (tester) async {
      useTallScreen(tester);
      await AppHarness(role: UserRole.admin).pump(tester);
      expect(_card('stat-total', '0'), findsOneWidget);
      expect(_card('stat-revenue', '₹0'), findsOneWidget);
      expect(find.byKey(const ValueKey('breakdown-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('recent-empty')), findsOneWidget);
    });

    testWidgets('a failing dashboard shows Retry and recovers', (tester) async {
      useTallScreen(tester);
      final bookings = FakeAdminBookingRepository();
      final drivers = FakeAdminDriverRepository();
      final dashboard = FakeDashboardRepository(bookings, drivers)
        ..error = networkError;
      final harness = AppHarness(
        role: UserRole.admin,
        adminBookings: bookings,
        adminDrivers: drivers,
        dashboard: dashboard,
      );
      await harness.pump(tester);
      expect(find.text('Unable to reach the server.'), findsWidgets);
      expect(find.byKey(const ValueKey('stat-total')), findsNothing);

      dashboard.error = null;
      await tapText(tester, 'Retry');
      expect(_card('stat-total', '0'), findsOneWidget);
    });

    testWidgets('a failing recent list does not hide the figures',
        (tester) async {
      useTallScreen(tester);
      final bookings = FakeAdminBookingRepository()..error = networkError;
      final harness = AppHarness(role: UserRole.admin, adminBookings: bookings);
      await harness.pump(tester);
      expect(find.byKey(const ValueKey('quick-service')), findsOneWidget);
      expect(find.text('Unable to reach the server.'), findsWidgets);
    });

    testWidgets('quick actions open the existing screens', (tester) async {
      useTallScreen(tester);
      await AppHarness(role: UserRole.admin).pump(tester);
      await tapKey(tester, 'quick-driver');
      expect(find.text('Add driver'), findsWidgets);
    });

    testWidgets('a stat card opens its list', (tester) async {
      useTallScreen(tester);
      await AppHarness(role: UserRole.admin).pump(tester);
      await tapKey(tester, 'stat-drivers');
      expect(find.text('Add driver'), findsOneWidget);
    });
  });
}
