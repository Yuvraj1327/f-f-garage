import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../models/payment.dart';

/// Opens the payment gateway's checkout and reports what happened.
///
/// A narrow interface so screens (and tests) never touch the SDK directly. What it
/// returns is only a report from the device; the server verifies every success.
abstract class CheckoutLauncher {
  Future<CheckoutResult> open(CheckoutOptions options);
}

/// Razorpay's checkout, through the `razorpay_flutter` plugin.
class RazorpayCheckoutLauncher implements CheckoutLauncher {
  const RazorpayCheckoutLauncher();

  @override
  Future<CheckoutResult> open(CheckoutOptions options) {
    final completer = Completer<CheckoutResult>();
    final razorpay = Razorpay();

    void finish(CheckoutResult result) {
      if (!completer.isCompleted) {
        completer.complete(result);
      }
      razorpay.clear();
    }

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      final orderId = r.orderId;
      final paymentId = r.paymentId;
      final signature = r.signature;
      if (orderId == null || paymentId == null || signature == null) {
        finish(const CheckoutFailure(
          'The payment window returned an incomplete answer.',
        ));
        return;
      }
      finish(CheckoutSuccess(
        orderId: orderId,
        paymentId: paymentId,
        signature: signature,
      ));
    });
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      if (r.code == Razorpay.PAYMENT_CANCELLED) {
        finish(const CheckoutDismissed());
      } else {
        finish(CheckoutFailure(r.message ?? 'The payment did not go through.'));
      }
    });
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
      finish(const CheckoutPending());
    });

    try {
      razorpay.open(options.toRazorpayOptions());
    } catch (_) {
      finish(const CheckoutFailure('The payment window could not be opened.'));
    }
    return completer.future;
  }
}
