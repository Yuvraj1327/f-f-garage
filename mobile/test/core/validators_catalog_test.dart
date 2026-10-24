import 'package:ff_garage/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('price', () {
    test('accepts whole and two-decimal amounts, including zero', () {
      for (final ok in ['0', '499', '499.5', '499.50', '1000000', ' 10 ']) {
        expect(Validators.price(ok), isNull, reason: ok);
      }
    });
    test('rejects everything else', () {
      for (final bad in [
        '', '  ', '-1', '10.999', '1000000.01', 'abc', '1,000', '1e3', '.5',
        '₹100', '99999999',
      ]) {
        expect(Validators.price(bad), isNotNull, reason: bad);
      }
      expect(Validators.price(null), isNotNull);
    });
    test('optional amount allows empty (charged at actuals)', () {
      expect(Validators.optionalAmount(''), isNull);
      expect(Validators.optionalAmount(null), isNull);
      expect(Validators.optionalAmount('350'), isNull);
      expect(Validators.optionalAmount('-5'), isNotNull);
      expect(Validators.parseAmount(' 350.5 '), 350.5);
      expect(Validators.parseAmount(''), isNull);
    });
  });

  group('numbers', () {
    test('duration is 5-1440 whole minutes or empty', () {
      expect(Validators.optionalDuration(''), isNull);
      expect(Validators.optionalDuration('5'), isNull);
      expect(Validators.optionalDuration('1440'), isNull);
      for (final bad in ['4', '1441', '1.5', 'x', '-10']) {
        expect(Validators.optionalDuration(bad), isNotNull, reason: bad);
      }
    });
    test('display order is 0-10000 or empty', () {
      expect(Validators.displayOrder(''), isNull);
      expect(Validators.displayOrder('0'), isNull);
      expect(Validators.displayOrder('10000'), isNull);
      for (final bad in ['-1', '10001', 'a', '1.5']) {
        expect(Validators.displayOrder(bad), isNotNull, reason: bad);
      }
    });
    test('capacity is 1-50', () {
      expect(Validators.capacity('1'), isNull);
      expect(Validators.capacity('50'), isNull);
      for (final bad in ['0', '51', '', 'x', '2.5']) {
        expect(Validators.capacity(bad), isNotNull, reason: bad);
      }
    });
  });

  group('pincode', () {
    test('six digits, not starting with 0, spaces ignored', () {
      expect(Validators.pincode('462001'), isNull);
      expect(Validators.pincode('462 001'), isNull);
      expect(Validators.normalizePincode('462 001'), '462001');
      for (final bad in ['', '46200', '4620011', '062001', 'abcdef', '46200a']) {
        expect(Validators.pincode(bad), isNotNull, reason: bad);
      }
      expect(Validators.pincode(null), isNotNull);
    });
  });

  group('text', () {
    test('required text enforces length after collapsing whitespace', () {
      expect(Validators.requiredText('  Ab  ', label: 'name', max: 5), isNull);
      expect(Validators.requiredText('A', label: 'name', max: 5), isNotNull);
      expect(Validators.requiredText('abcdef', label: 'name', max: 5), isNotNull);
      expect(Validators.requiredText('   ', label: 'name', max: 5), isNotNull);
      expect(Validators.requiredText(null, label: 'name', max: 5), isNotNull);
    });
    test('optional text only checks the maximum', () {
      expect(Validators.optionalText('', label: 'note', max: 3), isNull);
      expect(Validators.optionalText(null, label: 'note', max: 3), isNull);
      expect(Validators.optionalText('abcd', label: 'note', max: 3), isNotNull);
    });
  });

  test('slot order requires the end after the start', () {
    expect(Validators.slotOrder(540, 660), isNull);
    expect(Validators.slotOrder(540, 540), isNotNull);
    expect(Validators.slotOrder(660, 540), isNotNull);
  });
}
