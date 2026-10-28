import 'package:ff_garage/data/models/billing.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> extraJson(String id, String status, String amount) => {
      'id': id,
      'booking_id': 'b1',
      'charge_type': 'spare_part',
      'name': 'Brake pads',
      'amount': amount,
      'status': status,
      'requested_by_role': 'driver',
      'created_at': '2026-10-28T10:00:00Z',
    };

Map<String, dynamic> billJson() => {
      'booking_id': 'b1',
      'booking_code': 'FF-000001',
      'status': 'completed',
      'is_final': true,
      'service_name': 'General Service',
      'package_name': 'Basic',
      'package_price': '1000.00',
      'addons_total': '0.00',
      'discount_amount': '0.00',
      'estimated_total': '1000.00',
      'advance_percent': '20',
      'advance_due': '200.00',
      'advance_paid': '200.00',
      'approved_extras': [extraJson('e1', 'approved', '200.00')],
      'approved_extras_total': '200.00',
      'pending_extras': <Map<String, dynamic>>[],
      'pending_extras_total': '0.00',
      'final_total': '1200.00',
      'amount_paid': '200.00',
      'balance_due': '1000.00',
      'can_pay_balance': true,
      'refunded_total': '0.00',
      'payments': [
        {
          'id': 'p1',
          'kind': 'advance',
          'status': 'successful',
          'amount': '200.00',
          'created_at': '2026-10-28T09:00:00Z',
        },
        {
          'id': 'p2',
          'kind': 'balance',
          'status': 'failed',
          'amount': '1000.00',
          'created_at': '2026-10-28T11:00:00Z',
        },
      ],
      'refunds': <Map<String, dynamic>>[],
    };

void main() {
  test('the worked example: estimate 1000, advance 200, extras 200', () {
    final bill = Bill.fromJson(billJson());
    expect(bill.estimatedTotal, 1000);
    expect(bill.advancePaid, 200);
    expect(bill.approvedExtrasTotal, 200);
    expect(bill.finalTotal, 1200);
    expect(bill.balanceDue, 1000);
    expect(bill.canPayBalance, isTrue);
    expect(bill.approvedExtras.single.status, ExtraStatus.approved);
    expect(bill.refundPolicy, '');
  });

  test('only successful payments are counted as paid', () {
    final bill = Bill.fromJson(billJson());
    expect(bill.payments, hasLength(2));
    expect(bill.successfulPayments.single.kind, PaymentKind.advance);
  });

  test('a proposed extra is open, an approved one is not', () {
    expect(ExtraRequest.fromJson(extraJson('e', 'proposed', '50')).isOpen,
        isTrue);
    expect(ExtraRequest.fromJson(extraJson('e', 'approved', '50')).isOpen,
        isFalse);
  });

  test('a bill missing a field is rejected, not guessed', () {
    final broken = billJson()..remove('final_total');
    expect(() => Bill.fromJson(broken), throwsFormatException);
  });
}
