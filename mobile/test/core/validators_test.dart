import 'package:ff_garage/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('email', () {
    test('accepts normal addresses', () {
      expect(Validators.email('a@b.co'), isNull);
      expect(Validators.email('  first.last+tag@example.com '), isNull);
    });
    test('rejects empty and malformed', () {
      expect(Validators.email(null), isNotNull);
      expect(Validators.email('  '), isNotNull);
      expect(Validators.email('no-at-sign'), isNotNull);
      expect(Validators.email('a@b'), isNotNull);
      expect(Validators.email('a b@c.com'), isNotNull);
    });
  });

  group('passwords', () {
    test('sign-in only requires something', () {
      expect(Validators.requiredPassword('x'), isNull);
      expect(Validators.requiredPassword(''), isNotNull);
      expect(Validators.requiredPassword(null), isNotNull);
    });
    test('new password enforces length and non-blank', () {
      expect(Validators.newPassword('1234567'), isNotNull);
      expect(Validators.newPassword('12345678'), isNull);
      expect(Validators.newPassword('a' * 72), isNull);
      expect(Validators.newPassword('a' * 73), isNotNull);
      expect(Validators.newPassword('        '), isNotNull);
    });
    test('confirmation must match', () {
      expect(Validators.confirmPassword('abc12345', 'abc12345'), isNull);
      expect(Validators.confirmPassword('abc12346', 'abc12345'), isNotNull);
      expect(Validators.confirmPassword('', 'abc12345'), isNotNull);
    });
  });

  group('name', () {
    test('trims and collapses whitespace before checking', () {
      expect(Validators.fullName('  Asha   Rao '), isNull);
      expect(Validators.normalizeName('  Asha   Rao '), 'Asha Rao');
      expect(Validators.fullName(' A '), isNotNull);
      expect(Validators.fullName(''), isNotNull);
      expect(Validators.fullName('a' * 121), isNotNull);
    });
  });

  group('phone', () {
    test('normalises Indian mobiles to +91', () {
      expect(Validators.normalizedMobile('9876543210'), '+919876543210');
      expect(Validators.normalizedMobile('98765 43210'), '+919876543210');
      expect(Validators.normalizedMobile('09876543210'), '+919876543210');
      expect(Validators.normalizedMobile('919876543210'), '+919876543210');
      expect(Validators.normalizedMobile('+91-98765-43210'), '+919876543210');
    });
    test('rejects everything else', () {
      expect(Validators.normalizedMobile('1234567890'), isNull);
      expect(Validators.normalizedMobile('98765'), isNull);
      expect(Validators.normalizedMobile('abcdefghij'), isNull);
      expect(Validators.normalizedMobile(null), isNull);
      expect(Validators.phone(''), isNotNull);
      expect(Validators.phone('9876543210'), isNull);
    });
  });

  group('driver id', () {
    test('is case-insensitive and mirrors the backend pattern', () {
      expect(Validators.driverId('Ravi01'), isNull);
      expect(Validators.normalizeDriverId(' Ravi01 '), 'ravi01');
      expect(Validators.driverId('ab'), isNotNull);
      expect(Validators.driverId('-ravi'), isNotNull);
      expect(Validators.driverId('ra vi'), isNotNull);
      expect(Validators.driverId('ravi@x.com'), isNotNull);
      expect(Validators.driverId('a' * 33), isNotNull);
      expect(Validators.driverId(''), isNotNull);
    });
  });
}
