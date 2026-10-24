import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/models/booking.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/models/json_reader.dart' show formatApiDate;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/booking_journey.dart';
import '../support/fakes.dart';
import '../support/fakes_booking.dart';
import '../support/pump_app.dart';

const _tooLate = ApiException(
  type: ApiErrorType.conflict,
  message: 'Too close to the visit to cancel.',
  statusCode: 409,
);

void main() {
  group('history', () {
    testWidgets('is reached from home and says when there is nothing yet',
        (tester) async {
      final harness = customerHarness();
      await harness.pump(tester);
      await tapText(tester, 'My bookings');

      expect(find.text('You have no bookings yet.'), findsOneWidget);
      expect(find.text('Browse services'), findsOneWidget);
      expect(harness.bookingRepo.lists, hasLength(1));
    });

    testWidgets('lists bookings with code, service, time, status and total',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness(
        bookings: FakeBookingRepository(bookings: [
          booking(id: 'b2', number: 2, service: 'Wash', price: 299),
          booking(id: 'b1', number: 1, status: BookingStatus.confirmed),
        ]),
      );
      await harness.pump(tester);
      goTo(tester, '/home/bookings');
      await tester.pumpAndSettle();

      expect(find.text('FF-000002 - Wash'), findsOneWidget);
      expect(find.text('FF-000001 - General Service'), findsOneWidget);
      expect(find.text('Awaiting payment'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('₹299'), findsOneWidget);
      expect(find.textContaining('9:00 AM - 11:00 AM'), findsNWidgets(2));
    });

    testWidgets('opens a booking when tapped', (tester) async {
      useTallScreen(tester);
      final harness = customerHarness(
        bookings: FakeBookingRepository(bookings: [booking()]),
      );
      await harness.pump(tester);
      goTo(tester, '/home/bookings');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('booking-b1')));
      await tester.pumpAndSettle();

      expect(find.text('Cancel booking'), findsOneWidget);
      expect(find.text('Contact'), findsOneWidget);
    });

    testWidgets('filters by status and explains an empty filter',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness(
        bookings: FakeBookingRepository(bookings: [
          booking(id: 'b1', number: 1),
          booking(id: 'b2', number: 2, status: BookingStatus.completed),
        ]),
      );
      await harness.pump(tester);
      goTo(tester, '/home/bookings');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Completed'));
      await tester.pumpAndSettle();
      expect(harness.bookingRepo.lists.last.statuses, [BookingStatus.completed]);
      expect(find.text('FF-000002 - General Service'), findsOneWidget);
      expect(find.text('FF-000001 - General Service'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Cancelled'));
      await tester.pumpAndSettle();
      expect(harness.bookingRepo.lists.last.statuses, [BookingStatus.cancelled]);
      expect(find.text('No cancelled bookings.'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      expect(harness.bookingRepo.lists.last.statuses, isNull);
      expect(find.text('FF-000001 - General Service'), findsOneWidget);
    });

    testWidgets('loads more pages on request', (tester) async {
      useTallScreen(tester, height: 8000);
      final harness = customerHarness(
        bookings: FakeBookingRepository(bookings: [
          for (var i = 25; i >= 1; i--) booking(id: 'b$i', number: i),
        ]),
      );
      await harness.pump(tester);
      goTo(tester, '/home/bookings');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('booking-b25')), findsOneWidget);
      expect(find.byKey(const ValueKey('booking-b1')), findsNothing);
      expect(find.text('Load more'), findsOneWidget);

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(harness.bookingRepo.lists.last.offset, 20);
      expect(find.byKey(const ValueKey('booking-b1')), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('shows a failure and recovers on Retry', (tester) async {
      final harness = customerHarness(
        bookings: FakeBookingRepository(bookings: [booking()]),
      );
      harness.bookingRepo.error = networkError;
      await harness.pump(tester);
      goTo(tester, '/home/bookings');
      await tester.pumpAndSettle();

      expect(find.text('Unable to reach the server.'), findsOneWidget);
      expect(find.text('FF-000001 - General Service'), findsNothing);

      harness.bookingRepo.error = null;
      await tapText(tester, 'Retry');
      expect(find.text('FF-000001 - General Service'), findsOneWidget);
    });
  });

  group('details', () {
    testWidgets('shows service, visit, contact and price', (tester) async {
      useTallScreen(tester);
      final harness = customerHarness(
        bookings: FakeBookingRepository(bookings: [
          booking(
            landmark: 'Near the temple',
            notes: 'Gate 4',
            extras: 350,
            charges: const [
              BookingCharge(
                id: 'x1',
                chargeType: ExtraChargeType.engineOil,
                name: 'Engine oil 10W-30',
                amount: 350,
                includedInTotal: true,
              ),
              BookingCharge(
                id: 'x2',
                chargeType: ExtraChargeType.sparePart,
                name: 'Air filter',
                includedInTotal: false,
              ),
            ],
          ),
        ]),
      );
      await harness.pump(tester);
      goTo(tester, '/home/bookings/b1');
      await tester.pumpAndSettle();

      expect(find.text('FF-000001'), findsOneWidget);
      expect(find.text('Awaiting payment'), findsOneWidget);
      expect(find.text('General Service - Basic'), findsOneWidget);
      expect(find.text('Wash'), findsOneWidget);
      expect(find.text('12 MG Road, Near the temple, Bengaluru 560001'), findsOneWidget);
      expect(find.text('Notes: Gate 4'), findsOneWidget);
      expect(find.text('Test User'), findsOneWidget);
      expect(find.text('₹499'), findsOneWidget);
      expect(find.text('₹350'), findsOneWidget);
      expect(find.text('₹849'), findsOneWidget);
      expect(find.text('May apply on the day (not in the total)'), findsOneWidget);
      expect(find.text('Air filter'), findsOneWidget);
      expect(find.text('At actuals'), findsOneWidget);
      expect(find.textContaining('has been placed'), findsNothing);
    });

    testWidgets('shows the confirmation banner right after booking',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness(
        bookings: FakeBookingRepository(bookings: [booking()]),
      );
      await harness.pump(tester);
      goTo(tester, '/home/bookings/b1?created=1');
      await tester.pumpAndSettle();

      expect(
        find.text('Your booking FF-000001 has been placed. '
            'Its status is "Awaiting payment".'),
        findsOneWidget,
      );
    });

    testWidgets('a booking that does not exist says so', (tester) async {
      final harness = customerHarness();
      await harness.pump(tester);
      goTo(tester, '/home/bookings/nope');
      await tester.pumpAndSettle();

      expect(find.text('Booking not found'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a cancelled booking shows its reason and no actions',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness(
        bookings: FakeBookingRepository(bookings: [
          booking(
            status: BookingStatus.cancelled,
            canCancel: false,
            canModify: false,
            cancellationReason: 'Changed my mind',
          ),
        ]),
      );
      await harness.pump(tester);
      goTo(tester, '/home/bookings/b1');
      await tester.pumpAndSettle();

      expect(find.text('Changed my mind'), findsOneWidget);
      expect(find.text('Cancel booking'), findsNothing);
      expect(find.text('Change address or time'), findsNothing);
    });

    testWidgets('explains why a booking can no longer be cancelled',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness(
        bookings: FakeBookingRepository(bookings: [
          booking(
            status: BookingStatus.confirmed,
            canCancel: false,
            canModify: false,
            cancelBlockedReason: 'Cancellations close 4 hours before the visit.',
          ),
        ]),
      );
      await harness.pump(tester);
      goTo(tester, '/home/bookings/b1');
      await tester.pumpAndSettle();

      expect(
        find.text('Cancellations close 4 hours before the visit.'),
        findsOneWidget,
      );
      expect(find.text('Cancel booking'), findsNothing);
      expect(find.text('Change address or time'), findsNothing);
    });
  });

  group('cancelling', () {
    Future<void> openDetail(WidgetTester tester, FakeBookingRepository repo) async {
      final harness = customerHarness(bookings: repo);
      await harness.pump(tester);
      goTo(tester, '/home/bookings/b1');
      await tester.pumpAndSettle();
    }

    testWidgets('Keep booking closes the dialog and cancels nothing',
        (tester) async {
      useTallScreen(tester);
      final repo = FakeBookingRepository(bookings: [booking()]);
      await openDetail(tester, repo);

      await tapText(tester, 'Cancel booking');
      expect(find.text('Cancel this booking?'), findsOneWidget);
      await tapText(tester, 'Keep booking');

      expect(find.text('Cancel this booking?'), findsNothing);
      expect(repo.cancelled, isEmpty);
      expect(find.text('Awaiting payment'), findsOneWidget);
    });

    testWidgets('confirming sends the reason and shows the new status',
        (tester) async {
      useTallScreen(tester);
      final repo = FakeBookingRepository(bookings: [booking()]);
      await openDetail(tester, repo);

      await tapText(tester, 'Cancel booking');
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Changed my mind',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel booking'));
      await tester.pumpAndSettle();

      expect(repo.cancelled, ['b1']);
      expect(repo.lastCancelReason, 'Changed my mind');
      expect(find.text('Booking cancelled'), findsOneWidget);
      expect(find.text('Cancelled'), findsWidgets);
      expect(find.text('Cancel booking'), findsNothing);
    });

    testWidgets('a refusal from the server is shown and nothing changes',
        (tester) async {
      useTallScreen(tester);
      final repo = FakeBookingRepository(bookings: [booking()])
        ..cancelError = _tooLate;
      await openDetail(tester, repo);

      await tapText(tester, 'Cancel booking');
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel booking'));
      await tester.pumpAndSettle();

      expect(find.text('Too close to the visit to cancel.'), findsOneWidget);
      expect(find.text('Awaiting payment'), findsOneWidget);
      expect(find.text('Cancel booking'), findsOneWidget);
    });
  });

  group('changing a booking', () {
    // Dated long ago so any day picked in the picker counts as a change.
    FakeBookingRepository repo({String? landmark, String? notes}) =>
        FakeBookingRepository(bookings: [
          booking(
            date: DateTime(2020, 1, 1),
            landmark: landmark,
            notes: notes,
          ),
        ]);

    Future<void> openEdit(WidgetTester tester, FakeBookingRepository r) async {
      final harness = customerHarness(bookings: r);
      await harness.pump(tester);
      goTo(tester, '/home/bookings/b1');
      await tester.pumpAndSettle();
      await tapText(tester, 'Change address or time');
    }

    testWidgets('starts with the current details', (tester) async {
      useTallScreen(tester);
      await openEdit(tester, repo(landmark: 'Near the temple'));

      expect(find.text('Change booking'), findsOneWidget);
      expect(find.text('12 MG Road'), findsOneWidget);
      expect(find.text('Near the temple'), findsOneWidget);
      expect(find.text('560001'), findsOneWidget);
      expect(find.textContaining('The service and price cannot be changed'), findsOneWidget);
    });

    testWidgets('saving without changes sends nothing', (tester) async {
      useTallScreen(tester);
      final r = repo();
      await openEdit(tester, r);
      await tapButton(tester, 'Save');

      expect(find.text('No changes to save'), findsOneWidget);
      expect(r.lastUpdate, isNull);
      expect(find.text('Change booking'), findsOneWidget);
    });

    testWidgets('sends only the field that changed, then goes back',
        (tester) async {
      useTallScreen(tester);
      final r = repo();
      await openEdit(tester, r);
      await enter(tester, 'House / flat, street and area', '14  New Road');
      await tapButton(tester, 'Save');

      expect(r.lastUpdate, {'address_line': '14 New Road'});
      expect(find.text('Booking updated'), findsOneWidget);
      expect(find.text('Change booking'), findsNothing);
      expect(find.text('14 New Road, Bengaluru 560001'), findsOneWidget);
    });

    testWidgets('an emptied landmark is sent as null', (tester) async {
      useTallScreen(tester);
      final r = repo(landmark: 'Near the temple', notes: 'Gate 4');
      await openEdit(tester, r);
      await enter(tester, 'Landmark (optional)', '');
      await enter(tester, 'Notes for the driver (optional)', '');
      await tapButton(tester, 'Save');

      expect(r.lastUpdate, {'landmark': null, 'customer_notes': null});
    });

    testWidgets('a new date and time are sent together', (tester) async {
      useTallScreen(tester);
      final r = repo();
      await openEdit(tester, r);

      await tapText(tester, 'Change date or time');
      await tapKey(tester, dayKey(tomorrow()));
      await tapKey(tester, 'slot-slot2');
      expect(find.textContaining('12:00 PM - 2:00 PM (new)'), findsOneWidget);
      await tapButton(tester, 'Save');

      expect(r.lastUpdate, {
        'scheduled_date': formatApiDate(tomorrow()),
        'time_slot_id': 'slot2',
      });
    });

    testWidgets('a server error is shown on the form', (tester) async {
      useTallScreen(tester);
      final r = repo()
        ..updateError = const ApiException(
          type: ApiErrorType.validation,
          message: 'We do not service that PIN code.',
          statusCode: 422,
        );
      await openEdit(tester, r);
      await enter(tester, 'PIN code', '999999');
      await tapButton(tester, 'Save');

      expect(find.text('We do not service that PIN code.'), findsOneWidget);
      expect(find.text('Change booking'), findsOneWidget);
      expect(r.lastUpdate, {'pincode': '999999'});
    });

    testWidgets('a booking that can no longer be changed has no edit button',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness(
        bookings: FakeBookingRepository(
          bookings: [booking(canModify: false)],
        ),
      );
      await harness.pump(tester);
      goTo(tester, '/home/bookings/b1');
      await tester.pumpAndSettle();
      expect(find.text('Change address or time'), findsNothing);
    });
  });
}
