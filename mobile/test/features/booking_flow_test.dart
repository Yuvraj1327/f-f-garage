import 'package:ff_garage/app/app.dart';
import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/features/booking/providers/booking_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/booking_journey.dart';
import '../support/fakes.dart';
import '../support/pump_app.dart';

void main() {
  group('starting a booking', () {
    testWidgets('a package has a Book button that opens the address step',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      await harness.pump(tester);
      await startBooking(tester);

      expect(find.text('Where should we come?'), findsOneWidget);
      expect(find.textContaining('General Service - Basic'), findsOneWidget);
    });

    testWidgets('home links to My bookings', (tester) async {
      final harness = customerHarness();
      await harness.pump(tester);
      expect(find.text('My Bookings'), findsOneWidget);
    });

    testWidgets('booking screens opened without a package say so',
        (tester) async {
      final harness = customerHarness();
      await harness.pump(tester);
      for (final route in [
        '/home/book-address',
        '/home/book-schedule',
        '/home/book-summary',
      ]) {
        goTo(tester, route);
        await tester.pumpAndSettle();
        expect(
          find.text('Choose a service and package to book first.'),
          findsOneWidget,
          reason: route,
        );
      }
      expect(harness.bookingRepo.quoteCalls, 0);
    });
  });

  group('address step', () {
    testWidgets('rejects empty and malformed input before any request',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      await harness.pump(tester);
      await startBooking(tester);

      await tapButton(tester, 'Continue');
      expect(find.text('Where should we come?'), findsOneWidget);
      expect(find.text('Enter the PIN code'), findsOneWidget);
      expect(find.text('Enter the address'), findsOneWidget);

      await fillAddress(tester, pincode: '12ab', address: 'abc');
      await tapButton(tester, 'Continue');
      expect(find.text('Enter a valid 6-digit PIN code'), findsOneWidget);
      expect(find.text('The address must be 5 to 250 characters'), findsOneWidget);
      expect(harness.areas.calls, isEmpty);
    });

    testWidgets('does not continue for a PIN code we do not service',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      await harness.pump(tester);
      await startBooking(tester);

      await fillAddress(tester, pincode: '999999');
      await tapButton(tester, 'Continue');

      expect(find.text('Sorry, we do not service 999999 yet.'), findsOneWidget);
      expect(find.text('When should we come?'), findsNothing);
    });

    testWidgets('shows the error when the PIN check fails', (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      harness.areas.error = networkError;
      await harness.pump(tester);
      await startBooking(tester);

      await fillAddress(tester);
      await tapButton(tester, 'Continue');
      expect(find.text('Unable to reach the server.'), findsOneWidget);
      expect(find.text('When should we come?'), findsNothing);
      expect(buttonEnabled(tester, 'Continue'), isTrue);
    });

    testWidgets('a serviceable address moves on to the schedule',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      await harness.pump(tester);
      await toSchedule(tester);

      expect(harness.areas.calls, contains('check:560001'));
      expect(find.text('When should we come?'), findsOneWidget);
    });
  });

  group('schedule step', () {
    testWidgets('asks for a date, then lists that day\'s slots',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      await harness.pump(tester);
      await toSchedule(tester);

      expect(find.text('Pick a date to see the available times.'), findsOneWidget);
      expect(buttonEnabled(tester, 'Continue'), isFalse);

      await tapKey(tester, dayKey(tomorrow()));
      expect(find.text('9:00 AM - 11:00 AM'), findsOneWidget);
      expect(find.text('2 spots left'), findsOneWidget);
      expect(find.text('1 spot left'), findsOneWidget);
    });

    testWidgets('a full slot is shown with its reason and cannot be chosen',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      await harness.pump(tester);
      await toSchedule(tester);
      await tapKey(tester, dayKey(tomorrow()));

      expect(find.text('Fully booked'), findsOneWidget);
      final tile = tester.widget<ListTile>(
        find.descendant(
          of: find.byKey(const ValueKey('slot-slot3')),
          matching: find.byType(ListTile),
        ),
      );
      expect(tile.enabled, isFalse);
      await tester.tap(find.byKey(const ValueKey('slot-slot3')));
      await tester.pumpAndSettle();
      expect(buttonEnabled(tester, 'Continue'), isFalse);
    });

    testWidgets('a closed day cannot be chosen', (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      await harness.pump(tester);
      await toSchedule(tester);

      final chip = tester.widget<ChoiceChip>(
        find.byKey(ValueKey(dayKey(dayAfterTomorrow()))),
      );
      expect(chip.onSelected, isNull);
      expect(find.text('Pick a date to see the available times.'), findsOneWidget);
    });

    testWidgets('a past-cutoff slot says it is too late', (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      await harness.pump(tester);
      await toSchedule(tester);
      await tapKey(tester, dayKey(today()));
      expect(find.text('Too late to book'), findsOneWidget);
    });

    testWidgets('choosing a slot enables Continue', (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      await harness.pump(tester);
      await toSchedule(tester);
      await tapKey(tester, dayKey(tomorrow()));
      await tapKey(tester, 'slot-slot2');

      expect(buttonEnabled(tester, 'Continue'), isTrue);
      await tapButton(tester, 'Continue');
      expect(find.text('Review your booking'), findsOneWidget);
      expect(find.text('12:00 PM - 2:00 PM'), findsOneWidget);
    });

    testWidgets('says so when no date is open', (tester) async {
      useTallScreen(tester);
      final harness = customerHarness(days: [
        openDays().last,
      ]);
      await harness.pump(tester);
      await toSchedule(tester);
      expect(
        find.textContaining('No dates are open for booking right now'),
        findsOneWidget,
      );
    });

    testWidgets('a failed availability load can be retried', (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      harness.availability.error = networkError;
      await harness.pump(tester);
      await toSchedule(tester);

      expect(find.text('Unable to reach the server.'), findsOneWidget);
      harness.availability.error = null;
      await tapText(tester, 'Retry');
      expect(find.text('Choose a date'), findsOneWidget);
    });
  });

  group('summary step', () {
    testWidgets('shows the service, visit, inclusions and server price',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      await harness.pump(tester);
      await toSummary(tester, landmark: 'Near the temple');

      expect(find.text('Review your booking'), findsOneWidget);
      expect(find.text('General Service - Basic'), findsOneWidget);
      expect(find.text('Wash'), findsOneWidget);
      expect(find.text('Oil top-up'), findsOneWidget);
      expect(find.text('9:00 AM - 11:00 AM'), findsOneWidget);
      expect(find.text('12 MG Road, Flat 4'), findsOneWidget);
      expect(find.text('Near the temple'), findsOneWidget);
      expect(find.text('MG Road, Bengaluru 560001'), findsOneWidget);
      expect(find.text('Confirm booking - ₹499'), findsOneWidget);
      expect(harness.bookingRepo.quoteCalls, 1);
    });

    testWidgets('lists fixed add-ons to tick and at-actuals charges apart',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      await harness.pump(tester);
      await toSummary(tester);

      expect(find.text('Engine oil 10W-30'), findsOneWidget);
      expect(find.byKey(const ValueKey('addon-c1')), findsOneWidget);
      expect(find.byKey(const ValueKey('addon-c2')), findsNothing);
      expect(find.text('May apply on the day'), findsOneWidget);
      expect(find.text('Air filter (Spare part)'), findsOneWidget);
      expect(find.text('At actuals'), findsOneWidget);
      expect(find.textContaining('Not included in the total'), findsOneWidget);
    });

    testWidgets('ticking an add-on updates the total and the button',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      await harness.pump(tester);
      await toSummary(tester);

      await tapKey(tester, 'addon-c1');
      expect(find.text('Confirm booking - ₹849'), findsOneWidget);
      expect(find.text('₹849'), findsOneWidget);

      await tapKey(tester, 'addon-c1');
      expect(find.text('Confirm booking - ₹499'), findsOneWidget);
    });

    testWidgets('a failed price load shows an error and can be retried',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      harness.bookingRepo.quoteError = networkError;
      await harness.pump(tester);
      await toSummary(tester);

      expect(find.text('Unable to reach the server.'), findsOneWidget);
      expect(find.textContaining('Confirm booking'), findsNothing);

      harness.bookingRepo.quoteError = null;
      await tapText(tester, 'Retry');
      expect(find.text('Confirm booking - ₹499'), findsOneWidget);
    });
  });

  group('confirming', () {
    testWidgets('sends the choices, never a price, then shows the booking',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      await harness.pump(tester);
      await toSummary(tester, landmark: 'Near the temple');
      await tapKey(tester, 'addon-c1');
      await tester.enterText(find.byType(TextField), 'Gate 4');
      await tapButton(tester, 'Confirm booking - ₹849');

      final draft = harness.bookingRepo.creates.single;
      expect(draft.packageId, 'p1');
      expect(draft.extraChargeIds, ['c1']);
      expect(draft.pincode, '560001');
      expect(draft.addressLine, '12 MG Road, Flat 4');
      expect(draft.landmark, 'Near the temple');
      expect(draft.timeSlotId, 'slot1');
      expect(draft.date, tomorrow());
      expect(draft.notes, 'Gate 4');
      expect(draft.expectedTotal, 849);
      expect(draft.clientRequestId, isNotEmpty);

      expect(
        find.textContaining('Your booking FF-000001 has been placed'),
        findsOneWidget,
      );
      expect(find.text('Awaiting payment'), findsWidgets);
      expect(find.text('Review your booking'), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(FfGarageApp)),
      );
      expect(container.read(bookingFlowProvider).hasPackage, isFalse);
    });

    testWidgets('a rejected booking shows why, reloads prices and keeps the '
        'same request key for the retry', (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      await harness.pump(tester);
      await toSummary(tester);

      harness.bookingRepo.createError = const ApiException(
        type: ApiErrorType.conflict,
        message: 'The price has changed. Please review the new total.',
        statusCode: 409,
      );
      await tapButton(tester, 'Confirm booking - ₹499');

      expect(
        find.text('The price has changed. Please review the new total.'),
        findsOneWidget,
      );
      expect(find.text('Review your booking'), findsOneWidget);
      expect(harness.bookingRepo.quoteCalls, 2, reason: 'quote reloaded');
      expect(buttonEnabled(tester, 'Confirm booking - ₹499'), isTrue);

      harness.bookingRepo.createError = null;
      await tapButton(tester, 'Confirm booking - ₹499');

      final creates = harness.bookingRepo.creates;
      expect(creates, hasLength(2));
      expect(creates[1].clientRequestId, creates[0].clientRequestId);
      expect(
        find.textContaining('Your booking FF-000001 has been placed'),
        findsOneWidget,
      );
    });

    testWidgets('a network failure leaves the booking unplaced and retryable',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      await harness.pump(tester);
      await toSummary(tester);

      harness.bookingRepo.createError = networkError;
      await tapButton(tester, 'Confirm booking - ₹499');

      expect(find.text('Unable to reach the server.'), findsOneWidget);
      expect(find.text('Review your booking'), findsOneWidget);
      expect(harness.bookingRepo.bookings, isEmpty);
      expect(buttonEnabled(tester, 'Confirm booking - ₹499'), isTrue);
    });
  });
}
