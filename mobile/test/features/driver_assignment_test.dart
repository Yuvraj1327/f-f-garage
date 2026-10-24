import 'package:ff_garage/app/router/app_routes.dart';
import 'package:ff_garage/data/models/booking.dart';
import 'package:ff_garage/data/models/driver.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_driver.dart';
import '../support/pump_app.dart';

void main() {
  group('driver dashboard', () {
    testWidgets('lists open jobs with service, customer, address and slot',
        (tester) async {
      final harness = AppHarness(
        role: UserRole.driver,
        driverWork: FakeDriverWorkRepository(jobs: [driverJob()]),
      );
      await harness.pump(tester);

      expect(find.byKey(const ValueKey('job-b1')), findsOneWidget);
      expect(find.textContaining('General Service'), findsOneWidget);
      expect(find.textContaining('Test User'), findsOneWidget);
      expect(find.textContaining('12 MG Road'), findsOneWidget);
      expect(find.textContaining('9:00'), findsWidgets);
    });

    testWidgets('shows an empty message for each tab', (tester) async {
      final harness = AppHarness(role: UserRole.driver);
      await harness.pump(tester);

      expect(find.textContaining('No jobs assigned to you right now.'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tab-history')));
      await tester.pumpAndSettle();
      expect(find.text('No finished jobs yet.'), findsOneWidget);
      expect(harness.driverWork.scopes, containsAll(['open', 'history']));
    });

    testWidgets('history shows finished jobs only', (tester) async {
      final harness = AppHarness(
        role: UserRole.driver,
        driverWork: FakeDriverWorkRepository(jobs: [
          driverJob(id: 'open1'),
          driverJob(
            id: 'done1',
            number: 2,
            status: BookingStatus.completed,
            next: null,
          ),
        ]),
      );
      await harness.pump(tester);
      expect(find.byKey(const ValueKey('job-open1')), findsOneWidget);
      expect(find.byKey(const ValueKey('job-done1')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('tab-history')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('job-done1')), findsOneWidget);
    });

    testWidgets('a failed load shows the error and Retry works',
        (tester) async {
      final repo = FakeDriverWorkRepository(jobs: [driverJob()])
        ..error = notFoundError;
      final harness = AppHarness(role: UserRole.driver, driverWork: repo);
      await harness.pump(tester);

      expect(find.text('Retry'), findsOneWidget);
      repo.error = null;
      await tapText(tester, 'Retry');
      expect(find.byKey(const ValueKey('job-b1')), findsOneWidget);
    });
  });

  group('driver job', () {
    testWidgets('walks the steps with a confirmation each time',
        (tester) async {
      final repo = FakeDriverWorkRepository(jobs: [driverJob()]);
      final harness = AppHarness(role: UserRole.driver, driverWork: repo);
      await harness.pump(tester);

      await tester.tap(find.byKey(const ValueKey('job-b1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('next-step')), findsOneWidget);
      expect(find.text("I'm on my way"), findsOneWidget);

      // Cancelling the question records nothing.
      await tester.tap(find.byKey(const ValueKey('next-step')));
      await tester.pumpAndSettle();
      await tapText(tester, 'Cancel');
      expect(repo.updates, isEmpty);

      await tester.tap(find.byKey(const ValueKey('next-step')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text("I'm on my way"),
      ));
      await tester.pumpAndSettle();
      expect(repo.updates.single.status, BookingStatus.onTheWay);
      expect(find.text('Marked as on the way'), findsOneWidget);
      expect(find.text('Start service'), findsOneWidget);
    });

    testWidgets('a finished job has no step button', (tester) async {
      final harness = AppHarness(
        role: UserRole.driver,
        driverWork: FakeDriverWorkRepository(jobs: [
          driverJob(status: BookingStatus.completed, next: null),
        ]),
      );
      await harness.pump(tester);
      goTo(tester, AppRoutes.driverBooking('b1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('next-step')), findsNothing);
    });

    testWidgets('a booking that is not theirs shows an error', (tester) async {
      final harness = AppHarness(role: UserRole.driver);
      await harness.pump(tester);
      goTo(tester, AppRoutes.driverBooking('other'));
      await tester.pumpAndSettle();
      expect(find.text('Booking not found'), findsOneWidget);
    });

    testWidgets('a refused step shows the error', (tester) async {
      final repo = FakeDriverWorkRepository(jobs: [driverJob()])
        ..updateError = conflictError;
      final harness = AppHarness(role: UserRole.driver, driverWork: repo);
      await harness.pump(tester);
      goTo(tester, AppRoutes.driverBooking('b1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('next-step')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text("I'm on my way"),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('already has a visit'), findsOneWidget);
    });
  });

  group('admin drivers', () {
    testWidgets('lists drivers with open booking counts', (tester) async {
      final harness = AppHarness(
        role: UserRole.admin,
        adminDrivers: FakeAdminDriverRepository(drivers: [
          driverAccount(open: 2),
          driverAccount(id: 'd2', loginId: 'sam02', name: 'Sam', active: false),
        ]),
      );
      await harness.pump(tester);
      goTo(tester, AppRoutes.adminDrivers);
      await tester.pumpAndSettle();

      expect(find.textContaining('2 open bookings'), findsOneWidget);
      expect(find.textContaining('No open bookings'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
    });

    testWidgets('shows an empty state', (tester) async {
      final harness = AppHarness(role: UserRole.admin);
      await harness.pump(tester);
      goTo(tester, AppRoutes.adminDrivers);
      await tester.pumpAndSettle();
      expect(find.textContaining('No drivers yet.'), findsOneWidget);
    });

    testWidgets('creates a driver', (tester) async {
      final harness = AppHarness(role: UserRole.admin);
      await harness.pump(tester);
      goTo(tester, AppRoutes.adminDrivers);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('add-driver')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('driver-id')), 'Ravi01');
      await tester.enterText(
          find.byKey(const ValueKey('driver-name')), 'Ravi Kumar');
      await tester.enterText(
          find.byKey(const ValueKey('driver-password')), 'strong-pass-9');
      await tester.enterText(
          find.byKey(const ValueKey('driver-confirm')), 'strong-pass-9');
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();

      expect(harness.adminDrivers.created.single['driver_id'], 'ravi01');
      expect(find.text('Ravi Kumar'), findsOneWidget);
    });

    testWidgets('a driver ID that is already taken shows the error',
        (tester) async {
      final repo = FakeAdminDriverRepository()..createError = conflictError;
      final harness = AppHarness(role: UserRole.admin, adminDrivers: repo);
      await harness.pump(tester);
      goTo(tester, AppRoutes.adminDriverNew);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('driver-id')), 'ravi01');
      await tester.enterText(
          find.byKey(const ValueKey('driver-name')), 'Ravi Kumar');
      await tester.enterText(
          find.byKey(const ValueKey('driver-password')), 'strong-pass-9');
      await tester.enterText(
          find.byKey(const ValueKey('driver-confirm')), 'strong-pass-9');
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      expect(find.textContaining('already has a visit'), findsOneWidget);
    });

    testWidgets('switches a driver off after a warning', (tester) async {
      final repo = FakeAdminDriverRepository(drivers: [driverAccount(open: 1)]);
      final harness = AppHarness(role: UserRole.admin, adminDrivers: repo);
      await harness.pump(tester);
      goTo(tester, AppRoutes.adminDriver('d1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('driver-active')));
      await tester.pumpAndSettle();
      expect(find.textContaining('still has 1 open booking'), findsOneWidget);
      await tapText(tester, 'Switch off');
      expect(repo.updates.single.changes, {'is_active': false});
    });

    testWidgets('resets the password', (tester) async {
      final repo = FakeAdminDriverRepository(drivers: [driverAccount()]);
      final harness = AppHarness(role: UserRole.admin, adminDrivers: repo);
      await harness.pump(tester);
      goTo(tester, AppRoutes.adminDriver('d1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('reset-password')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('new-password')), 'another-pass-7');
      await tester.tap(find.byKey(const ValueKey('save-password')));
      await tester.pumpAndSettle();
      expect(repo.resets.single.password, 'another-pass-7');
    });
  });

  group('admin bookings and assignment', () {
    final ravi = driverAccount(open: 1);
    final sam = driverAccount(id: 'd2', loginId: 'sam02', name: 'Sam');

    AppHarness harnessWith(List<Booking> bookings) => AppHarness(
          role: UserRole.admin,
          adminDrivers: FakeAdminDriverRepository(drivers: [ravi, sam]),
          adminBookings: FakeAdminBookingRepository(
            bookings: List.of(bookings),
            drivers: [ravi, sam],
          ),
        );

    testWidgets('opens on the bookings that need a driver', (tester) async {
      final harness = harnessWith([
        booking(
            id: 'paid',
            number: 1,
            status: BookingStatus.confirmed,
            isPaid: true,
            canAssign: true),
        booking(id: 'unpaid', number: 2),
      ]);
      await harness.pump(tester);
      goTo(tester, AppRoutes.adminBookings);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('booking-paid')), findsOneWidget);
      expect(find.byKey(const ValueKey('booking-unpaid')), findsNothing);
      expect(find.text('No driver assigned'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('filter-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('booking-unpaid')), findsOneWidget);
    });

    testWidgets('empty and failed lists', (tester) async {
      final harness = harnessWith([]);
      await harness.pump(tester);
      goTo(tester, AppRoutes.adminBookings);
      await tester.pumpAndSettle();
      expect(find.text('No paid bookings are waiting for a driver.'),
          findsOneWidget);

      harness.adminBookings.error = notFoundError;
      await tester.tap(find.byKey(const ValueKey('filter-all')));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('assigns a driver and shows them', (tester) async {
      final harness = harnessWith([
        booking(
            id: 'b1',
            status: BookingStatus.confirmed,
            isPaid: true,
            canAssign: true),
      ]);
      await harness.pump(tester);
      goTo(tester, AppRoutes.adminBooking('b1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('no-driver')), findsOneWidget);
      expect(find.byKey(const ValueKey('unassign-driver')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('assign-driver')));
      await tester.pumpAndSettle();
      expect(find.text('Sam'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pick-d2')));
      await tester.pumpAndSettle();

      expect(harness.adminBookings.assigns.single.driverId, 'd2');
      expect(find.text('Sam assigned'), findsOneWidget);
      expect(find.byKey(const ValueKey('no-driver')), findsNothing);
      expect(find.text('Change driver'), findsOneWidget);
      expect(find.byKey(const ValueKey('unassign-driver')), findsOneWidget);
    });

    testWidgets('a refused assignment shows the reason', (tester) async {
      final harness = harnessWith([
        booking(
            id: 'b1',
            status: BookingStatus.confirmed,
            isPaid: true,
            canAssign: true),
      ]);
      harness.adminBookings.assignError = conflictError;
      await harness.pump(tester);
      goTo(tester, AppRoutes.adminBooking('b1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('assign-driver')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pick-d1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('already has a visit'), findsOneWidget);
    });

    testWidgets('reassigns and removes a driver', (tester) async {
      final harness = harnessWith([
        booking(
          id: 'b1',
          status: BookingStatus.assigned,
          isPaid: true,
          canAssign: true,
          canUnassign: true,
          assignment: assignmentFor(ravi),
        ),
      ]);
      await harness.pump(tester);
      goTo(tester, AppRoutes.adminBooking('b1'));
      await tester.pumpAndSettle();

      expect(find.text('Ravi Kumar'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('assign-driver')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pick-d2')));
      await tester.pumpAndSettle();
      expect(find.text('Driver changed to Sam'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('unassign-driver')));
      await tester.pumpAndSettle();
      await tapText(tester, 'Remove');
      expect(harness.adminBookings.unassigns, ['b1']);
      expect(find.byKey(const ValueKey('no-driver')), findsOneWidget);
    });

    testWidgets('no assign buttons while payment is pending', (tester) async {
      final harness = harnessWith([booking(id: 'b1')]);
      await harness.pump(tester);
      goTo(tester, AppRoutes.adminBooking('b1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('assign-driver')), findsNothing);
      expect(find.byKey(const ValueKey('needs-payment')), findsOneWidget);
    });

    testWidgets('warns when the assigned driver is switched off',
        (tester) async {
      final off = driverAccount(id: 'd9', active: false);
      final harness = harnessWith([
        booking(
          id: 'b1',
          status: BookingStatus.assigned,
          isPaid: true,
          canAssign: true,
          canUnassign: true,
          assignment: assignmentFor(off),
        ),
      ]);
      await harness.pump(tester);
      goTo(tester, AppRoutes.adminBooking('b1'));
      await tester.pumpAndSettle();
      expect(find.textContaining('switched off'), findsOneWidget);
    });
  });

  group('customer', () {
    testWidgets('sees the assigned driver, not when none or cancelled',
        (tester) async {
      final harness = AppHarness(
        role: UserRole.customer,
        bookingRepo: FakeBookingRepository(bookings: [
          booking(
            id: 'b1',
            status: BookingStatus.assigned,
            driver: const DriverSummary(name: 'Ravi Kumar', phone: '+919876500001'),
          ),
          booking(id: 'b2', number: 2, status: BookingStatus.confirmed),
          booking(
            id: 'b3',
            number: 3,
            status: BookingStatus.cancelled,
            driver: const DriverSummary(name: 'Ravi Kumar'),
          ),
        ]),
      );
      await harness.pump(tester);

      goTo(tester, AppRoutes.booking('b1'));
      await tester.pumpAndSettle();
      expect(find.text('Your driver'), findsOneWidget);
      expect(find.byKey(const ValueKey('driver-name')), findsOneWidget);
      expect(find.text('+919876500001'), findsOneWidget);

      goTo(tester, AppRoutes.booking('b2'));
      await tester.pumpAndSettle();
      expect(find.text('Your driver'), findsNothing);

      goTo(tester, AppRoutes.booking('b3'));
      await tester.pumpAndSettle();
      expect(find.text('Your driver'), findsNothing);
    });
  });
}
