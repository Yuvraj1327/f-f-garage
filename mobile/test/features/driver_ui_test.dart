import 'package:ff_garage/data/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/booking_journey.dart';
import '../support/fakes.dart';
import '../support/fakes_driver.dart';
import '../support/pump_app.dart';

AppHarness _driver(List<dynamic> jobs) => AppHarness(
      role: UserRole.driver,
      driverWork: FakeDriverWorkRepository(jobs: [...jobs.cast()]),
    );

void main() {
  group('My Jobs', () {
    testWidgets('a job card shows customer, vehicle, service, time, address and status',
        (tester) async {
      useTallScreen(tester);
      await _driver([driverJob()]).pump(tester);

      final card = find.byKey(const ValueKey('job-b1'));
      for (final text in [
        'FF-000001',
        'General Service',
        'Basic',
        'Test User - +919876543210',
        'Scooter',
      ]) {
        expect(find.descendant(of: card, matching: find.text(text)), findsOneWidget,
            reason: text);
      }
      expect(
        find.descendant(of: card, matching: find.textContaining('12 MG Road')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('9:00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text("Next: I'm on my way")),
        findsOneWidget,
      );
    });

    testWidgets('the empty state appears only when there are no jobs',
        (tester) async {
      await _driver([driverJob()]).pump(tester);
      expect(find.textContaining('No jobs assigned'), findsNothing);

      await _driver([]).pump(tester);
      expect(find.textContaining('No jobs assigned'), findsOneWidget);
    });

    testWidgets('pull to refresh reloads the list', (tester) async {
      final harness = _driver([]);
      await harness.pump(tester);
      expect(find.textContaining('No jobs assigned'), findsOneWidget);

      harness.driverWork.jobs = [driverJob()];
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('job-b1')), findsOneWidget);
    });

    testWidgets('a failed first load shows Retry and can be refreshed away',
        (tester) async {
      final harness = _driver([driverJob()]);
      harness.driverWork.error = networkError;
      await harness.pump(tester);
      expect(find.text('Unable to reach the server.'), findsWidgets);

      harness.driverWork.error = null;
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('job-b1')), findsOneWidget);
    });

    testWidgets('a failed refresh keeps the list and says so', (tester) async {
      final harness = _driver([driverJob()]);
      await harness.pump(tester);
      harness.driverWork.error = networkError;
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('job-b1')), findsOneWidget);
      expect(find.byKey(const ValueKey('refresh-error')), findsOneWidget);

      harness.driverWork.error = null;
      await tapText(tester, 'Retry');
      expect(find.byKey(const ValueKey('refresh-error')), findsNothing);
    });

    testWidgets('does not overflow on a small phone', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _driver([driverJob(), driverJob(id: 'b2', number: 2)]).pump(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('History', () {
    testWidgets('lists completed and cancelled jobs', (tester) async {
      useTallScreen(tester);
      await _driver([
        driverJob(id: 'done', status: BookingStatus.completed, next: null),
        driverJob(id: 'gone', number: 2, status: BookingStatus.cancelled, next: null),
      ]).pump(tester);
      await tapKey(tester, 'nav-history');

      expect(find.byKey(const ValueKey('job-done')), findsOneWidget);
      expect(find.byKey(const ValueKey('job-gone')), findsOneWidget);
      expect(find.text('View details'), findsNWidgets(2));
    });
  });

  group('Earnings', () {
    testWidgets('shows real counts and the latest completed jobs, no invented money',
        (tester) async {
      useTallScreen(tester);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await _driver([
        driverJob(id: 'c1', status: BookingStatus.completed, next: null, date: today),
        driverJob(
            id: 'c2',
            number: 2,
            status: BookingStatus.completed,
            next: null,
            date: today),
        driverJob(id: 'o1', number: 3),
      ]).pump(tester);
      await tapKey(tester, 'nav-earnings');

      expect(
        find.descendant(
            of: find.byKey(const ValueKey('earnings-today')), matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: find.byKey(const ValueKey('earnings-week')), matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: find.byKey(const ValueKey('earnings-open')), matching: find.text('1')),
        findsOneWidget,
      );
      expect(find.text('FF-000001 - General Service'), findsOneWidget);
      expect(find.byKey(const ValueKey('earnings-note')), findsOneWidget);
      expect(find.textContaining('₹'), findsNothing);
    });

    testWidgets('with no completed jobs it says so', (tester) async {
      await _driver([]).pump(tester);
      await tapKey(tester, 'nav-earnings');
      expect(find.byKey(const ValueKey('earnings-empty')), findsOneWidget);
    });

    testWidgets('a failed load shows Retry', (tester) async {
      final harness = _driver([]);
      harness.driverWork.error = networkError;
      await harness.pump(tester);
      await tapKey(tester, 'nav-earnings');
      expect(find.text('Unable to reach the server.'), findsWidgets);
      harness.driverWork.error = null;
      await tapText(tester, 'Retry');
      expect(find.byKey(const ValueKey('earnings-empty')), findsOneWidget);
    });
  });

  group('Settings', () {
    testWidgets('has the profile and Logout, and the bottom bar stays',
        (tester) async {
      useTallScreen(tester);
      await _driver([]).pump(tester);
      await tapKey(tester, 'nav-settings');
      expect(find.byKey(const ValueKey('settings-profile')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-logout')), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byKey(const ValueKey('side-dashboard')), findsNothing);
    });
  });
}
