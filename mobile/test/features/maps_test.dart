import 'package:ff_garage/app/app.dart';
import 'package:ff_garage/app/router/app_routes.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/models/place.dart';
import 'package:ff_garage/data/repositories/maps_repository.dart';
import 'package:ff_garage/data/services/location_service.dart';
import 'package:ff_garage/features/booking/providers/booking_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/booking_journey.dart';
import '../support/fakes_booking.dart';
import '../support/fakes_driver.dart';
import '../support/fakes_maps.dart';
import '../support/pump_app.dart';

/// The Bengaluru PIN code the tests' service area covers.
Place bengaluruPlace({bool? serviceable = true, String pincode = '560001'}) =>
    place(
      address: '12 MG Road, Bengaluru, Karnataka $pincode, India',
      pincode: pincode,
      serviceable: serviceable,
    );

const MapPoint _moved = MapPoint(12.9716, 77.5946);

BookingAddress? _flowAddress(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(FfGarageApp)),
  );
  return container.read(bookingFlowProvider).address;
}

String _text(WidgetTester tester, String label) =>
    tester.widget<TextFormField>(field(label)).controller!.text;

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<FilledButton>(find.byKey(ValueKey(key))).onPressed != null;

Future<void> _moveMap(
  WidgetTester tester,
  AppHarness harness, [
  MapPoint to = _moved,
]) async {
  harness.mapView.moveTo(to);
  await tester.pumpAndSettle();
}

/// Customer with maps on, on the address step.
Future<AppHarness> _addressStep(
  WidgetTester tester, {
  FakeMapsRepository? maps,
  FakeLocationService? location,
  bool mapsEnabled = true,
  FakeBookingRepository? bookings,
}) async {
  useTallScreen(tester);
  final harness = customerHarness(
    maps: maps,
    location: location,
    mapsEnabled: mapsEnabled,
    bookings: bookings,
  );
  await harness.pump(tester);
  await startBooking(tester);
  return harness;
}

void main() {
  group('address step without maps', () {
    testWidgets('has no map button and says maps are off', (tester) async {
      await _addressStep(tester, mapsEnabled: false);

      expect(find.byKey(const ValueKey('pick-on-map')), findsNothing);
      expect(find.byKey(const ValueKey('use-my-location')), findsOneWidget);
      expect(find.textContaining('Maps are not switched on'), findsOneWidget);
      // The form itself is unchanged.
      expect(field('PIN code'), findsOneWidget);
      expect(field('House / flat, street and area'), findsOneWidget);
    });

    testWidgets('my location fills the form from the address lookup',
        (tester) async {
      final maps = FakeMapsRepository()..reverseResults = [bengaluruPlace()];
      await _addressStep(tester, maps: maps, mapsEnabled: false);

      await tapKey(tester, 'use-my-location');

      expect(maps.reverses, [const MapPoint(23.2599, 77.4126)]);
      expect(_text(tester, 'PIN code'), '560001');
      expect(
        _text(tester, 'House / flat, street and area'),
        '12 MG Road, Bengaluru, Karnataka 560001',
      );
      expect(find.byKey(const ValueKey('map-fallback')), findsOneWidget);
      expect(find.textContaining('23.259900,77.412600'), findsOneWidget);
    });

    testWidgets('an unavailable lookup keeps the position and the form',
        (tester) async {
      final maps = FakeMapsRepository()..reverseError = lookupUnavailable;
      await _addressStep(tester, maps: maps, mapsEnabled: false);

      await tapKey(tester, 'use-my-location');

      expect(find.byKey(const ValueKey('map-fallback')), findsOneWidget);
      expect(_text(tester, 'PIN code'), isEmpty);
      expect(_text(tester, 'House / flat, street and area'), isEmpty);

      // Typing the address still gets the booking going, pin included.
      await fillAddress(tester);
      await tapButton(tester, 'Continue');
      final address = _flowAddress(tester)!;
      expect(address.latitude, 23.2599);
      expect(address.longitude, 77.4126);
      expect(address.pincode, '560001');
    });

    testWidgets('the pin can be removed', (tester) async {
      final maps = FakeMapsRepository()..reverseResults = [bengaluruPlace()];
      await _addressStep(tester, maps: maps, mapsEnabled: false);
      await tapKey(tester, 'use-my-location');

      await tapKey(tester, 'remove-pin');

      expect(find.byKey(const ValueKey('map-fallback')), findsNothing);
      await fillAddress(tester);
      await tapButton(tester, 'Continue');
      expect(_flowAddress(tester)!.latitude, isNull);
      expect(_flowAddress(tester)!.longitude, isNull);
    });
  });

  group('location permission and services', () {
    testWidgets('blocked for good: explains and opens the settings',
        (tester) async {
      final location = FakeLocationService(
        const LocationFailed(LocationProblem.deniedForever),
      );
      await _addressStep(tester, location: location, mapsEnabled: false);

      await tapKey(tester, 'use-my-location');

      expect(
        find.text(locationProblemMessage(LocationProblem.deniedForever)),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('map-fallback')), findsNothing);
      await tapKey(tester, 'open-location-settings');
      expect(location.settingsOpened, [LocationProblem.deniedForever]);
    });

    testWidgets('location switched off offers the location settings',
        (tester) async {
      final location = FakeLocationService(
        const LocationFailed(LocationProblem.servicesOff),
      );
      await _addressStep(tester, location: location, mapsEnabled: false);

      await tapKey(tester, 'use-my-location');

      expect(
        find.text(locationProblemMessage(LocationProblem.servicesOff)),
        findsOneWidget,
      );
      await tapKey(tester, 'open-location-settings');
      expect(location.settingsOpened, [LocationProblem.servicesOff]);
    });

    testWidgets('a plain "no" or a timeout has no settings button',
        (tester) async {
      for (final problem in [LocationProblem.denied, LocationProblem.timeout]) {
        final location = FakeLocationService(LocationFailed(problem));
        await _addressStep(tester, location: location, mapsEnabled: false);

        await tapKey(tester, 'use-my-location');

        expect(find.text(locationProblemMessage(problem)), findsOneWidget);
        expect(find.byKey(const ValueKey('open-location-settings')), findsNothing);
        // The form still works: the customer can type the address.
        expect(field('PIN code'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('when the settings cannot be opened it says what to do',
        (tester) async {
      final location = FakeLocationService(
        const LocationFailed(LocationProblem.deniedForever),
      )..settingsCanOpen = false;
      await _addressStep(tester, location: location, mapsEnabled: false);

      await tapKey(tester, 'use-my-location');
      await tapKey(tester, 'open-location-settings');

      expect(
        find.text('Open your device settings and allow location for this app.'),
        findsOneWidget,
      );
    });

    testWidgets('trying again after a failure asks for the position again',
        (tester) async {
      final location = FakeLocationService(
        const LocationFailed(LocationProblem.timeout),
      );
      await _addressStep(tester, location: location, mapsEnabled: false);
      await tapKey(tester, 'use-my-location');

      // Pressing again after a failure tries again.
      await tapKey(tester, 'use-my-location');
      expect(location.calls, 2);
    });
  });

  group('map picker', () {
    testWidgets('moving the map looks up the address, and it is used',
        (tester) async {
      final maps = FakeMapsRepository()..reverseResults = [bengaluruPlace()];
      final harness = await _addressStep(tester, maps: maps);

      await tapKey(tester, 'pick-on-map');
      expect(find.text('Choose location'), findsOneWidget);
      expect(find.byKey(const ValueKey('center-pin')), findsOneWidget);
      expect(_enabled(tester, 'use-this-location'), isFalse);

      await _moveMap(tester, harness);
      expect(maps.reverses, [_moved]);
      expect(find.byKey(const ValueKey('picked-address')), findsOneWidget);
      expect(find.text('PIN 560001'), findsOneWidget);
      expect(find.text('We service this area'), findsOneWidget);
      expect(_enabled(tester, 'use-this-location'), isTrue);

      await tapKey(tester, 'use-this-location');

      expect(find.text('Choose location'), findsNothing);
      expect(_text(tester, 'PIN code'), '560001');
      expect(
        _text(tester, 'House / flat, street and area'),
        '12 MG Road, Bengaluru, Karnataka 560001',
      );
      expect(find.byKey(const ValueKey('map-preview')), findsOneWidget);
      expect(find.text('Change on map'), findsOneWidget);
    });

    testWidgets('the preview map is not interactive and marks the pin',
        (tester) async {
      final maps = FakeMapsRepository()..reverseResults = [bengaluruPlace()];
      final harness = await _addressStep(tester, maps: maps);
      await tapKey(tester, 'pick-on-map');
      await _moveMap(tester, harness);
      await tapKey(tester, 'use-this-location');

      final spec = harness.mapView.spec!;
      expect(spec.interactive, isFalse);
      expect(spec.marker, _moved);
    });

    testWidgets('nothing is chosen until the map is moved', (tester) async {
      final harness = await _addressStep(tester);
      await tapKey(tester, 'pick-on-map');

      expect(
        find.textContaining('Move the map to put the pin on your doorstep'),
        findsOneWidget,
      );
      expect(_enabled(tester, 'use-this-location'), isFalse);
      expect(harness.maps.reverses, isEmpty);
    });

    testWidgets('going back without choosing changes nothing', (tester) async {
      await _addressStep(tester);
      await tapKey(tester, 'pick-on-map');

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Choose location'), findsNothing);
      expect(find.byKey(const ValueKey('map-preview')), findsNothing);
      expect(_text(tester, 'PIN code'), isEmpty);
    });

    testWidgets('a PIN code we do not serve cannot be chosen', (tester) async {
      final maps = FakeMapsRepository()
        ..reverseResults = [
          bengaluruPlace(serviceable: false, pincode: '999999'),
        ];
      final harness = await _addressStep(tester, maps: maps);
      await tapKey(tester, 'pick-on-map');

      await _moveMap(tester, harness);

      expect(find.text('Not serviceable yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('blocked-note')), findsOneWidget);
      expect(_enabled(tester, 'use-this-location'), isFalse);

      // Moving to a serviceable spot unblocks it.
      maps.reverseResults = [bengaluruPlace()];
      await _moveMap(tester, harness, const MapPoint(12.97, 77.6));
      expect(find.byKey(const ValueKey('blocked-note')), findsNothing);
      expect(_enabled(tester, 'use-this-location'), isTrue);
    });

    testWidgets('a failed lookup still lets the pin be used', (tester) async {
      final maps = FakeMapsRepository()..reverseError = lookupUnavailable;
      final harness = await _addressStep(tester, maps: maps);
      await tapKey(tester, 'pick-on-map');

      await _moveMap(tester, harness);

      expect(find.textContaining(lookupUnavailableMessage), findsOneWidget);
      expect(find.textContaining('You can still use this pin'), findsOneWidget);
      expect(_enabled(tester, 'use-this-location'), isTrue);

      await tapKey(tester, 'use-this-location');
      expect(find.byKey(const ValueKey('map-preview')), findsOneWidget);
      expect(_text(tester, 'PIN code'), isEmpty);
      expect(_text(tester, 'House / flat, street and area'), isEmpty);
    });

    testWidgets('a spot with no address is still a valid pin', (tester) async {
      final harness = await _addressStep(tester);
      await tapKey(tester, 'pick-on-map');

      await _moveMap(tester, harness);

      expect(find.textContaining('No address found at this spot'), findsOneWidget);
      expect(_enabled(tester, 'use-this-location'), isTrue);
    });

    testWidgets('searching shows results, and a result moves the pin',
        (tester) async {
      final maps = FakeMapsRepository()
        ..searchResults = [bengaluruPlace()]
        ..reverseResults = [bengaluruPlace()];
      final harness = await _addressStep(tester, maps: maps);
      await tapKey(tester, 'pick-on-map');

      await tester.enterText(
        find.byKey(const ValueKey('map-search')),
        '  MG Road  ',
      );
      await tapKey(tester, 'map-search-go');
      expect(maps.searches, ['MG Road']);
      expect(find.byKey(const ValueKey('search-result-0')), findsOneWidget);

      await tapKey(tester, 'search-result-0');

      expect(find.byKey(const ValueKey('search-result-0')), findsNothing);
      expect(find.byKey(const ValueKey('picked-address')), findsOneWidget);
      expect(harness.mapView.animations, [const MapPoint(23.2599, 77.4126)]);
      // The result already carries its address: no second lookup for it.
      expect(maps.reverses, isEmpty);

      await tapKey(tester, 'use-this-location');
      expect(_text(tester, 'PIN code'), '560001');
    });

    testWidgets('a search needs at least three characters', (tester) async {
      final maps = FakeMapsRepository();
      await _addressStep(tester, maps: maps);
      await tapKey(tester, 'pick-on-map');

      await tester.enterText(find.byKey(const ValueKey('map-search')), 'MG');
      await tapKey(tester, 'map-search-go');

      expect(find.text('Type at least 3 characters to search.'), findsOneWidget);
      expect(maps.searches, isEmpty);
    });

    testWidgets('a search with no match says so', (tester) async {
      await _addressStep(tester);
      await tapKey(tester, 'pick-on-map');

      await tester.enterText(find.byKey(const ValueKey('map-search')), 'zzzzzz');
      await tapKey(tester, 'map-search-go');

      expect(find.textContaining('No matching address found'), findsOneWidget);
    });

    testWidgets('a failed search explains and keeps the map usable',
        (tester) async {
      final maps = FakeMapsRepository()..error = lookupUnavailable;
      await _addressStep(tester, maps: maps);
      await tapKey(tester, 'pick-on-map');

      await tester.enterText(find.byKey(const ValueKey('map-search')), 'MG Road');
      await tapKey(tester, 'map-search-go');

      expect(find.text(lookupUnavailableMessage), findsOneWidget);
      expect(find.byKey(const ValueKey('center-pin')), findsOneWidget);
    });

    testWidgets('a result in an area we do not serve is labelled',
        (tester) async {
      final maps = FakeMapsRepository()
        ..searchResults = [
          bengaluruPlace(serviceable: false, pincode: '999999'),
        ];
      await _addressStep(tester, maps: maps);
      await tapKey(tester, 'pick-on-map');

      await tester.enterText(find.byKey(const ValueKey('map-search')), 'MG Road');
      await tapKey(tester, 'map-search-go');
      expect(find.text('We do not service this PIN code yet'), findsOneWidget);

      await tapKey(tester, 'search-result-0');
      expect(_enabled(tester, 'use-this-location'), isFalse);
    });

    testWidgets('my location moves the map and looks up the address',
        (tester) async {
      final maps = FakeMapsRepository()..reverseResults = [bengaluruPlace()];
      final harness = await _addressStep(tester, maps: maps);
      await tapKey(tester, 'pick-on-map');

      await tapKey(tester, 'locate-me');

      expect(harness.location.calls, 1);
      expect(harness.mapView.animations, [const MapPoint(23.2599, 77.4126)]);
      expect(maps.reverses, [const MapPoint(23.2599, 77.4126)]);
      expect(find.byKey(const ValueKey('picked-address')), findsOneWidget);
      expect(_enabled(tester, 'use-this-location'), isTrue);
    });

    testWidgets('my location refused: explains, offers settings, keeps the map',
        (tester) async {
      final location = FakeLocationService(
        const LocationFailed(LocationProblem.deniedForever),
      );
      final harness = await _addressStep(tester, location: location);
      await tapKey(tester, 'pick-on-map');

      await tapKey(tester, 'locate-me');

      expect(
        find.text(locationProblemMessage(LocationProblem.deniedForever)),
        findsOneWidget,
      );
      expect(harness.mapView.animations, isEmpty);
      expect(_enabled(tester, 'use-this-location'), isFalse);
      await tapKey(tester, 'open-location-settings');
      expect(location.settingsOpened, [LocationProblem.deniedForever]);
      // The search box and the pin are still there.
      expect(find.byKey(const ValueKey('map-search')), findsOneWidget);
      expect(find.byKey(const ValueKey('center-pin')), findsOneWidget);
    });

    testWidgets('"Use my current location" opens the map at the phone position',
        (tester) async {
      final maps = FakeMapsRepository()..reverseResults = [bengaluruPlace()];
      await _addressStep(tester, maps: maps);

      await tapKey(tester, 'use-my-location');

      expect(find.text('Choose location'), findsOneWidget);
      expect(maps.reverses, [const MapPoint(23.2599, 77.4126)]);
      expect(find.byKey(const ValueKey('picked-address')), findsOneWidget);
      await tapKey(tester, 'use-this-location');
      expect(_text(tester, 'PIN code'), '560001');
      expect(find.byKey(const ValueKey('map-preview')), findsOneWidget);
    });

    testWidgets('a customer can open the picker directly, a driver cannot',
        (tester) async {
      useTallScreen(tester);
      final customer = customerHarness(mapsEnabled: true);
      await customer.pump(tester);
      goTo(tester, AppRoutes.pickLocation);
      await tester.pumpAndSettle();
      expect(find.text('Choose location'), findsOneWidget);
      expect(find.byKey(const ValueKey('map-search')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      final driver = AppHarness(role: UserRole.driver, mapsEnabled: true);
      await driver.pump(tester);
      goTo(tester, AppRoutes.pickLocation);
      await tester.pumpAndSettle();
      expect(find.text('Choose location'), findsNothing);
    });

    testWidgets('without a Maps key the picker explains instead of failing',
        (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      await harness.pump(tester);
      goTo(tester, AppRoutes.pickLocation);
      await tester.pumpAndSettle();

      expect(find.text('Choose location'), findsOneWidget);
      expect(find.textContaining('Maps are not switched on'), findsOneWidget);
      expect(find.byKey(const ValueKey('map-search')), findsNothing);
      expect(harness.mapView.builds, 0);
    });
  });

  group('address form with a pin', () {
    Future<AppHarness> pinned(WidgetTester tester) async {
      final maps = FakeMapsRepository()..reverseResults = [bengaluruPlace()];
      final harness = await _addressStep(tester, maps: maps);
      await tapKey(tester, 'pick-on-map');
      await _moveMap(tester, harness);
      await tapKey(tester, 'use-this-location');
      return harness;
    }

    testWidgets('continuing keeps the pin for the booking', (tester) async {
      await pinned(tester);

      await tapButton(tester, 'Continue');

      final address = _flowAddress(tester)!;
      expect(address.latitude, _moved.latitude);
      expect(address.longitude, _moved.longitude);
      expect(address.pincode, '560001');
      expect(address.addressLine, '12 MG Road, Bengaluru, Karnataka 560001');
    });

    testWidgets('changing the PIN code drops a pin that no longer fits',
        (tester) async {
      await pinned(tester);
      expect(find.byKey(const ValueKey('map-preview')), findsOneWidget);

      await enter(tester, 'PIN code', '560002');
      await tester.pump();

      expect(find.byKey(const ValueKey('map-preview')), findsNothing);
      expect(find.text('Pick on map'), findsOneWidget);
    });

    testWidgets('typing the same PIN code keeps the pin', (tester) async {
      await pinned(tester);

      await enter(tester, 'PIN code', '560 001');
      await tester.pump();

      expect(find.byKey(const ValueKey('map-preview')), findsOneWidget);
    });

    testWidgets('an address typed earlier is kept', (tester) async {
      final maps = FakeMapsRepository()..reverseResults = [bengaluruPlace()];
      final harness = await _addressStep(tester, maps: maps);
      await enter(tester, 'House / flat, street and area', 'Flat 4, Green Villa');

      await tapKey(tester, 'pick-on-map');
      await _moveMap(tester, harness);
      await tapKey(tester, 'use-this-location');

      expect(_text(tester, 'House / flat, street and area'), 'Flat 4, Green Villa');
      expect(_text(tester, 'PIN code'), '560001');
      expect(
        find.text('Location saved. The address you typed was kept.'),
        findsOneWidget,
      );
    });

    testWidgets('a pasted address fills in an empty PIN code', (tester) async {
      await _addressStep(tester, mapsEnabled: false);

      await enter(
        tester,
        'House / flat, street and area',
        'Flat 2, Indiranagar, Bengaluru 560 038',
      );
      await tester.pump();
      expect(_text(tester, 'PIN code'), '560038');

      // A PIN code the customer typed is never overwritten.
      await enter(tester, 'PIN code', '560001');
      await enter(
        tester,
        'House / flat, street and area',
        'Flat 2, Indiranagar, Bengaluru 560038',
      );
      await tester.pump();
      expect(_text(tester, 'PIN code'), '560001');
    });

    testWidgets('the pin travels to the server and shows on the summary',
        (tester) async {
      final harness = await pinned(tester);
      await tapButton(tester, 'Continue');
      await tapKey(tester, dayKey(tomorrow()));
      await tapKey(tester, 'slot-slot1');
      await tapButton(tester, 'Continue');

      expect(find.byKey(const ValueKey('map-preview')), findsOneWidget);
      await tapButton(tester, 'Confirm booking - ₹499');

      final draft = harness.bookingRepo.creates.single;
      expect(draft.latitude, _moved.latitude);
      expect(draft.longitude, _moved.longitude);
      expect(draft.pincode, '560001');
    });

    testWidgets('a booking without a pin sends none', (tester) async {
      useTallScreen(tester);
      final harness = customerHarness(mapsEnabled: true);
      await harness.pump(tester);
      await toSummary(tester);
      expect(find.byKey(const ValueKey('map-preview')), findsNothing);

      await tapButton(tester, 'Confirm booking - ₹499');

      final draft = harness.bookingRepo.creates.single;
      expect(draft.latitude, isNull);
      expect(draft.longitude, isNull);
    });
  });

  group('previous addresses', () {
    testWidgets('are offered with their pin and can be reused', (tester) async {
      final bookings = FakeBookingRepository(bookings: [
        booking(
          landmark: 'Gate 4',
          latitude: 12.97,
          longitude: 77.59,
        ),
      ]);
      await _addressStep(tester, bookings: bookings, mapsEnabled: false);

      expect(find.text('Use a previous address'), findsOneWidget);
      expect(find.text('PIN 560001 - map pin saved'), findsOneWidget);
      await tapKey(tester, 'previous-560001-12 MG Road');

      expect(_text(tester, 'PIN code'), '560001');
      expect(_text(tester, 'House / flat, street and area'), '12 MG Road');
      expect(_text(tester, 'Landmark (optional)'), 'Gate 4');
      expect(find.textContaining('12.970000,77.590000'), findsOneWidget);

      await tapButton(tester, 'Continue');
      final address = _flowAddress(tester)!;
      expect(address.latitude, 12.97);
      expect(address.longitude, 77.59);
    });

    testWidgets('an address without a pin brings no pin', (tester) async {
      final bookings = FakeBookingRepository(bookings: [booking()]);
      await _addressStep(tester, bookings: bookings);

      expect(find.text('PIN 560001'), findsOneWidget);
      await tapKey(tester, 'previous-560001-12 MG Road');

      expect(_text(tester, 'House / flat, street and area'), '12 MG Road');
      expect(find.byKey(const ValueKey('map-preview')), findsNothing);
      expect(find.byKey(const ValueKey('map-fallback')), findsNothing);
    });

    testWidgets('the same address is listed once, and at most four',
        (tester) async {
      final bookings = FakeBookingRepository(bookings: [
        booking(id: 'b1', number: 1, address: '12 MG Road'),
        booking(id: 'b2', number: 2, address: '12 mg road'),
        for (var i = 3; i <= 8; i++)
          booking(id: 'b$i', number: i, address: 'Road number $i'),
      ]);
      await _addressStep(tester, bookings: bookings);

      bool isPrevious(Widget w) {
        final key = w.key;
        return key is ValueKey<String> && key.value.startsWith('previous-');
      }

      expect(find.byWidgetPredicate(isPrevious), findsNWidgets(4));
      expect(find.byKey(const ValueKey('previous-560001-12 MG Road')), findsOneWidget);
    });

    testWidgets('a customer with no bookings sees no such section',
        (tester) async {
      await _addressStep(tester);
      expect(find.text('Use a previous address'), findsNothing);
    });

    testWidgets('a failure loading them does not get in the way',
        (tester) async {
      final bookings = FakeBookingRepository()..error = lookupUnavailable;
      await _addressStep(tester, bookings: bookings);

      expect(find.text('Use a previous address'), findsNothing);
      expect(field('PIN code'), findsOneWidget);
    });
  });

  group('changing a booking with a pin', () {
    FakeBookingRepository repo({bool pin = true}) =>
        FakeBookingRepository(bookings: [
          booking(
            date: DateTime(2020, 1, 1),
            latitude: pin ? 23.2599 : null,
            longitude: pin ? 77.4126 : null,
          ),
        ]);

    Future<AppHarness> openEdit(
      WidgetTester tester,
      FakeBookingRepository r, {
      FakeMapsRepository? maps,
    }) async {
      useTallScreen(tester);
      final harness = customerHarness(
        bookings: r,
        maps: maps,
        mapsEnabled: true,
      );
      await harness.pump(tester);
      goTo(tester, '/home/bookings/b1');
      await tester.pumpAndSettle();
      await tapText(tester, 'Change address or time');
      return harness;
    }

    testWidgets('shows the saved pin and sends nothing when unchanged',
        (tester) async {
      final r = repo();
      await openEdit(tester, r);

      expect(find.byKey(const ValueKey('map-preview')), findsOneWidget);
      expect(find.text('Change on map'), findsOneWidget);
      await tapButton(tester, 'Save');

      expect(find.text('No changes to save'), findsOneWidget);
      expect(r.lastUpdate, isNull);
    });

    testWidgets('removing the pin clears both coordinates', (tester) async {
      final r = repo();
      await openEdit(tester, r);

      await tapKey(tester, 'remove-pin');
      await tapButton(tester, 'Save');

      expect(r.lastUpdate, {'latitude': null, 'longitude': null});
    });

    testWidgets('a new PIN code without a new spot drops the old pin',
        (tester) async {
      final r = repo();
      await openEdit(tester, r);

      await enter(tester, 'PIN code', '560002');
      await tapButton(tester, 'Save');

      expect(r.lastUpdate, {
        'pincode': '560002',
        'latitude': null,
        'longitude': null,
      });
    });

    testWidgets('moving the pin sends the new coordinates only',
        (tester) async {
      final r = repo();
      final maps = FakeMapsRepository()..reverseResults = [bengaluruPlace()];
      final harness = await openEdit(tester, r, maps: maps);

      await tapKey(tester, 'pick-on-map');
      // The picker starts from the saved pin.
      expect(maps.reverses, [const MapPoint(23.2599, 77.4126)]);
      await _moveMap(tester, harness);
      await tapKey(tester, 'use-this-location');
      await tapButton(tester, 'Save');

      expect(r.lastUpdate, {
        'latitude': _moved.latitude,
        'longitude': _moved.longitude,
      });
    });

    testWidgets('a spot in another PIN code updates the PIN code too',
        (tester) async {
      final r = repo();
      final maps = FakeMapsRepository()
        ..reverseResults = [bengaluruPlace(pincode: '560002')];
      final harness = await openEdit(tester, r, maps: maps);

      await tapKey(tester, 'pick-on-map');
      await _moveMap(tester, harness);
      await tapKey(tester, 'use-this-location');
      expect(find.text('PIN code set to 560002 to match the location'), findsOneWidget);
      await tapButton(tester, 'Save');

      expect(r.lastUpdate, {
        'pincode': '560002',
        'latitude': _moved.latitude,
        'longitude': _moved.longitude,
      });
    });

    testWidgets('a booking without a pin can get one', (tester) async {
      final r = repo(pin: false);
      final maps = FakeMapsRepository()..reverseResults = [bengaluruPlace()];
      final harness = await openEdit(tester, r, maps: maps);
      expect(find.byKey(const ValueKey('map-preview')), findsNothing);

      await tapKey(tester, 'pick-on-map');
      await _moveMap(tester, harness);
      await tapKey(tester, 'use-this-location');
      await tapButton(tester, 'Save');

      expect(r.lastUpdate, {
        'latitude': _moved.latitude,
        'longitude': _moved.longitude,
      });
    });
  });

  group('showing a booking location', () {
    FakeBookingRepository pinnedBooking() => FakeBookingRepository(
          bookings: [booking(latitude: 23.2599, longitude: 77.4126)],
        );

    Future<AppHarness> openDetail(
      WidgetTester tester,
      FakeBookingRepository r, {
      bool mapsEnabled = true,
    }) async {
      useTallScreen(tester);
      final harness = customerHarness(bookings: r, mapsEnabled: mapsEnabled);
      await harness.pump(tester);
      goTo(tester, '/home/bookings/b1');
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('a map preview and an "Open in Maps" button', (tester) async {
      final harness = await openDetail(tester, pinnedBooking());

      expect(find.byKey(const ValueKey('map-preview')), findsOneWidget);
      expect(harness.mapView.spec!.marker, const MapPoint(23.2599, 77.4126));
      expect(harness.mapView.interactive, isFalse);
      await tapKey(tester, 'open-in-maps');
      expect(harness.contactLauncher.opened, ['map:23.259900,77.412600']);
    });

    testWidgets('without a Maps key the coordinates and the button remain',
        (tester) async {
      final harness =
          await openDetail(tester, pinnedBooking(), mapsEnabled: false);

      expect(find.byKey(const ValueKey('map-preview')), findsNothing);
      expect(find.byKey(const ValueKey('map-fallback')), findsOneWidget);
      expect(find.text('Pinned location: 23.259900,77.412600'), findsOneWidget);
      expect(harness.mapView.builds, 0);
      await tapKey(tester, 'open-in-maps');
      expect(harness.contactLauncher.opened, ['map:23.259900,77.412600']);
    });

    testWidgets('a booking without a pin shows no location block',
        (tester) async {
      await openDetail(tester, FakeBookingRepository(bookings: [booking()]));

      expect(find.byKey(const ValueKey('map-preview')), findsNothing);
      expect(find.byKey(const ValueKey('map-fallback')), findsNothing);
      expect(find.byKey(const ValueKey('open-in-maps')), findsNothing);
    });

    testWidgets('if no maps app opens, the coordinates are shown',
        (tester) async {
      final harness = await openDetail(tester, pinnedBooking());
      harness.contactLauncher.canOpen = false;

      await tapKey(tester, 'open-in-maps');

      expect(
        find.text("Couldn't open maps on this device. Location: 23.259900,77.412600"),
        findsOneWidget,
      );
    });

    testWidgets('the admin sees the pin too', (tester) async {
      useTallScreen(tester);
      final harness = AppHarness(
        role: UserRole.admin,
        mapsEnabled: true,
        adminBookings: FakeAdminBookingRepository(bookings: [
          booking(latitude: 23.2599, longitude: 77.4126),
        ]),
      );
      await harness.pump(tester);
      goTo(tester, AppRoutes.adminBooking('b1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('map-preview')), findsOneWidget);
      await tapKey(tester, 'open-in-maps');
      expect(harness.contactLauncher.opened, ['map:23.259900,77.412600']);
    });
  });

  group('driver job', () {
    Future<AppHarness> openJob(
      WidgetTester tester, {
      double? latitude,
      double? longitude,
      bool mapsEnabled = true,
    }) async {
      useTallScreen(tester);
      final harness = AppHarness(
        role: UserRole.driver,
        mapsEnabled: mapsEnabled,
        driverWork: FakeDriverWorkRepository(jobs: [
          driverJob(latitude: latitude, longitude: longitude),
        ]),
      );
      await harness.pump(tester);
      goTo(tester, AppRoutes.driverBooking('b1'));
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('shows the customer location and navigates to the coordinates',
        (tester) async {
      final harness =
          await openJob(tester, latitude: 23.2599, longitude: 77.4126);

      expect(find.byKey(const ValueKey('map-preview')), findsOneWidget);
      await tapKey(tester, 'navigate');
      expect(harness.contactLauncher.opened, ['directions:23.2599,77.4126']);
    });

    testWidgets('the driver can also open the pin in their maps app',
        (tester) async {
      final harness =
          await openJob(tester, latitude: 23.2599, longitude: 77.4126);

      await tapKey(tester, 'open-in-maps');

      expect(harness.contactLauncher.opened, ['map:23.259900,77.412600']);
    });

    testWidgets('without a Maps key navigation still works', (tester) async {
      final harness = await openJob(
        tester,
        latitude: 23.2599,
        longitude: 77.4126,
        mapsEnabled: false,
      );

      expect(find.byKey(const ValueKey('map-preview')), findsNothing);
      expect(find.byKey(const ValueKey('map-fallback')), findsOneWidget);
      await tapKey(tester, 'navigate');
      expect(harness.contactLauncher.opened, ['directions:23.2599,77.4126']);
    });

    testWidgets('a job without a pin navigates to the written address',
        (tester) async {
      final harness = await openJob(tester);

      expect(find.byKey(const ValueKey('map-preview')), findsNothing);
      expect(find.byKey(const ValueKey('map-fallback')), findsNothing);
      await tapKey(tester, 'navigate');
      expect(
        harness.contactLauncher.opened,
        ['directions:12 MG Road, Bengaluru 560001'],
      );
    });

    testWidgets('if navigation cannot open, the address is shown',
        (tester) async {
      final harness = await openJob(tester);
      harness.contactLauncher.canOpen = false;

      await tapKey(tester, 'navigate');

      expect(
        find.text(
          "Couldn't open that on this device. "
          'Address: 12 MG Road, Bengaluru 560001',
        ),
        findsOneWidget,
      );
    });
  });
}
