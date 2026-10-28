import 'package:ff_garage/app/router/app_routes.dart';
import 'package:ff_garage/core/widgets/brand_logo.dart';
import 'package:ff_garage/core/widgets/service_icon.dart';
import 'package:ff_garage/core/widgets/vehicle_banner.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes_catalog.dart';
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

  testWidgets('browse services lists the 4 tabs and a vehicle toggle',
      (tester) async {
    await AppHarness(role: UserRole.customer).pump(tester);
    await tapText(tester, 'Browse services');
    expect(find.text('2-Wheeler Services'), findsOneWidget);
    expect(find.byKey(const ValueKey('vehicle-type-toggle')), findsOneWidget);
    expect(find.text('Book a Mechanic'), findsWidgets);
    expect(find.text('Service Packages'), findsWidgets);
    expect(tester.takeException(), isNull);
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

  group('service pictures and icons', () {
    test('the three headline services get their own picture', () {
      expect(serviceAssetFor('Book a Mechanic')!.square, contains('book_mechanic'));
      expect(serviceAssetFor('Check My Vehicle')!.banner, contains('check_vehicle'));
      expect(serviceAssetFor('Mechanic Consultation')!.square,
          contains('mechanic_consultation'));
      expect(serviceAssetFor('Brake Pad Replacement'), isNull);
    });

    test('every part category has its own icon', () {
      final icons = {
        for (final c in [
          'Engine', 'Brakes', 'Battery', 'Chain', 'Cables', 'Lights', 'Tyres',
          'Filters', 'Lubricants', 'Electrical',
        ])
          c: serviceIconFor(c),
      };
      expect(icons.values.toSet().length, icons.length);
      expect(serviceIconFor('Other Repairs'), Icons.build_outlined);
    });

    testWidgets('a headline service shows a square picture in the list',
        (tester) async {
      final harness = AppHarness(
        role: UserRole.customer,
        catalog: FakeCatalogRepository([service(name: 'Book a Mechanic')]),
      );
      await harness.pump(tester);
      goTo(tester, AppRoutes.browseServices);
      await tester.pumpAndSettle();
      final image = find.byKey(const ValueKey('asset-image-s1'));
      expect(image, findsOneWidget);
      final size = tester.getSize(image);
      expect(size.width, size.height);
    });

    testWidgets('other services show the circular category icon',
        (tester) async {
      await AppHarness(role: UserRole.customer).pump(tester);
      goTo(tester, AppRoutes.browseServices);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('asset-image-s1')), findsNothing);
      expect(find.byType(ServiceThumb), findsWidgets);
    });

    testWidgets('opening a service shows the full-width banner first',
        (tester) async {
      final harness = AppHarness(
        role: UserRole.customer,
        catalog: FakeCatalogRepository([service(name: 'Check My Vehicle')]),
      );
      await harness.pump(tester);
      goTo(tester, AppRoutes.serviceDetail('s1'));
      await tester.pumpAndSettle();
      final banner = find.byKey(const ValueKey('service-banner'));
      expect(banner, findsOneWidget);
      final width = tester.getSize(banner).width;
      expect(width, tester.view.physicalSize.width / tester.view.devicePixelRatio);
      expect(find.byKey(const ValueKey('detail-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('detail-price')), findsOneWidget);
      expect(find.byKey(const ValueKey('detail-duration')), findsOneWidget);
    });
  });
}
