import 'package:ff_garage/app/router/app_routes.dart';
import 'package:ff_garage/core/network/auth_failure.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/models/service_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/fakes_catalog.dart';
import '../support/pump_app.dart';

ServiceArea _area() => const ServiceArea(
      id: 'a1',
      pincode: '560001',
      areaName: 'MG Road',
      city: 'Bengaluru',
      state: 'Karnataka',
      isActive: true,
    );

void main() {
  group('customer', () {
    testWidgets('checks a serviceable PIN code', (tester) async {
      final harness = AppHarness(
        role: UserRole.customer,
        areas: FakeServiceAreaRepository([_area()]),
      );
      await harness.pump(tester);

      await enter(tester, 'PIN code', '560001');
      await tapText(tester, 'Check');

      expect(harness.areas.calls, contains('check:560001'));
      expect(find.textContaining('Good news! We service MG Road'), findsOneWidget);
    });

    testWidgets('reports an unserviceable PIN code', (tester) async {
      final harness = AppHarness(role: UserRole.customer);
      await harness.pump(tester);

      await enter(tester, 'PIN code', '999999');
      await tapText(tester, 'Check');
      expect(
        find.text('Sorry, we do not service 999999 yet.'),
        findsOneWidget,
      );
    });

    testWidgets('an invalid PIN code is rejected before any request',
        (tester) async {
      final harness = AppHarness(role: UserRole.customer);
      await harness.pump(tester);

      await enter(tester, 'PIN code', '12ab');
      await tapText(tester, 'Check');
      expect(find.text('Enter a valid 6-digit PIN code'), findsOneWidget);
      expect(harness.areas.calls, isEmpty);
    });

    testWidgets('a failed check shows the error', (tester) async {
      final harness = AppHarness(role: UserRole.customer);
      harness.areas.error = networkError;
      await harness.pump(tester);

      await enter(tester, 'PIN code', '560001');
      await tapText(tester, 'Check');
      expect(find.text('Unable to reach the server.'), findsOneWidget);
    });

    testWidgets('browses active services and opens the details',
        (tester) async {
      final harness = AppHarness(
        role: UserRole.customer,
        catalog: FakeCatalogRepository([
          service(),
          service(id: 's2', name: 'Hidden Service', isActive: false),
        ]),
      );
      await harness.pump(tester);
      await tapText(tester, 'Browse services');

      expect(find.text('General Service'), findsOneWidget);
      expect(find.text('Hidden Service'), findsNothing);

      await tapText(tester, 'General Service');
      expect(find.text('Wash'), findsOneWidget);
      expect(find.text('Oil top-up'), findsOneWidget);
    });

    testWidgets('browse shows an empty message for a type with no services',
        (tester) async {
      final harness = AppHarness(role: UserRole.customer);
      await harness.pump(tester);
      await tapText(tester, 'Browse services');
      await tapText(tester, 'Bike');
      expect(find.textContaining('No bike services are available'), findsOneWidget);
    });

    testWidgets('has no way into the admin screens, even by deep link',
        (tester) async {
      final harness = AppHarness(role: UserRole.customer);
      await harness.pump(tester);

      goTo(tester, AppRoutes.adminServices);
      await tester.pumpAndSettle();

      expect(find.text('Hello, Test User'), findsOneWidget);
      expect(find.text('Add service'), findsNothing);
      expect(harness.catalog.calls.where((c) => c == 'adminList'), isEmpty);
    });
  });

  group('driver', () {
    testWidgets('cannot reach the admin or customer catalogue screens',
        (tester) async {
      final harness = AppHarness(role: UserRole.driver);
      await harness.pump(tester);

      goTo(tester, AppRoutes.adminAreas);
      await tester.pumpAndSettle();
      expect(find.textContaining('No jobs assigned to you right now.'), findsOneWidget);

      goTo(tester, AppRoutes.browseServices);
      await tester.pumpAndSettle();
      expect(find.textContaining('No jobs assigned to you right now.'), findsOneWidget);
    });
  });

  group('admin sign in', () {
    testWidgets('an admin signs in and lands on the admin home',
        (tester) async {
      final harness = AppHarness(role: UserRole.admin);
      harness.gateway.hasStoredSession = false;
      await harness.pump(tester);

      await tapText(tester, 'Admin sign in');
      expect(find.text('Manage services, service areas and availability.'),
          findsOneWidget);

      await enter(tester, 'Email', 'admin@example.com');
      await enter(tester, 'Password', 'secret-pass-1');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(harness.gateway.lastEmail, 'admin@example.com');
      expect(find.text('Service areas'), findsOneWidget);
      expect(find.text('Availability'), findsOneWidget);
    });

    testWidgets('a customer account is refused on the admin sign-in',
        (tester) async {
      final harness = AppHarness(role: UserRole.customer);
      harness.gateway.hasStoredSession = false;
      await harness.pump(tester);

      await tapText(tester, 'Admin sign in');
      await enter(tester, 'Email', 'user@example.com');
      await enter(tester, 'Password', 'secret-pass-1');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text(AuthFailure.notAdminAccount.message), findsOneWidget);
      expect(find.text('Service areas'), findsNothing);
      expect(harness.gateway.hasSession, isFalse);
    });
  });
}
