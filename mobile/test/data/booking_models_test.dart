import 'package:ff_garage/data/models/booking.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({Map<String, dynamic> override = const {}}) => {
      'id': 'b1',
      'booking_number': 12,
      'booking_code': 'FF-000012',
      'status': 'pending_payment',
      'vehicle_type': 'scooter',
      'service_id': 's1',
      'package_id': 'p1',
      'service_name': 'General Service',
      'package_name': 'Basic',
      'package_inclusions': ['Wash', 'Oil top-up'],
      'estimated_duration_minutes': 90,
      'customer_name': 'Asha',
      'customer_phone': '+919876543210',
      'address_line': '12 MG Road',
      'landmark': null,
      'city': 'Bhopal',
      'state': 'Madhya Pradesh',
      'pincode': '462001',
      'latitude': null,
      'longitude': null,
      'scheduled_date': '2026-10-21',
      'slot_start': '09:00:00',
      'slot_end': '11:00:00',
      'package_price': '499.00',
      'extra_charges_total': '350.00',
      'total_amount': '849.00',
      'extra_charges': [
        {
          'id': 'x1',
          'extra_charge_id': 'c1',
          'charge_type': 'engine_oil',
          'name': 'Engine oil',
          'amount': '350.00',
          'included_in_total': true,
        },
        {
          'id': 'x2',
          'extra_charge_id': 'c2',
          'charge_type': 'spare_part',
          'name': 'Air filter',
          'amount': null,
          'included_in_total': false,
        },
      ],
      'customer_notes': null,
      'cancellation_reason': null,
      'confirmed_at': null,
      'completed_at': null,
      'cancelled_at': null,
      'created_at': '2026-10-19T08:00:00+05:30',
      'can_cancel': true,
      'can_modify': false,
      'cancel_blocked_reason': null,
      ...override,
    };

void main() {
  group('Booking.fromJson', () {
    test('reads every field the API sends', () {
      final b = Booking.fromJson(_json());
      expect(b.code, 'FF-000012');
      expect(b.status, BookingStatus.pendingPayment);
      expect(b.date, DateTime(2026, 10, 21));
      expect(b.timeLabel, '9:00 AM - 11:00 AM');
      expect(b.packagePrice, 499);
      expect(b.totalAmount, 849);
      expect(b.durationMinutes, 90);
      expect(b.inclusions, ['Wash', 'Oil top-up']);
      expect(b.canCancel, isTrue);
      expect(b.canModify, isFalse);
    });

    test('splits chosen add-ons from ones that only may apply', () {
      final b = Booking.fromJson(_json());
      expect(b.chosenCharges.map((c) => c.name), ['Engine oil']);
      expect(b.possibleCharges.map((c) => c.name), ['Air filter']);
      expect(b.possibleCharges.single.amount, isNull);
    });

    test('accepts money as numbers too', () {
      final b = Booking.fromJson(_json(override: {
        'package_price': 499,
        'extra_charges_total': 350.5,
        'total_amount': 849.5,
      }));
      expect(b.totalAmount, 849.5);
    });

    test('a cancelled booking is flagged', () {
      final b = Booking.fromJson(_json(override: {
        'status': 'cancelled',
        'cancellation_reason': 'Changed my mind',
        'can_cancel': false,
      }));
      expect(b.isCancelled, isTrue);
      expect(b.cancellationReason, 'Changed my mind');
    });

    test('rejects a malformed response with a FormatException', () {
      for (final broken in <Map<String, dynamic>>[
        {'status': 'teleported'},
        {'booking_number': '12'},
        {'scheduled_date': 'tomorrow'},
        {'slot_start': '9am'},
        {'total_amount': 'lots'},
        {'extra_charges': 'none'},
        {'can_cancel': 'yes'},
        {'created_at': 'sometime'},
        {'id': null},
      ]) {
        expect(
          () => Booking.fromJson(_json(override: broken)),
          throwsFormatException,
          reason: '$broken',
        );
      }
    });
  });

  group('BookingPage', () {
    Map<String, dynamic> page(int count, int total, int offset) => {
          'items': [for (var i = 0; i < count; i++) _json(override: {'id': 'b$i'})],
          'total': total,
          'limit': 20,
          'offset': offset,
        };

    test('knows when there are more pages', () {
      expect(BookingPage.fromJson(page(20, 45, 0)).hasMore, isTrue);
      expect(BookingPage.fromJson(page(5, 45, 40)).hasMore, isFalse);
      expect(BookingPage.fromJson(page(0, 0, 0)).hasMore, isFalse);
    });
  });

  group('BookingQuote', () {
    BookingQuote quote(double price, List<double?> amounts) => BookingQuote(
          serviceId: 's',
          serviceName: 'S',
          vehicleType: VehicleType.bike,
          packageId: 'p',
          packageName: 'P',
          inclusions: const [],
          packagePrice: price,
          charges: [
            for (var i = 0; i < amounts.length; i++)
              QuoteCharge(
                id: 'c$i',
                chargeType: ExtraChargeType.other,
                name: 'Charge $i',
                amount: amounts[i],
                selectable: amounts[i] != null,
              ),
          ],
        );

    test('totals the package and the chosen add-ons exactly', () {
      final q = quote(499.99, [350.10, 0.05, null]);
      expect(q.totalFor({}), 499.99);
      expect(q.totalFor({'c0'}), 850.09);
      expect(q.totalFor({'c0', 'c1'}), 850.14);
    });

    test('ignores add-ons charged at actuals even if they are ticked', () {
      final q = quote(100, [null]);
      expect(q.totalFor({'c0'}), 100);
    });

    test('ignores ids it does not know', () {
      expect(quote(100, [50]).totalFor({'nope'}), 100);
    });

    test('extrasFor is the difference', () {
      final q = quote(499, [350]);
      expect(q.extrasFor({'c0'}), 350);
      expect(q.extrasFor({}), 0);
    });

    test('parses the server response', () {
      final q = BookingQuote.fromJson({
        'service_id': 's1',
        'service_name': 'General Service',
        'vehicle_type': 'scooter',
        'package_id': 'p1',
        'package_name': 'Basic',
        'inclusions': ['Wash'],
        'estimated_duration_minutes': null,
        'package_price': '499.00',
        'extra_charges': [
          {
            'extra_charge_id': 'c1',
            'charge_type': 'engine_oil',
            'name': 'Engine oil',
            'amount': '350.00',
            'selectable': true,
            'selected': false,
            'included_in_total': false,
          },
        ],
        'extra_charges_total': '0.00',
        'total_amount': '499.00',
      });
      expect(q.packagePrice, 499);
      expect(q.charges.single.selectable, isTrue);
      expect(q.durationMinutes, isNull);
    });
  });

  group('payment fields', () {
    test('an older response without them is unpaid and not payable', () {
      final b = Booking.fromJson(_json());
      expect(b.payment, isNull);
      expect(b.isPaid, isFalse);
      expect(b.canPay, isFalse);
    });

    test('the payment summary, paid and can-pay flags are read', () {
      final b = Booking.fromJson(_json(override: {
        'status': 'confirmed',
        'is_paid': true,
        'can_pay': false,
        'payment': {
          'id': 'pay-1',
          'status': 'successful',
          'amount': '849.00',
          'currency': 'INR',
          'method': 'card',
          'transaction_id': 'pay_X',
          'paid_at': '2026-10-20T16:05:00+05:30',
          'failure_reason': null,
          'livemode': false,
          'created_at': '2026-10-20T16:00:00+05:30',
        },
      }));
      expect(b.isPaid, isTrue);
      expect(b.payment!.transactionId, 'pay_X');
      expect(b.payment!.amount, 849.0);
    });

    test('a payment that is not an object is refused', () {
      expect(() => Booking.fromJson(_json(override: {'payment': 'x'})),
          throwsFormatException);
    });
  });
}
