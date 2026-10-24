import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/models/payment.dart';
import 'package:ff_garage/data/repositories/payment_repository.dart';
import 'package:ff_garage/data/services/payment_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_api.dart';

Map<String, dynamic> _payment({
  String status = 'successful',
  Map<String, dynamic>? extra,
}) =>
    {
      'id': 'pay-1',
      'booking_id': 'b1',
      'gateway_order_id': 'order_X',
      'status': status,
      'amount': '499.00',
      'currency': 'INR',
      'method': 'upi',
      'transaction_id': 'pay_X',
      'paid_at': '2026-10-20T16:05:00+05:30',
      'failure_reason': null,
      'livemode': false,
      'created_at': '2026-10-20T16:00:00+05:30',
      ...?extra,
    };

Map<String, dynamic> _checkout() => {
      'key_id': 'rzp_test_abc',
      'order_id': 'order_X',
      'amount_paise': 49900,
      'currency': 'INR',
      'name': 'F&F Two Wheeler Garage',
      'description': 'FF-000001',
      'prefill_name': 'Asha',
      'prefill_contact': null,
      'prefill_email': null,
      'mode': 'test',
    };

PaymentRepository _repo(StubApi api) =>
    PaymentRepository(PaymentApiService(api.client));

const _signature = CheckoutSuccess(
  orderId: 'order_X',
  paymentId: 'pay_X',
  signature: 'sig',
);

void main() {
  group('models', () {
    test('a payment is read with money, dates and status', () {
      final p = Payment.fromJson(_payment());
      expect(p.status, PaymentStatus.successful);
      expect(p.isSuccessful, isTrue);
      expect(p.amount, 499.0);
      expect(p.transactionId, 'pay_X');
      expect(p.paidAt, isNotNull);
      expect(p.livemode, isFalse);
    });

    test('cancelled and pending are understood', () {
      expect(Payment.fromJson(_payment(status: 'cancelled')).status,
          PaymentStatus.cancelled);
      expect(Payment.fromJson(_payment(status: 'pending')).isSuccessful,
          isFalse);
    });

    test('an unknown status is refused rather than guessed', () {
      expect(() => Payment.fromJson(_payment(status: 'refunded')),
          throwsFormatException);
    });

    test('checkout options become the Razorpay options map', () {
      final options = CheckoutOptions.fromJson(_checkout());
      expect(options.isTestMode, isTrue);
      final map = options.toRazorpayOptions();
      expect(map['key'], 'rzp_test_abc');
      expect(map['order_id'], 'order_X');
      expect(map['amount'], 49900);
      expect(map['currency'], 'INR');
      expect(map['prefill'], {'name': 'Asha'});
      expect(map.containsKey('secret'), isFalse);
    });

    test('live mode is recognised', () {
      final live = CheckoutOptions.fromJson({..._checkout(), 'mode': 'live'});
      expect(live.isTestMode, isFalse);
    });

    test('the server verdict is read', () {
      final verdict = PaymentResult.fromJson({
        'payment': _payment(),
        'booking_status': 'confirmed',
        'outcome': 'paid',
        'paid': true,
      });
      expect(verdict.paid, isTrue);
      expect(verdict.bookingStatus, BookingStatus.confirmed);
    });
  });

  group('repository', () {
    test('start posts to the booking and sends no amount', () async {
      final api = StubApi((_) => (
            201,
            {'payment': _payment(status: 'pending'), 'checkout': _checkout()},
          ));
      final started = await _repo(api).start('b1');
      expect(api.last.method, 'POST');
      expect(api.last.path, '/bookings/b1/payments');
      expect(api.last.body, isNull);
      expect(started.checkout.amountPaise, 49900);
      expect(started.payment.status, PaymentStatus.pending);
    });

    test('verify sends the three checkout values and reads the verdict',
        () async {
      final api = StubApi((_) => (
            200,
            {
              'payment': _payment(),
              'booking_status': 'confirmed',
              'outcome': 'paid',
              'paid': true,
            },
          ));
      final result = await _repo(api).verify('pay-1', _signature);
      expect(api.last.path, '/payments/pay-1/verify');
      expect(api.last.body, {
        'razorpay_order_id': 'order_X',
        'razorpay_payment_id': 'pay_X',
        'razorpay_signature': 'sig',
      });
      expect(result.paid, isTrue);
      expect(result.bookingStatus, BookingStatus.confirmed);
    });

    test('cancel, get and list use the payment endpoints', () async {
      final api = StubApi((r) => r.path.endsWith('/payments')
          ? (200, [_payment()])
          : (200, _payment(status: 'cancelled')));
      final repo = _repo(api);
      expect((await repo.cancel('pay-1')).status, PaymentStatus.cancelled);
      expect(api.last.path, '/payments/pay-1/cancel');
      await repo.get('pay-1');
      expect(api.last.path, '/payments/pay-1');
      expect(await repo.forBooking('b1'), hasLength(1));
      expect(api.last.path, '/bookings/b1/payments');
    });

    test('a server error is an ApiException with the server message', () async {
      final api = StubApi((_) => (
            503,
            {'detail': 'Online payments are not available right now'},
          ));
      await expectLater(
        _repo(api).start('b1'),
        throwsA(isA<ApiException>()),
      );
    });

    test('a malformed answer becomes an invalid-response error', () async {
      final api = StubApi((_) => (200, {'payment': 'nope', 'checkout': {}}));
      await expectLater(
        _repo(api).start('b1'),
        throwsA(isA<ApiException>().having(
          (e) => e.type,
          'type',
          ApiErrorType.invalidResponse,
        )),
      );
    });
  });
}
