import 'package:ff_garage/app/router/app_routes.dart';
import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/core/preferences/app_preferences.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/models/vehicle.dart';
import 'package:ff_garage/data/services/location_service.dart';
import 'package:ff_garage/features/home/providers/home_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/booking_journey.dart';
import '../support/fakes_maps.dart';
import '../support/fakes_vehicles.dart';
import '../support/pump_app.dart';

void main() {
  group('registration rule', () {
    test('accepts real plate shapes and normalises them', () {
      expect(normalizeRegistration('mh 12-ab 1234'), 'MH12AB1234');
      expect(normalizeRegistration('DL1CAB1234'), 'DL1CAB1234');
      expect(normalizeRegistration('22bh1234aa'), '22BH1234AA');
    });

    test('rejects everything else', () {
      for (final bad in ['', 'MH12', '1234', 'MH12AB12345', 'abc!', 'XX00']) {
        expect(normalizeRegistration(bad), isNull, reason: bad);
      }
    });

    test('shows a readable plate', () {
      expect(vehicle().registrationPretty, 'MH12 AB 1234');
      expect(vehicle(nickname: 'Daily').title, 'Daily');
      expect(vehicle().title, 'TVS Jupiter');
    });
  });

  group('my vehicles', () {
    Future<AppHarness> open(WidgetTester tester,
        {List<Vehicle>? saved, MemoryPreferences? prefs}) async {
      useTallScreen(tester);
      final harness = AppHarness(
        role: UserRole.customer,
        vehicles: FakeVehicleRepository(saved),
        preferences: prefs,
      );
      await harness.pump(tester);
      goTo(tester, AppRoutes.vehicles);
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('empty list invites adding one', (tester) async {
      await open(tester);
      expect(find.textContaining('No vehicles saved yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('add-vehicle')), findsOneWidget);
    });

    testWidgets('adds a vehicle with validation and selects it', (tester) async {
      final harness = await open(tester);
      await tester.tap(find.byKey(const ValueKey('add-vehicle')));
      await tester.pumpAndSettle();

      // Nothing filled in: every required field complains.
      await tapText(tester, 'Save vehicle');
      expect(find.textContaining('valid registration number'), findsOneWidget);
      expect(find.text('Enter the make, e.g. Honda'), findsOneWidget);
      expect(find.text('Enter the model, e.g. Activa'), findsOneWidget);
      expect(harness.vehicles.items, isEmpty);

      await tester.enterText(
          find.byKey(const ValueKey('vehicle-registration')), 'mh 12 ab 1234');
      await tester.enterText(find.byKey(const ValueKey('vehicle-make')), 'Honda');
      await tester.enterText(find.byKey(const ValueKey('vehicle-model')), 'Shine');
      await tester.tap(find.byKey(const ValueKey('type-bike')));
      await tester.pumpAndSettle();
      await tapText(tester, 'Save vehicle');

      final saved = harness.vehicles.items.single;
      expect(saved.registration, 'MH12AB1234');
      expect(saved.type, VehicleType.bike);
      expect(saved.nickname, isNull);
      expect(find.text('Honda Shine'), findsOneWidget);
      expect(harness.preferences.getString('selected_vehicle'), saved.id);
    });

    testWidgets('shows the server refusal for a duplicate plate',
        (tester) async {
      final harness = await open(tester, saved: [vehicle()]);
      await tester.tap(find.byKey(const ValueKey('add-vehicle')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('vehicle-registration')), 'MH12AB1234');
      await tester.enterText(find.byKey(const ValueKey('vehicle-make')), 'TVS');
      await tester.enterText(find.byKey(const ValueKey('vehicle-model')), 'Ntorq');
      await tapText(tester, 'Save vehicle');
      expect(find.text('You have already saved this vehicle'), findsOneWidget);
      expect(harness.vehicles.items.length, 1);
    });

    testWidgets('edits a vehicle', (tester) async {
      final harness = await open(tester, saved: [vehicle()]);
      await tester.tap(find.byKey(const ValueKey('vehicle-menu-v1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Edit vehicle'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('vehicle-model')), 'Ntorq');
      await tester.enterText(
          find.byKey(const ValueKey('vehicle-nickname')), 'Office ride');
      await tapText(tester, 'Save changes');

      expect(harness.vehicles.items.single.model, 'Ntorq');
      expect(harness.vehicles.items.single.nickname, 'Office ride');
      expect(find.text('Office ride'), findsOneWidget);
    });

    testWidgets('removes a vehicle only after confirming', (tester) async {
      final harness = await open(tester, saved: [vehicle()]);
      await tester.tap(find.byKey(const ValueKey('vehicle-menu-v1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove vehicle?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(harness.vehicles.items.length, 1);

      await tester.tap(find.byKey(const ValueKey('vehicle-menu-v1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Remove'),
      ));
      await tester.pumpAndSettle();
      expect(harness.vehicles.items, isEmpty);
      expect(find.textContaining('No vehicles saved yet'), findsOneWidget);
    });

    testWidgets('tapping a vehicle selects it and the choice is saved',
        (tester) async {
      final harness = await open(tester, saved: [
        vehicle(),
        vehicle(id: 'v2', registration: 'MH14CD5678', make: 'Honda', model: 'Shine',
            type: VehicleType.bike),
      ]);
      await tester.tap(find.byKey(const ValueKey('vehicle-v2')));
      await tester.pumpAndSettle();
      expect(harness.preferences.getString('selected_vehicle'), 'v2');
    });

    testWidgets('a load failure offers Retry', (tester) async {
      useTallScreen(tester);
      final repo = FakeVehicleRepository()
        ..error = const ApiException(
          type: ApiErrorType.network,
          message: 'No connection.',
        );
      await AppHarness(role: UserRole.customer, vehicles: repo).pump(tester);
      goTo(tester, AppRoutes.vehicles);
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('drivers and admins cannot open the vehicle screens',
        (tester) async {
      for (final role in [UserRole.driver, UserRole.admin]) {
        await AppHarness(role: role).pump(tester);
        goTo(tester, AppRoutes.vehicles);
        await tester.pumpAndSettle();
        expect(find.text('My vehicles'), findsNothing, reason: '$role');
      }
    });

    testWidgets('settings has a My vehicles entry for customers only',
        (tester) async {
      useTallScreen(tester);
      await AppHarness(role: UserRole.customer).pump(tester);
      await tester.tap(find.byKey(const ValueKey('nav-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-vehicles')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('add-vehicle')), findsOneWidget);

      await AppHarness(role: UserRole.driver).pump(tester);
      await tester.tap(find.byKey(const ValueKey('nav-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-vehicles')), findsNothing);
    });
  });

  group('home: vehicle card and search', () {
    testWidgets('invites adding a vehicle, then shows the saved one',
        (tester) async {
      useTallScreen(tester);
      await AppHarness(role: UserRole.customer).pump(tester);
      expect(find.text('Add Your Vehicle'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await AppHarness(
        role: UserRole.customer,
        vehicles: FakeVehicleRepository([vehicle(nickname: 'Daily ride')]),
      ).pump(tester);
      expect(find.text('Daily ride'), findsOneWidget);
      expect(find.textContaining('MH12 AB 1234'), findsOneWidget);
    });

    testWidgets('the search bar opens the service list with the text',
        (tester) async {
      useTallScreen(tester);
      await AppHarness(role: UserRole.customer).pump(tester);
      await tester.enterText(find.byKey(const ValueKey('home-search')), 'general');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Our services'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'general'), findsOneWidget);
    });
  });

  group('home: location', () {
    testWidgets('the first visit explains and does not ask by itself',
        (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(role: UserRole.customer);
      await harness.pump(tester);
      expect(find.text('Find service near you'), findsOneWidget);
      expect(harness.location.calls, 0);
    });

    testWidgets('allowing shows the address, serviceability and a map',
        (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(role: UserRole.customer, mapsEnabled: true);
      harness.maps.reverseResults = [place()];
      await harness.pump(tester);

      await tester.tap(find.byKey(const ValueKey('allow-location')));
      await tester.pumpAndSettle();

      expect(harness.location.calls, 1);
      expect(find.textContaining('12 MG Road'), findsOneWidget);
      expect(find.text('We service this area'), findsOneWidget);
      expect(harness.mapView.spec?.marker, isNotNull);
      expect(harness.preferences.getBool(HomeLocationController.grantedKey),
          isTrue);
    });

    testWidgets('an area we do not service says so', (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(role: UserRole.customer);
      harness.maps.reverseResults = [place(serviceable: false, pincode: '560001')];
      await harness.pump(tester);
      await tester.tap(find.byKey(const ValueKey('allow-location')));
      await tester.pumpAndSettle();
      expect(find.textContaining("don't service this area yet"), findsOneWidget);
    });

    testWidgets('a failed address lookup still shows the pinned location',
        (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(role: UserRole.customer);
      harness.maps.reverseError = lookupUnavailable;
      await harness.pump(tester);
      await tester.tap(find.byKey(const ValueKey('allow-location')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pinned location'), findsOneWidget);
    });

    testWidgets('"Not now" is remembered and never asks again', (tester) async {
      useTallScreen(tester);
      final saved = MemoryPreferences();
      final first = AppHarness(role: UserRole.customer, preferences: saved);
      await first.pump(tester);
      await tester.tap(find.byKey(const ValueKey('skip-location')));
      await tester.pumpAndSettle();
      expect(first.location.calls, 0);
      expect(find.byKey(const ValueKey('choose-on-map')), findsOneWidget);
      // The PIN-code check is still there as the typed alternative.
      expect(find.text('Do we service your area?'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      final second = AppHarness(role: UserRole.customer, preferences: saved);
      await second.pump(tester);
      expect(find.text('Find service near you'), findsNothing);
      expect(second.location.calls, 0);
    });

    testWidgets('a refusal falls back to the map and is not repeated',
        (tester) async {
      useTallScreen(tester);
      final saved = MemoryPreferences();
      final first = AppHarness(
        role: UserRole.customer,
        preferences: saved,
        location: FakeLocationService(
          const LocationFailed(LocationProblem.denied),
        ),
      );
      await first.pump(tester);
      await tester.tap(find.byKey(const ValueKey('allow-location')));
      await tester.pumpAndSettle();
      expect(find.text('Location access is off for this app.'), findsOneWidget);
      expect(find.byKey(const ValueKey('choose-on-map')), findsOneWidget);
      expect(first.location.calls, 1);

      await tester.pumpWidget(const SizedBox());
      final second = AppHarness(role: UserRole.customer, preferences: saved);
      await second.pump(tester);
      expect(second.location.calls, 0);
    });

    testWidgets('after a grant, later visits read the position quietly',
        (tester) async {
      useTallScreen(tester);
      final saved = MemoryPreferences();
      final first = AppHarness(role: UserRole.customer, preferences: saved);
      first.maps.reverseResults = [place()];
      await first.pump(tester);
      await tester.tap(find.byKey(const ValueKey('allow-location')));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      final second = AppHarness(role: UserRole.customer, preferences: saved);
      second.maps.reverseResults = [place()];
      await second.pump(tester);
      expect(find.text('Find service near you'), findsNothing);
      expect(second.location.calls, 1);
      expect(find.textContaining('12 MG Road'), findsOneWidget);
    });
  });

  group('booking summary: vehicle', () {
    // The full booking journey is covered in booking_flow_test; here only the
    // vehicle choice on the summary and what is sent.
    testWidgets('sends the saved vehicle of the right type', (tester) async {
      useTallScreen(tester);
      final harness = customerHarness(
        vehicles: FakeVehicleRepository([
          vehicle(id: 'bike1', type: VehicleType.bike, registration: 'MH14CD5678',
              make: 'Honda', model: 'Shine'),
          vehicle(),
        ]),
      );
      await harness.pump(tester);
      await toSummary(tester);

      expect(find.text('Your vehicle'), findsOneWidget);
      // The test service is for scooters, so the scooter is used.
      expect(find.textContaining('TVS Jupiter'), findsWidgets);
      await tester.tap(find.textContaining('Confirm booking'));
      await tester.pumpAndSettle();
      expect(harness.bookingRepo.creates.single.vehicleId, 'v1');
    });

    testWidgets('booking still works with no saved vehicle', (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      await harness.pump(tester);
      await toSummary(tester);
      expect(find.byKey(const ValueKey('add-vehicle-booking')), findsOneWidget);
      await tester.tap(find.textContaining('Confirm booking'));
      await tester.pumpAndSettle();
      expect(harness.bookingRepo.creates.single.vehicleId, isNull);
    });
  });
}
