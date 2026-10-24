import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/models/support_contact.dart';
import 'package:ff_garage/data/repositories/support_repository.dart';
import 'package:ff_garage/data/services/support_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_api.dart';

void main() {
  group('SupportContact', () {
    test('reads every field', () {
      final c = SupportContact.fromJson({
        'name': 'F&F',
        'phone': '+919876543210',
        'whatsapp': '919876543210',
        'email': 'a@b.com',
        'address': '12 Main Road',
        'hours': '9-7',
      });
      expect(c.hasPhone && c.hasWhatsapp && c.hasEmail, isTrue);
      expect(c.hasAddress && c.hasHours && c.hasAnyContact, isTrue);
    });

    test('empty strings mean "not configured"', () {
      final c = SupportContact.fromJson({
        'name': 'F&F',
        'phone': '',
        'whatsapp': '',
        'email': '',
        'address': '',
        'hours': '',
      });
      expect(c.hasAnyContact, isFalse);
      expect(c.hasHours, isFalse);
    });

    test('hours alone are not a way to contact the garage', () {
      final c = SupportContact.fromJson({'name': 'F&F', 'hours': '9-7'});
      expect(c.hasHours, isTrue);
      expect(c.hasAnyContact, isFalse);
    });

    test('a wrongly typed field is rejected', () {
      expect(
        () => SupportContact.fromJson({'name': 'F&F', 'phone': 5}),
        throwsFormatException,
      );
    });
  });

  group('SupportRepository', () {
    test('calls GET /support/contact and maps the answer', () async {
      final api = StubApi((_) => (
            200,
            {
              'name': 'F&F',
              'phone': '+919876543210',
              'whatsapp': '',
              'email': '',
              'address': '',
              'hours': '',
            }
          ));
      final repo = SupportRepository(SupportApiService(api.client));

      final c = await repo.contact();

      expect(api.last.method, 'GET');
      expect(api.last.path, '/support/contact');
      expect(c.phone, '+919876543210');
    });

    test('turns an unreadable answer into an invalidResponse error', () async {
      final api = StubApi((_) => (200, {'name': 'F&F', 'phone': 5}));
      final repo = SupportRepository(SupportApiService(api.client));

      await expectLater(
        repo.contact(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.invalidResponse),
        ),
      );
    });
  });
}
