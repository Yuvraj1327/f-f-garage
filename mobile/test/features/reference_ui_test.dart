import 'package:ff_garage/app/router/app_routes.dart';
import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/core/widgets/filter_pill.dart';
import 'package:ff_garage/core/widgets/stat_tile.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_catalog.dart';
import '../support/fakes_driver.dart';
import '../support/pump_app.dart';

Finder _navLabel(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

Finder _stat(String label, String value) => find.descendant(
      of: find.widgetWithText(StatTile, label),
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
    testWidgets('shows booking and driver counts from the server',
        (tester) async {
      final ravi = driverAccount();
      final sam = driverAccount(id: 'd2', loginId: 'sam02', name: 'Sam', active: false);
      final harness = AppHarness(
        role: UserRole.admin,
        adminDrivers: FakeAdminDriverRepository(drivers: [ravi, sam]),
        adminBookings: FakeAdminBookingRepository(
          drivers: [ravi, sam],
          bookings: [
            booking(id: 'a', number: 1, status: BookingStatus.completed),
            booking(id: 'b', number: 2, status: BookingStatus.cancelled),
            booking(id: 'c', number: 3, status: BookingStatus.confirmed),
            booking(id: 'd', number: 4),
          ],
        ),
      );
      await harness.pump(tester);

      expect(_stat('Total Bookings', '4'), findsOneWidget);
      expect(_stat('Completed', '1'), findsOneWidget);
      expect(_stat('Pending', '2'), findsOneWidget);
      expect(_stat('Cancelled', '1'), findsOneWidget);
      expect(_stat('Active Drivers', '1'), findsOneWidget);
    });

    testWidgets('bookings, services and drivers screens open from the manage list',
        (tester) async {
      final harness = AppHarness(role: UserRole.admin);
      await harness.pump(tester);

      await tapText(tester, 'Drivers');
      expect(find.text('Add driver'), findsOneWidget);
    });
  });
}
