import 'package:ff_garage/app/router/app_routes.dart';
import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/booking_journey.dart';
import '../support/fakes_booking.dart';
import '../support/fakes_support.dart';
import '../support/pump_app.dart';

void main() {
  group('support screen', () {
    testWidgets('shows every configured way to reach the garage',
        (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(role: UserRole.customer);
      await harness.pump(tester);

      await tapText(tester, 'Help & support');

      expect(find.text('F&F Two Wheeler Garage'), findsOneWidget);
      expect(find.text('+919876543210'), findsOneWidget);
      expect(find.text('help@example.com'), findsOneWidget);
      expect(find.text('12 Main Road, Pune'), findsOneWidget);
      expect(find.text('Mon-Sat 9am-7pm'), findsOneWidget);
      expect(find.text('Common questions'), findsOneWidget);
      expect(harness.support.calls, 1);
    });

    testWidgets('hides what the operator has not configured', (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(
        role: UserRole.customer,
        support: FakeSupportRepository(
          contactDetails(whatsapp: '', email: '', address: '', hours: ''),
        ),
      );
      await harness.pump(tester);

      await tapText(tester, 'Help & support');

      expect(find.text('Call us'), findsOneWidget);
      expect(find.text('WhatsApp'), findsNothing);
      expect(find.text('Email'), findsNothing);
      expect(find.text('Visit us'), findsNothing);
      expect(find.text('Opening hours'), findsNothing);
    });

    testWidgets('says so when no contact details are configured',
        (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(
        role: UserRole.customer,
        support: FakeSupportRepository(
          contactDetails(phone: '', whatsapp: '', email: '', address: ''),
        ),
      );
      await harness.pump(tester);

      await tapText(tester, 'Help & support');

      expect(find.textContaining('has not published contact details'),
          findsOneWidget);
      expect(find.text('Call us'), findsNothing);
    });

    testWidgets('tapping Call, WhatsApp, Email and Visit asks the device',
        (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(role: UserRole.customer);
      await harness.pump(tester);
      await tapText(tester, 'Help & support');

      await tapText(tester, 'Call us');
      await tapText(tester, 'WhatsApp');
      await tapText(tester, 'Email');
      await tapText(tester, 'Visit us');

      expect(harness.contactLauncher.opened, [
        'call:+919876543210',
        'whatsapp:919876543210:Hi, I need help with my service.',
        'email:help@example.com',
        'map:12 Main Road, Pune',
      ]);
    });

    testWidgets('shows the details instead when the device cannot open it',
        (tester) async {
      useTallScreen(tester);
      final launcher = FakeContactLauncher()..canOpen = false;
      final harness =
          AppHarness(role: UserRole.customer, contactLauncher: launcher);
      await harness.pump(tester);
      await tapText(tester, 'Help & support');

      await tapText(tester, 'Call us');

      expect(find.textContaining("Couldn't open that on this device"),
          findsOneWidget);
      expect(find.textContaining('Our number is +919876543210'),
          findsOneWidget);
    });

    testWidgets('a failed load shows the error with a working Retry',
        (tester) async {
      useTallScreen(tester);
      final support = FakeSupportRepository()
        ..error = const ApiException(
          type: ApiErrorType.network,
          message: 'No internet connection.',
        );
      final harness = AppHarness(role: UserRole.customer, support: support);
      await harness.pump(tester);
      await tapText(tester, 'Help & support');

      expect(find.text('No internet connection.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      support.error = null;
      await tapText(tester, 'Retry');

      expect(find.text('+919876543210'), findsOneWidget);
    });

    testWidgets('opened from a booking, it quotes the booking code',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness(
        bookings: FakeBookingRepository(bookings: [booking()]),
      );
      await harness.pump(tester);

      goTo(tester, AppRoutes.booking('b1'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Help with this booking');

      expect(find.textContaining('Asking about booking FF-000001'),
          findsOneWidget);
      await tapText(tester, 'WhatsApp');
      expect(harness.contactLauncher.opened.single,
          'whatsapp:919876543210:Hi, I need help with booking FF-000001.');
    });

    testWidgets('drivers and admins can open it too', (tester) async {
      for (final role in [UserRole.driver, UserRole.admin]) {
        useTallScreen(tester);
        final harness = AppHarness(role: role);
        await harness.pump(tester);

        goTo(tester, AppRoutes.support);
        await tester.pumpAndSettle();

        expect(find.text('Help & support'), findsOneWidget, reason: '$role');
        expect(find.text('+919876543210'), findsOneWidget, reason: '$role');
      }
    });
  });
}
