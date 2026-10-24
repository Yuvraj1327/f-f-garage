import 'package:ff_garage/app/router/app_routes.dart';
import 'package:ff_garage/data/models/booking.dart';
import 'package:ff_garage/data/models/driver.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/features/booking/presentation/booking_timeline.dart';
import 'package:ff_garage/features/booking/presentation/booking_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/booking_journey.dart';
import '../support/fakes_booking.dart';
import '../support/fakes_driver.dart';
import '../support/fakes_notification.dart';
import '../support/fakes_payment.dart';
import '../support/pump_app.dart';

TimelineEvent _e(BookingStatus status, int minute) => TimelineEvent(
      status: status,
      at: DateTime.utc(2026, 10, 21, 10, minute),
    );

List<String> _states(Booking b) =>
    [for (final s in buildTimeline(b)) '${s.label}:${s.state.name}'];

const _ravi = DriverSummary(name: 'Ravi Kumar', phone: '+919876500001');

void main() {
  group('timeline steps', () {
    test('a new booking: placed, then waiting for payment', () {
      final steps = buildTimeline(booking());
      expect(_states(booking()), [
        'Booking placed:done',
        'Booking confirmed:upcoming',
        'Driver assigned:upcoming',
        'Driver on the way:upcoming',
        'Service in progress:upcoming',
        'Service completed:upcoming',
      ]);
      expect(steps[1].hint, 'Waiting for payment');
      expect(steps[0].at, isNotNull);
      expect(steps[2].at, isNull);
    });

    test('a failed payment says so on the next step', () {
      final b = booking(payment: payment(status: PaymentStatus.failed));
      expect(buildTimeline(b)[1].hint, contains('payment failed'));
      expect(buildTimeline(b)[1].state, StepState.upcoming);
    });

    test('confirmed: waiting for a driver', () {
      final b = booking(
        status: BookingStatus.confirmed,
        timeline: [
          _e(BookingStatus.pendingPayment, 0),
          _e(BookingStatus.confirmed, 5),
        ],
      );
      expect(_states(b).take(3), [
        'Booking placed:done',
        'Booking confirmed:done',
        'Driver assigned:upcoming',
      ]);
      expect(buildTimeline(b)[1].at, DateTime.utc(2026, 10, 21, 10, 5));
      expect(buildTimeline(b)[2].hint, 'We will assign a driver soon');
    });

    test('assigned, on the way and in progress mark the current step active',
        () {
      for (final entry in {
        BookingStatus.assigned: 2,
        BookingStatus.onTheWay: 3,
        BookingStatus.inProgress: 4,
      }.entries) {
        final steps = buildTimeline(booking(status: entry.key, driver: _ravi));
        for (var i = 0; i < steps.length; i++) {
          final expected = i < entry.value
              ? StepState.done
              : i == entry.value
                  ? StepState.active
                  : StepState.upcoming;
          expect(steps[i].state, expected, reason: '${entry.key} step $i');
        }
      }
      final assigned =
          buildTimeline(booking(status: BookingStatus.assigned, driver: _ravi));
      expect(assigned[2].hint, 'Ravi Kumar will do your service');
    });

    test('completed: every step is done', () {
      final steps = buildTimeline(booking(
        status: BookingStatus.completed,
        completedAt: DateTime.utc(2026, 10, 21, 12),
      ));
      expect(steps.every((s) => s.state == StepState.done), isTrue);
      expect(steps.last.at, DateTime.utc(2026, 10, 21, 12));
    });

    test('a removed driver puts the booking back to waiting for a driver', () {
      final b = booking(
        status: BookingStatus.confirmed,
        timeline: [
          _e(BookingStatus.pendingPayment, 0),
          _e(BookingStatus.confirmed, 5),
          _e(BookingStatus.assigned, 10),
          _e(BookingStatus.confirmed, 15),
        ],
      );
      final steps = buildTimeline(b);
      expect(steps[2].state, StepState.upcoming);
      expect(steps[2].at, isNull);
      expect(steps[1].at, DateTime.utc(2026, 10, 21, 10, 15));
    });

    test('cancelled before payment shows only placed and cancelled', () {
      final b = booking(
        status: BookingStatus.cancelled,
        cancelledAt: DateTime.utc(2026, 10, 21, 11),
        timeline: [
          _e(BookingStatus.pendingPayment, 0),
          _e(BookingStatus.cancelled, 30),
        ],
      );
      expect(_states(b), ['Booking placed:done', 'Booking cancelled:cancelled']);
    });

    test('cancelled after a driver was assigned keeps the steps it reached',
        () {
      final b = booking(
        status: BookingStatus.cancelled,
        timeline: [
          _e(BookingStatus.pendingPayment, 0),
          _e(BookingStatus.confirmed, 5),
          _e(BookingStatus.assigned, 10),
          _e(BookingStatus.cancelled, 20),
        ],
      );
      expect(_states(b), [
        'Booking placed:done',
        'Booking confirmed:done',
        'Driver assigned:done',
        'Booking cancelled:cancelled',
      ]);
    });

    test('cancelled after the driver was removed stops at confirmed', () {
      final b = booking(
        status: BookingStatus.cancelled,
        timeline: [
          _e(BookingStatus.pendingPayment, 0),
          _e(BookingStatus.confirmed, 5),
          _e(BookingStatus.assigned, 10),
          _e(BookingStatus.confirmed, 12),
          _e(BookingStatus.cancelled, 20),
        ],
      );
      expect(_states(b).length, 3);
      expect(_states(b).last, 'Booking cancelled:cancelled');
    });

    test('without a history the steps come from the booking itself', () {
      final paid = booking(
        status: BookingStatus.cancelled,
        confirmedAt: DateTime.utc(2026, 10, 21, 10, 5),
        cancelledAt: DateTime.utc(2026, 10, 21, 11),
      );
      expect(_states(paid), [
        'Booking placed:done',
        'Booking confirmed:done',
        'Booking cancelled:cancelled',
      ]);
      expect(_states(booking(status: BookingStatus.cancelled)).length, 2);
    });
  });

  group('progress line', () {
    test('says where each booking stands', () {
      expect(bookingProgressLine(booking()), 'Waiting for payment');
      expect(
        bookingProgressLine(
          booking(payment: payment(status: PaymentStatus.failed)),
        ),
        'Payment failed - tap to try again',
      );
      expect(bookingProgressLine(booking(status: BookingStatus.confirmed)),
          'Paid - waiting for a driver');
      expect(
        bookingProgressLine(
            booking(status: BookingStatus.assigned, driver: _ravi)),
        'Driver: Ravi Kumar',
      );
      expect(
        bookingProgressLine(
            booking(status: BookingStatus.onTheWay, driver: _ravi)),
        'Ravi Kumar is on the way',
      );
      expect(bookingProgressLine(booking(status: BookingStatus.inProgress)),
          'Service in progress');
      expect(
        bookingProgressLine(booking(
          status: BookingStatus.completed,
          completedAt: DateTime(2026, 10, 21, 12),
        )),
        'Completed Wed, 21 Oct 2026',
      );
      expect(
        bookingProgressLine(booking(
          status: BookingStatus.cancelled,
          cancelledAt: DateTime(2026, 10, 21, 12),
        )),
        'Cancelled Wed, 21 Oct 2026',
      );
      expect(bookingProgressLine(booking(status: BookingStatus.cancelled)),
          'Cancelled');
    });
  });

  group('booking details', () {
    testWidgets('show the number, status, payment, driver and progress',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness(
        bookings: FakeBookingRepository(bookings: [
          booking(
            status: BookingStatus.assigned,
            isPaid: true,
            payment: payment(),
            driver: _ravi,
            timeline: [
              _e(BookingStatus.pendingPayment, 0),
              _e(BookingStatus.confirmed, 5),
              _e(BookingStatus.assigned, 10),
            ],
          ),
        ]),
      );
      await harness.pump(tester);
      goTo(tester, AppRoutes.booking('b1'));
      await tester.pumpAndSettle();

      expect(find.text('FF-000001'), findsOneWidget);
      expect(find.text('Driver assigned'), findsWidgets);
      expect(find.text('Payment: Paid'), findsOneWidget);
      expect(find.text('Progress'), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline-step-5')), findsOneWidget);
      expect(find.text('Ravi Kumar will do your service'), findsOneWidget);
      expect(find.text('Your driver'), findsOneWidget);
      expect(find.text('12 MG Road, Bengaluru 560001'), findsOneWidget);
    });

    testWidgets('an unpaid booking says it is not paid yet', (tester) async {
      useTallScreen(tester);
      final harness = customerHarness(
        bookings: FakeBookingRepository(bookings: [booking()]),
      );
      await harness.pump(tester);
      goTo(tester, AppRoutes.booking('b1'));
      await tester.pumpAndSettle();
      expect(find.text('Payment: Not paid yet'), findsOneWidget);
      expect(find.text('Waiting for payment'), findsOneWidget);
    });

    testWidgets('a cancelled booking shows no steps that can still happen',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness(
        bookings: FakeBookingRepository(bookings: [
          booking(
            status: BookingStatus.cancelled,
            canCancel: false,
            canModify: false,
            timeline: [
              _e(BookingStatus.pendingPayment, 0),
              _e(BookingStatus.cancelled, 20),
            ],
          ),
        ]),
      );
      await harness.pump(tester);
      goTo(tester, AppRoutes.booking('b1'));
      await tester.pumpAndSettle();

      expect(find.text('Booking cancelled'), findsOneWidget);
      expect(find.text('Driver on the way'), findsNothing);
      expect(find.text('Service completed'), findsNothing);
    });

    testWidgets('follows a booking while it is open (driver and status)',
        (tester) async {
      useTallScreen(tester);
      final repo = FakeBookingRepository(bookings: [
        booking(
          status: BookingStatus.confirmed,
          isPaid: true,
          payment: payment(),
          timeline: [
            _e(BookingStatus.pendingPayment, 0),
            _e(BookingStatus.confirmed, 5),
          ],
        ),
      ]);
      final harness = customerHarness(
        bookings: repo,
        pollInterval: const Duration(seconds: 5),
      );
      await harness.pump(tester);
      goTo(tester, AppRoutes.booking('b1'));
      await tester.pumpAndSettle();
      expect(find.text('Your driver'), findsNothing);
      expect(find.text('We will assign a driver soon'), findsOneWidget);

      // The admin assigns a driver; the customer does nothing.
      repo.bookings = [
        booking(
          status: BookingStatus.assigned,
          isPaid: true,
          payment: payment(),
          driver: _ravi,
          timeline: [
            _e(BookingStatus.pendingPayment, 0),
            _e(BookingStatus.confirmed, 5),
            _e(BookingStatus.assigned, 10),
          ],
        ),
      ];
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('Your driver'), findsOneWidget);
      expect(find.text('Ravi Kumar will do your service'), findsOneWidget);

      // ...and then the driver completes it.
      repo.bookings = [
        booking(
          status: BookingStatus.completed,
          isPaid: true,
          payment: payment(),
          driver: _ravi,
          canCancel: false,
          canModify: false,
          completedAt: DateTime.utc(2026, 10, 21, 12),
        ),
      ];
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('Service completed'), findsOneWidget);
      expect(find.text('Completed'), findsWidgets);
    });

    testWidgets('a failed check for updates changes nothing', (tester) async {
      useTallScreen(tester);
      final repo = FakeBookingRepository(bookings: [booking()]);
      final harness = customerHarness(
        bookings: repo,
        pollInterval: const Duration(seconds: 5),
      );
      await harness.pump(tester);
      goTo(tester, AppRoutes.booking('b1'));
      await tester.pumpAndSettle();

      repo.error = notFoundError;
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('Booking placed'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('history', () {
    testWidgets('shows status, progress, driver, payment and dates',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness(
        bookings: FakeBookingRepository(bookings: [
          booking(
            id: 'b2',
            number: 2,
            status: BookingStatus.onTheWay,
            isPaid: true,
            payment: payment(),
            driver: _ravi,
          ),
          booking(
            id: 'b1',
            number: 1,
            status: BookingStatus.completed,
            completedAt: DateTime(2026, 10, 18, 12),
            payment: payment(),
          ),
        ]),
      );
      await harness.pump(tester);
      goTo(tester, AppRoutes.bookings);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('progress-line-b2')), findsOneWidget);
      expect(find.text('Ravi Kumar is on the way'), findsOneWidget);
      expect(find.text('Completed Sun, 18 Oct 2026'), findsOneWidget);
      expect(find.text('On the way'), findsOneWidget);
    });
  });

  group('notification bell', () {
    testWidgets('shows how many updates are unread', (tester) async {
      final harness = customerHarness(
        notifications: FakeNotificationRepository(items: [
          notification(id: 'n1'),
          notification(id: 'n2'),
          notification(id: 'n3', read: true),
        ]),
      );
      await harness.pump(tester);
      expect(find.byKey(const ValueKey('notifications-bell')), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('has no count when everything is read', (tester) async {
      final harness = customerHarness(
        notifications: FakeNotificationRepository(
          items: [notification(read: true)],
        ),
      );
      await harness.pump(tester);
      expect(find.text('1'), findsNothing);
      expect(find.byTooltip('Notifications'), findsOneWidget);
    });

    testWidgets('a new notification updates the count and reloads bookings',
        (tester) async {
      useTallScreen(tester);
      final notes = FakeNotificationRepository();
      final bookings = FakeBookingRepository(bookings: [booking()]);
      final harness = customerHarness(
        notifications: notes,
        bookings: bookings,
        pollInterval: const Duration(seconds: 5),
      );
      await harness.pump(tester);
      await tapText(tester, 'My bookings');
      final loads = bookings.lists.length;

      notes.items = [notification(id: 'new')];
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(bookings.lists.length, greaterThan(loads));
    });

    testWidgets('a failed unread check shows no count and no error',
        (tester) async {
      final notes = FakeNotificationRepository(items: [notification()])
        ..error = notFoundError;
      final harness = customerHarness(notifications: notes);
      await harness.pump(tester);
      expect(find.text('1'), findsNothing);
      expect(find.byKey(const ValueKey('notifications-bell')), findsOneWidget);
    });
  });

  group('notifications screen', () {
    testWidgets('lists updates, unread first-class, newest first',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness(
        notifications: FakeNotificationRepository(items: [
          notification(
            id: 'n2',
            kind: 'driver_assigned',
            title: 'Driver assigned',
            body: 'Ravi Kumar is assigned to FF-000001 (General Service).',
          ),
          notification(id: 'n1', read: true),
        ]),
      );
      await harness.pump(tester);
      await tester.tap(find.byKey(const ValueKey('notifications-bell')));
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsWidgets);
      expect(find.text('Driver assigned'), findsOneWidget);
      expect(find.text('Booking confirmed'), findsOneWidget);
      expect(find.byKey(const ValueKey('unread-dot-n2')), findsOneWidget);
      expect(find.byKey(const ValueKey('unread-dot-n1')), findsNothing);
    });

    testWidgets('says there is nothing yet', (tester) async {
      final harness = customerHarness();
      await harness.pump(tester);
      goTo(tester, AppRoutes.notifications);
      await tester.pumpAndSettle();
      expect(find.textContaining('No notifications yet.'), findsOneWidget);
    });

    testWidgets('a failed load shows the error and Retry works',
        (tester) async {
      final notes = FakeNotificationRepository(items: [notification()])
        ..error = notFoundError;
      final harness = customerHarness(notifications: notes);
      await harness.pump(tester);
      goTo(tester, AppRoutes.notifications);
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);

      notes.error = null;
      await tapText(tester, 'Retry');
      expect(find.text('Booking confirmed'), findsOneWidget);
    });

    testWidgets('opening one marks it read and shows its booking',
        (tester) async {
      useTallScreen(tester);
      final notes = FakeNotificationRepository(items: [notification()]);
      final harness = customerHarness(
        notifications: notes,
        bookings: FakeBookingRepository(bookings: [booking()]),
      );
      await harness.pump(tester);
      goTo(tester, AppRoutes.notifications);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('notification-n1')));
      await tester.pumpAndSettle();
      expect(notes.marked.single, ['n1']);
      expect(notes.items.single.isRead, isTrue);
      expect(find.text('Progress'), findsOneWidget);
    });

    testWidgets('mark all read', (tester) async {
      useTallScreen(tester);
      final notes = FakeNotificationRepository(items: [
        notification(id: 'n1'),
        notification(id: 'n2'),
      ]);
      final harness = customerHarness(notifications: notes);
      await harness.pump(tester);
      goTo(tester, AppRoutes.notifications);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('mark-all-read')));
      await tester.pumpAndSettle();
      expect(notes.marked.single, isNull);
      expect(find.text('All notifications marked as read'), findsOneWidget);
      expect(find.byKey(const ValueKey('unread-dot-n1')), findsNothing);
      final button =
          tester.widget<TextButton>(find.byKey(const ValueKey('mark-all-read')));
      expect(button.onPressed, isNull);
    });

    testWidgets('a failed mark-all shows the error and keeps them unread',
        (tester) async {
      useTallScreen(tester);
      final notes = FakeNotificationRepository(items: [notification()])
        ..markError = notFoundError;
      final harness = customerHarness(notifications: notes);
      await harness.pump(tester);
      goTo(tester, AppRoutes.notifications);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('mark-all-read')));
      await tester.pumpAndSettle();
      expect(find.text('Booking not found'), findsOneWidget);
      expect(find.byKey(const ValueKey('unread-dot-n1')), findsOneWidget);
    });

    testWidgets('pages with Load more', (tester) async {
      useTallScreen(tester, height: 6000);
      final notes = FakeNotificationRepository(items: [
        for (var i = 0; i < 25; i++)
          notification(id: 'n$i', title: 'Update $i', read: true),
      ]);
      final harness = customerHarness(notifications: notes);
      await harness.pump(tester);
      goTo(tester, AppRoutes.notifications);
      await tester.pumpAndSettle();

      expect(find.text('Update 0'), findsOneWidget);
      expect(find.text('Update 24'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('load-more')));
      await tester.tap(find.byKey(const ValueKey('load-more')));
      await tester.pumpAndSettle();
      expect(find.text('Update 24'), findsOneWidget);
      expect(find.byKey(const ValueKey('load-more')), findsNothing);
    });
  });

  group('who can open notifications', () {
    testWidgets('a driver and an admin are sent to their own home',
        (tester) async {
      final driver = AppHarness(role: UserRole.driver);
      await driver.pump(tester);
      goTo(tester, AppRoutes.notifications);
      await tester.pumpAndSettle();
      expect(find.textContaining('No jobs assigned to you right now.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('mark-all-read')), findsNothing);
    });

    testWidgets('an admin cannot open them', (tester) async {
      final admin = AppHarness(role: UserRole.admin);
      await admin.pump(tester);
      goTo(tester, AppRoutes.notifications);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mark-all-read')), findsNothing);
      expect(find.text('Service areas'), findsOneWidget);
    });
  });
}
