import 'package:ff_garage/core/config/app_config.dart';
import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/core/utils/validators.dart';
import 'package:ff_garage/data/models/booking.dart';
import 'package:ff_garage/data/models/place.dart';
import 'package:ff_garage/data/repositories/booking_repository.dart';
import 'package:ff_garage/data/repositories/maps_repository.dart';
import 'package:ff_garage/data/services/booking_api_service.dart';
import 'package:ff_garage/data/services/maps_api_service.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_api.dart';

Map<String, dynamic> _placeJson({
  Object? latitude = 23.2599,
  Object? longitude = 77.4126,
  Object? serviceable = true,
}) =>
    {
      'formatted_address': '12 MG Road, Bhopal 462001, India',
      'latitude': latitude,
      'longitude': longitude,
      'pincode': '462001',
      'area_name': 'New Market',
      'city': 'Bhopal',
      'state': 'Madhya Pradesh',
      'serviceable': serviceable,
    };

MapsRepository _repo(StubApi api) => MapsRepository(MapsApiService(api.client));

Map<String, dynamic> _bookingJson({Object? latitude, Object? longitude}) => {
      'id': 'b1',
      'booking_number': 1,
      'booking_code': 'FF-000001',
      'status': 'confirmed',
      'vehicle_type': 'scooter',
      'service_id': 's1',
      'package_id': 'p1',
      'service_name': 'General Service',
      'package_name': 'Basic',
      'package_inclusions': <String>[],
      'estimated_duration_minutes': null,
      'customer_name': 'Asha',
      'customer_phone': '+919876543210',
      'address_line': '12 MG Road',
      'landmark': null,
      'latitude': latitude,
      'longitude': longitude,
      'city': 'Bhopal',
      'state': null,
      'pincode': '462001',
      'scheduled_date': '2026-10-21',
      'slot_start': '09:00:00',
      'slot_end': '11:00:00',
      'package_price': '499.00',
      'extra_charges_total': '0.00',
      'total_amount': '499.00',
      'extra_charges': <Object>[],
      'customer_notes': null,
      'cancellation_reason': null,
      'created_at': '2026-10-19T08:00:00+05:30',
      'can_cancel': true,
      'can_modify': true,
      'cancel_blocked_reason': null,
    };

NewBooking _draft({double? latitude, double? longitude}) => NewBooking(
      packageId: 'p1',
      extraChargeIds: const [],
      pincode: '462001',
      addressLine: '12 MG Road',
      date: DateTime(2026, 10, 21),
      timeSlotId: 'slot1',
      expectedTotal: 499,
      clientRequestId: '11111111-1111-4111-8111-111111111111',
      latitude: latitude,
      longitude: longitude,
    );

void main() {
  group('Place.fromJson', () {
    test('reads every field', () {
      final place = Place.fromJson(_placeJson());
      expect(place.formattedAddress, '12 MG Road, Bhopal 462001, India');
      expect(place.point, const MapPoint(23.2599, 77.4126));
      expect(place.pincode, '462001');
      expect(place.areaName, 'New Market');
      expect(place.city, 'Bhopal');
      expect(place.state, 'Madhya Pradesh');
      expect(place.serviceable, isTrue);
    });

    test('a place without a PIN code or service verdict is still valid', () {
      final json = _placeJson(serviceable: null)
        ..['pincode'] = null
        ..['city'] = null;
      final place = Place.fromJson(json);
      expect(place.pincode, isNull);
      expect(place.city, isNull);
      expect(place.serviceable, isNull);
    });

    test('coordinates may arrive as whole numbers', () {
      final place = Place.fromJson(_placeJson(latitude: 23, longitude: 77));
      expect(place.point, const MapPoint(23, 77));
    });

    test('a place without coordinates is rejected', () {
      expect(
        () => Place.fromJson(_placeJson(latitude: null)),
        throwsFormatException,
      );
      expect(
        () => Place.fromJson(_placeJson(longitude: null)),
        throwsFormatException,
      );
    });

    test('a service verdict that is not true/false is rejected', () {
      expect(
        () => Place.fromJson(_placeJson(serviceable: 'yes')),
        throwsFormatException,
      );
    });
  });

  group('MapPoint', () {
    test('formats as a Google Maps query with six decimals', () {
      expect(const MapPoint(12.9716, 77.5946).asQuery, '12.971600,77.594600');
    });

    test('compares by value', () {
      expect(const MapPoint(1, 2), const MapPoint(1, 2));
      expect(const MapPoint(1, 2), isNot(const MapPoint(1, 3)));
    });
  });

  group('MapsRepository', () {
    test('search sends the trimmed text and parses the places', () async {
      final api = StubApi((_) => (
            200,
            {
              'results': [_placeJson()],
            },
          ));
      final places = await _repo(api).search('  MG Road Bhopal ');

      expect(api.last.method, 'GET');
      expect(api.last.path, '/maps/geocode');
      expect(api.last.query, {'q': 'MG Road Bhopal'});
      expect(places, hasLength(1));
      expect(places.single.pincode, '462001');
    });

    test('reverse sends the coordinates', () async {
      final api = StubApi((_) => (200, {'results': <Object>[]}));
      final places = await _repo(api).reverse(const MapPoint(23.2599, 77.4126));

      expect(api.last.path, '/maps/reverse');
      expect(api.last.query, {'latitude': 23.2599, 'longitude': 77.4126});
      expect(places, isEmpty);
    });

    test('a malformed answer becomes an invalid-response error', () async {
      for (final body in <Object?>[
        {'results': 'nope'},
        {
          'results': [
            {'formatted_address': 'x'},
          ],
        },
        {
          'results': [42],
        },
      ]) {
        final api = StubApi((_) => (200, body));
        await expectLater(
          _repo(api).search('MG Road'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.type, 'type', ApiErrorType.invalidResponse),
          ),
          reason: '$body',
        );
      }
    });

    test('a server failure says that typing the address still works', () async {
      final api = StubApi((_) => (503, {'detail': 'raw upstream detail'}));
      await expectLater(
        _repo(api).search('MG Road'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.server)
              .having((e) => e.message, 'message', lookupUnavailableMessage)
              .having((e) => e.statusCode, 'status', 503),
        ),
      );
    });

    test('other failures keep their own message', () async {
      final api = StubApi((_) => (403, {'detail': 'Customers only'}));
      await expectLater(
        _repo(api).reverse(const MapPoint(1, 2)),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.forbidden)
              .having((e) => e.message, 'message', 'Customers only'),
        ),
      );
    });

    test('too many searches is reported with the server wording', () async {
      final api = StubApi((_) => (429, {'detail': 'Too many address lookups.'}));
      await expectLater(
        _repo(api).search('MG Road'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 429)
              .having((e) => e.message, 'message', 'Too many address lookups.'),
        ),
      );
    });
  });

  group('bookings carry a location', () {
    test('Booking reads latitude and longitude', () {
      final booking =
          Booking.fromJson(_bookingJson(latitude: 23.2599, longitude: 77.4126));
      expect(booking.hasLocation, isTrue);
      expect(booking.latitude, 23.2599);
      expect(booking.longitude, 77.4126);
    });

    test('a booking without a pin has no location', () {
      final booking = Booking.fromJson(_bookingJson());
      expect(booking.hasLocation, isFalse);
      expect(booking.latitude, isNull);
    });

    test('create sends the pin when both coordinates are set', () async {
      final api = StubApi((_) => (201, _bookingJson()));
      await BookingRepository(BookingApiService(api.client))
          .create(_draft(latitude: 23.2599, longitude: 77.4126));
      final body = api.last.body! as Map<String, dynamic>;
      expect(body['latitude'], 23.2599);
      expect(body['longitude'], 77.4126);
    });

    test('create never sends half a pin', () async {
      final api = StubApi((_) => (201, _bookingJson()));
      final repo = BookingRepository(BookingApiService(api.client));
      await repo.create(_draft(latitude: 23.2599));
      var body = api.last.body! as Map<String, dynamic>;
      expect(body.containsKey('latitude'), isFalse);
      expect(body.containsKey('longitude'), isFalse);

      await repo.create(_draft());
      body = api.last.body! as Map<String, dynamic>;
      expect(body.containsKey('latitude'), isFalse);
    });
  });

  group('Validators.extractPincode', () {
    test('finds the PIN code at the end of an address', () {
      expect(
        Validators.extractPincode('12 MG Road, Bhopal, Madhya Pradesh 462001'),
        '462001',
      );
    });

    test('accepts the spaced form and removes the space', () {
      expect(Validators.extractPincode('Indiranagar, Bengaluru 560 038'), '560038');
    });

    test('the last match wins: a PIN code ends an address', () {
      expect(Validators.extractPincode('Plot 400001, Sector 5, Pune 411001'), '411001');
    });

    test('a phone number or a long number is not a PIN code', () {
      expect(Validators.extractPincode('Call 9876543210 after 5'), isNull);
      expect(Validators.extractPincode('Flat 1234567'), isNull);
    });

    test('a PIN code cannot start with zero', () {
      expect(Validators.extractPincode('House 012345'), isNull);
    });

    test('no PIN code gives null', () {
      expect(Validators.extractPincode('Near the temple'), isNull);
      expect(Validators.extractPincode(''), isNull);
    });
  });

  group('AppConfig platform keys', () {
    AppConfig config({
      String web = '',
      String android = '',
      String ios = '',
      String mapsWeb = '',
      String mapsAndroid = '',
      String mapsIos = '',
    }) =>
        AppConfig(
          apiBaseUrl: 'http://api.test/api/v1',
          supabaseUrl: 'https://p.supabase.co',
          supabaseAnonKey: 'anon',
          googleClientIdWeb: web,
          googleClientIdAndroid: android,
          googleClientIdIos: ios,
          mapsKeyWeb: mapsWeb,
          mapsKeyAndroid: mapsAndroid,
          mapsKeyIos: mapsIos,
        );

    test('maps need the key of the platform being run', () {
      final c = config(mapsAndroid: 'a');
      expect(c.mapsConfigured(isWeb: false, platform: TargetPlatform.android), isTrue);
      expect(c.mapsConfigured(isWeb: false, platform: TargetPlatform.iOS), isFalse);
      expect(c.mapsConfigured(isWeb: true, platform: TargetPlatform.android), isFalse);
      expect(c.mapsConfigured(isWeb: false, platform: TargetPlatform.linux), isFalse);
    });

    test('web and iOS maps use their own keys', () {
      final c = config(mapsWeb: 'w', mapsIos: 'i');
      expect(c.mapsConfigured(isWeb: true, platform: TargetPlatform.android), isTrue);
      expect(c.mapsConfigured(isWeb: false, platform: TargetPlatform.iOS), isTrue);
      expect(c.mapsConfigured(isWeb: false, platform: TargetPlatform.android), isFalse);
    });

    test('Google sign-in on Android needs the web and Android client IDs', () {
      expect(
        config(web: 'w').googleSignInConfigured(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
      expect(
        config(web: 'w', android: 'a').googleSignInConfigured(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
    });

    test('Google sign-in on iOS needs the web and iOS client IDs', () {
      expect(
        config(web: 'w', android: 'a').googleSignInConfigured(
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        isFalse,
      );
      expect(
        config(web: 'w', ios: 'i').googleSignInConfigured(
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        isTrue,
      );
    });

    test('Google sign-in on the web needs only Supabase', () {
      expect(
        config().googleSignInConfigured(
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
    });

    test('placeholders from .env.example count as not set', () {
      final c = AppConfig.fromMap({
        'SUPABASE_URL': 'https://p.supabase.co',
        'SUPABASE_ANON_KEY': 'anon',
        'GOOGLE_CLIENT_ID_WEB': 'YOUR-WEB-CLIENT-ID.apps.googleusercontent.com',
        'GOOGLE_MAPS_KEY_ANDROID': 'YOUR-ANDROID-MAPS-KEY',
        'GOOGLE_MAPS_KEY_IOS': 'AIzaRealLookingKey',
      });
      expect(c.googleClientIdWeb, isEmpty);
      expect(c.mapsKeyAndroid, isEmpty);
      expect(c.mapsKeyIos, 'AIzaRealLookingKey');
    });
  });
}
