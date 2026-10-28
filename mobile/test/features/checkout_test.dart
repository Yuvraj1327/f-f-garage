import 'package:ff_garage/app/router/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/booking_journey.dart';
import '../support/pump_app.dart';

void main() {
  group('catalog and checkout', () {
    testWidgets('adding a service shows the cart bar, and it can be removed',
        (tester) async {
      useTallScreen(tester);
      await customerHarness().pump(tester);
      await tapText(tester, 'Browse services');
      expect(find.byKey(const ValueKey('cart-bar')), findsNothing);

      await tapText(tester, 'General Service');
      await tapKey(tester, 'book-p1');
      goTo(tester, AppRoutes.browseServices);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cart-bar')), findsOneWidget);

      await tapKey(tester, 'cart-remove');
      expect(find.byKey(const ValueKey('cart-bar')), findsNothing);
    });

    testWidgets('checkout shows the estimate and the 20% advance, and asks '
        'for a location before it can be confirmed', (tester) async {
      useTallScreen(tester);
      final harness = customerHarness();
      await harness.pump(tester);
      await tapText(tester, 'Browse services');
      await tapText(tester, 'General Service');
      await tapKey(tester, 'book-p1');
      goTo(tester, AppRoutes.checkout);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('estimated-total')), findsOneWidget);
      expect(find.byKey(const ValueKey('advance-now')), findsOneWidget);
      expect(find.text('Add your location to continue'), findsOneWidget);
      expect(harness.bookingRepo.creates, isEmpty);
    });
  });
}
