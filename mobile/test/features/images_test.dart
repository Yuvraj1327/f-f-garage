import 'package:ff_garage/core/widgets/brand_logo.dart';
import 'package:ff_garage/core/widgets/vehicle_banner.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_app.dart';

String _asset(WidgetTester tester, Finder f) =>
    ((tester.widget<Image>(f)).image as AssetImage).assetName;

void main() {
  testWidgets('customer home shows the mechanic banner with Book a service',
      (tester) async {
    await AppHarness(role: UserRole.customer).pump(tester);
    final banner = find.byKey(const ValueKey('home-banner'));
    expect(banner, findsOneWidget);
    expect(_asset(tester, banner), BrandAssets.homeBanner);
    expect(find.widgetWithText(FilledButton, 'Book a service'), findsOneWidget);
  });

  testWidgets('home scrolls to the two promo sections and nothing overflows',
      (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await AppHarness(role: UserRole.customer).pump(tester);

    final scroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('promo-why-choose')),
      300,
      scrollable: scroll,
    );
    expect(find.text('Why Choose F&F Garage?'), findsOneWidget);
    expect(_asset(tester, find.byKey(const ValueKey('promo-bike-image'))),
        BrandAssets.promoBike);
    for (final benefit in [
      'Convenient doorstep service',
      'Skilled mechanics',
      'Transparent pricing',
      'Easy booking',
    ]) {
      expect(find.text(benefit), findsOneWidget);
    }

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('promo-scooter')),
      300,
      scrollable: scroll,
    );
    expect(find.text('Reliable scooter servicing'), findsOneWidget);
    expect(_asset(tester, find.byKey(const ValueKey('promo-scooter-image'))),
        BrandAssets.promoScooter);
    expect(tester.takeException(), isNull);
    // The bottom navbar stays on screen.
    expect(find.byKey(const ValueKey('nav-home')), findsOneWidget);
  });

  testWidgets('browse services shows the scooter then the bike picture',
      (tester) async {
    await AppHarness(role: UserRole.customer).pump(tester);
    await tapText(tester, 'Browse services');
    expect(_asset(tester, find.byKey(const ValueKey('vehicle-scooter'))),
        BrandAssets.scooter);
    await tester.tap(find.text('Bike'));
    await tester.pumpAndSettle();
    expect(_asset(tester, find.byKey(const ValueKey('vehicle-bike'))),
        BrandAssets.bike);
  });

  testWidgets('the vehicle picture keeps its 16:9 shape', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: VehicleBanner(type: VehicleType.bike)),
    ));
    final box = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(box.aspectRatio, closeTo(1672 / 941, 0.001));
  });

  test('brand assets are the registered files', () {
    expect(BrandAssets.logo, 'assets/images/logo.png');
    expect(BrandAssets.scooter, 'assets/images/scooter.jpg');
    expect(BrandAssets.bike, 'assets/images/bike.jpg');
    expect(BrandAssets.homeBanner, 'assets/images/home_banner.jpg');
    expect(BrandAssets.promoBike, 'assets/images/promo_bike_service.jpg');
    expect(BrandAssets.promoScooter, 'assets/images/promo_scooter_service.jpg');
  });
}
