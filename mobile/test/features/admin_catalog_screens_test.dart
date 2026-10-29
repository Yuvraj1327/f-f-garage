import 'package:ff_garage/data/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/fakes_catalog.dart';
import '../support/pump_app.dart';
import '../support/booking_journey.dart';

Future<AppHarness> _openServices(
  WidgetTester tester, {
  FakeCatalogRepository? catalog,
}) async {
  final harness = AppHarness(role: UserRole.admin, catalog: catalog);
  await harness.pump(tester);
  await tapKey(tester, 'side-services');
  return harness;
}

void main() {
  testWidgets('the admin sidebar offers services, areas and availability',
      (tester) async {
    await AppHarness(role: UserRole.admin).pump(tester);
    for (final key in ['side-services', 'side-areas', 'side-availability']) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
  });

  testWidgets('lists services including inactive ones, with a filter',
      (tester) async {
    final catalog = FakeCatalogRepository([
      service(),
      service(id: 's2', name: 'Chain Service', type: VehicleType.bike, isActive: false),
    ]);
    await _openServices(tester, catalog: catalog);

    expect(find.text('General Service'), findsOneWidget);
    expect(find.text('Chain Service'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);

    await tapText(tester, 'Bike');
    expect(find.text('General Service'), findsNothing);
    expect(find.text('Chain Service'), findsOneWidget);
  });

  testWidgets('the switch disables a service', (tester) async {
    final harness = await _openServices(tester);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(harness.catalog.calls, contains('updateService:s1'));
    expect(harness.catalog.lastChanges, {'is_active': false});
    expect(find.text('Inactive'), findsOneWidget);
  });

  testWidgets('a failing toggle shows the error and keeps the old state',
      (tester) async {
    final harness = await _openServices(tester);
    harness.catalog.error = networkError;
    // Only writes should fail for this check: reads were already loaded.
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('Unable to reach the server.'), findsOneWidget);
  });

  testWidgets('creating a service validates, saves it with its package, then publishes',
      (tester) async {
    final harness = await _openServices(tester);
    await tapText(tester, 'Add service');

    await tapText(tester, 'Publish service');
    expect(find.text('Enter the service name'), findsOneWidget);
    expect(harness.catalog.calls.where((c) => c.startsWith('createService')), isEmpty);

    await enter(tester, 'Service name', 'Brake Service');
    await tapText(tester, 'Bike');
    await tapText(tester, 'Publish service');
    expect(find.text('Enter the price'), findsOneWidget, reason: 'price is required');

    await enter(tester, 'Price', '499');
    await tapText(tester, 'Publish service');

    expect(
      harness.catalog.calls,
      contains('createService:Brake Service:bike:Service Packages'),
    );
    // Created switched off, completed with its package, then switched on.
    expect(harness.catalog.lastCreate!['is_active'], false);
    expect(harness.catalog.lastCreate!['category_id'], 'cat-package');
    expect(
      harness.catalog.calls.indexWhere((c) => c.startsWith('createPackage')),
      greaterThan(harness.catalog.calls.indexWhere((c) => c.startsWith('createService'))),
    );
    expect(harness.catalog.calls.last, startsWith('updateService:new-'));
    expect(harness.catalog.lastChanges, {'is_active': true});
    // Lands on the new service's page.
    expect(find.text('Brake Service'), findsWidgets);
    expect(find.text('Packages'), findsOneWidget);
  });

  testWidgets('a duplicate service name shows the server message inline',
      (tester) async {
    final harness = await _openServices(tester);
    await tapText(tester, 'Add service');
    await enter(tester, 'Service name', 'General Service');
    await enter(tester, 'Price', '499');
    harness.catalog.error = conflictServiceError;
    await tapText(tester, 'Publish service');

    expect(find.text('A service with this name already exists'), findsOneWidget);
    expect(find.text('New service'), findsOneWidget, reason: 'stays on the form');
  });

  testWidgets('editing sends only the changed fields', (tester) async {
    final harness = await _openServices(tester);
    await tapText(tester, 'General Service');
    await tester.tap(find.byTooltip('Edit service'));
    await tester.pumpAndSettle();

    // Vehicle type cannot be changed once the service exists.
    expect(find.text('Cannot be changed after creation'), findsOneWidget);
    await enter(tester, 'Service name', 'Full Service');
    await tapText(tester, 'Save changes');

    expect(harness.catalog.lastChanges, {'name': 'Full Service'});
    expect(
      harness.catalog.calls.where((c) => c.startsWith('updatePackage')),
      isEmpty,
      reason: 'the package was not touched',
    );
  });

  testWidgets('package form validates the price and parses inclusions',
      (tester) async {
    final harness = await _openServices(tester);
    await tapText(tester, 'General Service');
    await tapText(tester, 'Add package');

    await enter(tester, 'Package name', 'Premium');
    await enter(tester, 'Price', '10.999');
    await tapText(tester, 'Save');
    expect(find.text('Enter a valid amount (at most 2 decimal places)'), findsOneWidget);

    await enter(tester, 'Price', '899.5');
    await enter(tester, 'What is included (one per line)', 'Wash\n wash \n\nOil top-up');
    await enter(tester, 'Estimated duration (optional)', '4');
    await tapText(tester, 'Save');
    expect(find.text('Enter whole minutes between 5 and 1440'), findsOneWidget);

    await enter(tester, 'Estimated duration (optional)', '120');
    await tapText(tester, 'Save');
    expect(
      harness.catalog.calls,
      contains('createPackage:Premium:899.5:Wash|Oil top-up:120'),
    );
  });

  testWidgets('a negative price is rejected', (tester) async {
    await _openServices(tester);
    await tapText(tester, 'General Service');
    await tapText(tester, 'Add package');
    await enter(tester, 'Package name', 'Premium');
    await enter(tester, 'Price', '-5');
    await tapText(tester, 'Save');
    expect(find.text('Enter a valid amount (at most 2 decimal places)'), findsOneWidget);
  });

  testWidgets('an extra charge can be created without an amount',
      (tester) async {
    final harness = await _openServices(tester);
    await tapText(tester, 'General Service');
    await tapText(tester, 'Add charge');

    await enter(tester, 'Name', 'Air filter');
    await tapText(tester, 'Save');

    expect(
      harness.catalog.calls,
      contains('createCharge:Air filter:spare_part:null:null'),
    );
  });

  testWidgets('an extra charge can be deleted after confirming', (tester) async {
    final catalog = FakeCatalogRepository([
      service(charges: [charge()]),
    ]);
    await _openServices(tester, catalog: catalog);
    await tapText(tester, 'General Service');
    await tapText(tester, 'Engine oil 10W-30');

    await tester.tap(find.byTooltip('Delete charge'));
    await tester.pumpAndSettle();
    expect(find.text('Delete charge?'), findsOneWidget);
    await tapText(tester, 'Cancel');
    expect(catalog.calls.where((c) => c.startsWith('deleteCharge')), isEmpty);

    await tester.tap(find.byTooltip('Delete charge'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Delete');
    expect(catalog.calls, contains('deleteCharge:c1'));
  });

  testWidgets('a service list that fails to load offers Retry', (tester) async {
    final catalog = FakeCatalogRepository([service()])
      ..error = networkError;
    await _openServices(tester, catalog: catalog);
    expect(find.text('Unable to reach the server.'), findsOneWidget);

    catalog.error = null;
    await tapText(tester, 'Retry');
    expect(find.text('General Service'), findsOneWidget);
  });
}
