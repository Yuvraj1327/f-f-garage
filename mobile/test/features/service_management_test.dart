import 'dart:typed_data';

import 'package:ff_garage/app/router/app_routes.dart';
import 'package:ff_garage/core/media/image_picker_service.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/booking_journey.dart';
import '../support/fakes_catalog.dart';
import '../support/fakes_vehicles.dart';
import '../support/pump_app.dart';

void main() {
  group('customer cards', () {
    testWidgets('show the offer, discount, price and View details / ADD',
        (tester) async {
      useTallScreen(tester);
      final catalog = FakeCatalogRepository([
        service(
          id: 's1',
          name: 'Book a Mechanic',
          badge: 'Trending',
          shortDescription: 'Diagnosis and a repair estimate.',
          packages: [
            package(serviceId: 's1', price: 240, originalPrice: 300),
          ],
        ),
      ]);
      final harness = AppHarness(role: UserRole.customer, catalog: catalog);
      await harness.pump(tester);
      goTo(tester, AppRoutes.browseServices);
      await tester.pumpAndSettle();

      expect(find.text('Book a Mechanic'), findsOneWidget);
      expect(find.text('Diagnosis and a repair estimate.'), findsOneWidget);
      expect(find.text('Trending'), findsOneWidget);
      expect(find.text('20% OFF'), findsOneWidget);
      expect(find.text('₹240'), findsOneWidget);
      expect(find.text('₹300'), findsOneWidget);
      expect(find.byKey(const ValueKey('details-s1')), findsOneWidget);

      await tapKey(tester, 'add-s1');
      expect(find.byKey(const ValueKey('added-s1')), findsOneWidget);
    });

    testWidgets('a vehicle the service does not support cannot add it',
        (tester) async {
      useTallScreen(tester);
      final catalog = FakeCatalogRepository([
        service(
          id: 's1',
          name: 'Honda Care',
          supportedMakes: ['Honda'],
        ),
      ]);
      final harness = AppHarness(
        role: UserRole.customer,
        catalog: catalog,
        vehicles: FakeVehicleRepository([vehicle(make: 'TVS', model: 'Jupiter')]),
      );
      await harness.pump(tester);
      goTo(tester, AppRoutes.browseServices);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('unsupported-s1')), findsOneWidget);
      final add = tester.widget<FilledButton>(find.byKey(const ValueKey('add-s1')));
      expect(add.onPressed, isNull);
    });

    testWidgets('a vehicle that is supported can add it', (tester) async {
      useTallScreen(tester);
      final catalog = FakeCatalogRepository([
        service(id: 's1', name: 'TVS Care', supportedMakes: ['tvs']),
      ]);
      final harness = AppHarness(
        role: UserRole.customer,
        catalog: catalog,
        vehicles: FakeVehicleRepository([vehicle(make: 'TVS', model: 'Jupiter')]),
      );
      await harness.pump(tester);
      goTo(tester, AppRoutes.browseServices);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('unsupported-s1')), findsNothing);
      await tapKey(tester, 'add-s1');
      expect(find.byKey(const ValueKey('added-s1')), findsOneWidget);
    });
  });

  group('customer details page', () {
    testWidgets('shows the info tiles, the three sections and what to pay now',
        (tester) async {
      useTallScreen(tester);
      final catalog = FakeCatalogRepository([
        service(
          id: 's1',
          name: 'Brake Overhaul',
          partImageUrls: ['https://cdn.test/pad.jpg'],
          packages: [
            package(
              id: 'p1',
              serviceId: 's1',
              price: 500,
              originalPrice: 625,
              minutes: 90,
              warrantyDays: 30,
              repeatIntervalDays: 90,
              inclusions: ['Brake inspection', 'Pad refit'],
              includedParts: ['Brake pads'],
              exclusions: ['Disc replacement'],
            ),
          ],
        ),
      ]);
      final harness = AppHarness(role: UserRole.customer, catalog: catalog);
      await harness.pump(tester);
      goTo(tester, AppRoutes.serviceDetail('s1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('detail-name')), findsOneWidget);
      expect(find.text('₹500'), findsWidgets);
      expect(find.text('20% OFF'), findsOneWidget);
      expect(find.byKey(const ValueKey('detail-duration')), findsOneWidget);
      expect(find.text('30 days'), findsWidgets);
      expect(find.text('Every 90 days'), findsOneWidget);
      expect(find.text('Included Services (2)'), findsOneWidget);
      expect(find.text('Included Parts (1)'), findsOneWidget);
      expect(find.text('Not Included (1)'), findsOneWidget);
      expect(find.text('Brake pads'), findsOneWidget);
      expect(find.byKey(const ValueKey('part-images')), findsOneWidget);
      // 20% now, the rest after the service.
      expect(find.text('Pay now ₹100 / ₹400 after service'), findsOneWidget);
    });

    testWidgets('a package with its own advance percent shows that share',
        (tester) async {
      useTallScreen(tester);
      final catalog = FakeCatalogRepository([
        service(
          id: 's1',
          packages: [
            package(id: 'p1', serviceId: 's1', price: 500, advancePercent: 50),
          ],
        ),
      ]);
      await AppHarness(role: UserRole.customer, catalog: catalog).pump(tester);
      goTo(tester, AppRoutes.serviceDetail('s1'));
      await tester.pumpAndSettle();
      expect(find.text('Pay now ₹250 / ₹250 after service'), findsOneWidget);
    });

    testWidgets('empty sections are hidden', (tester) async {
      useTallScreen(tester);
      final catalog = FakeCatalogRepository([
        service(
          id: 's1',
          packages: [package(id: 'p1', serviceId: 's1', inclusions: ['Wash'])],
        ),
      ]);
      await AppHarness(role: UserRole.customer, catalog: catalog).pump(tester);
      goTo(tester, AppRoutes.serviceDetail('s1'));
      await tester.pumpAndSettle();
      expect(find.text('Included Services (1)'), findsOneWidget);
      expect(find.byKey(const ValueKey('section-Included Parts')), findsNothing);
      expect(find.byKey(const ValueKey('section-Not Included')), findsNothing);
    });
  });

  group('admin service list', () {
    Future<AppHarness> open(WidgetTester tester, FakeCatalogRepository catalog) async {
      useTallScreen(tester);
      final harness = AppHarness(role: UserRole.admin, catalog: catalog);
      await harness.pump(tester);
      goTo(tester, AppRoutes.adminServices);
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('uses the customer card with management controls',
        (tester) async {
      final harness = await open(
        tester,
        FakeCatalogRepository([service(id: 's1', badge: 'Popular')]),
      );
      expect(find.byKey(const ValueKey('service-s1')), findsOneWidget);
      expect(find.text('Popular'), findsOneWidget);
      for (final key in ['preview-s1', 'edit-s1', 'duplicate-s1', 'delete-s1']) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      // Customers' Add button is not on the admin card.
      expect(find.byKey(const ValueKey('add-s1')), findsNothing);
      expect(harness.catalog.calls, contains('adminCategories'));
    });

    testWidgets('filters by category and searches by name', (tester) async {
      await open(
        tester,
        FakeCatalogRepository([
          service(id: 's1', name: 'General Service'),
          service(id: 's2', name: 'Pad Change', categoryId: 'cat-brakes'),
        ]),
      );
      await tester.tap(find.byKey(const ValueKey('cat-Brakes')));
      await tester.pumpAndSettle();
      expect(find.text('General Service'), findsNothing);
      expect(find.text('Pad Change'), findsOneWidget);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('admin-service-search')), 'general');
      await tester.pumpAndSettle();
      expect(find.text('General Service'), findsOneWidget);
      expect(find.text('Pad Change'), findsNothing);
    });

    testWidgets('duplicate makes a switched-off copy', (tester) async {
      final harness = await open(tester, FakeCatalogRepository([service(id: 's1')]));
      await tapKey(tester, 'duplicate-s1');
      expect(harness.catalog.calls, contains('duplicateService:s1'));
      expect(find.text('General Service (Copy)'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
    });

    testWidgets('delete asks first, then removes the service', (tester) async {
      final harness = await open(tester, FakeCatalogRepository([service(id: 's1')]));
      await tapKey(tester, 'delete-s1');
      expect(find.text('Delete service?'), findsOneWidget);
      await tapText(tester, 'Cancel');
      expect(harness.catalog.calls.where((c) => c.startsWith('deleteService')), isEmpty);

      await tapKey(tester, 'delete-s1');
      await tapText(tester, 'Delete');
      expect(harness.catalog.calls, contains('deleteService:s1'));
      expect(find.text('General Service'), findsNothing);
    });

    testWidgets('a built-in service cannot be deleted', (tester) async {
      await open(
        tester,
        FakeCatalogRepository([service(id: 's1', systemKey: 'book_mechanic')]),
      );
      final button = tester.widget<IconButton>(find.byKey(const ValueKey('delete-s1')));
      expect(button.onPressed, isNull);
    });

    testWidgets('preview shows the customer page without Add', (tester) async {
      await open(tester, FakeCatalogRepository([service(id: 's1', isActive: false)]));
      await tapKey(tester, 'preview-s1');
      expect(find.text('Preview as customer'), findsOneWidget);
      expect(find.byKey(const ValueKey('detail-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('book-p1')), findsNothing);
      expect(find.text('Add (preview)'), findsOneWidget);
    });
  });

  group('admin categories', () {
    Future<AppHarness> open(WidgetTester tester) async {
      useTallScreen(tester);
      final harness = AppHarness(role: UserRole.admin);
      await harness.pump(tester);
      goTo(tester, AppRoutes.adminCategories);
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('lists the categories with their tab', (tester) async {
      await open(tester);
      expect(find.text('Book a Mechanic'), findsWidgets);
      expect(find.text('Brakes'), findsOneWidget);
      expect(find.text('Specific Repair'), findsOneWidget);
    });

    testWidgets('adds a category after validating the name', (tester) async {
      final harness = await open(tester);
      await tapKey(tester, 'add-category');
      await tapKey(tester, 'category-save');
      expect(find.text('Enter at least 2 characters'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('category-name')), 'Tyres');
      await tapKey(tester, 'category-save');
      expect(harness.catalog.calls, contains('createCategory:Tyres:repair'));
      expect(find.text('Tyres'), findsOneWidget);
    });

    testWidgets('renames a category', (tester) async {
      final harness = await open(tester);
      await tapKey(tester, 'category-edit-cat-brakes');
      await tester.enterText(
        find.byKey(const ValueKey('category-name')),
        'Brakes & Discs',
      );
      await tapKey(tester, 'category-save');
      expect(harness.catalog.calls, contains('updateCategory:cat-brakes:name'));
      expect(find.text('Brakes & Discs'), findsOneWidget);
    });

    testWidgets('a built-in category keeps its tab', (tester) async {
      await open(tester);
      await tapKey(tester, 'category-edit-cat-package');
      final dropdown = tester.widget<DropdownButtonFormField<dynamic>>(
        find.byKey(const ValueKey('category-tab')),
      );
      expect(dropdown.onChanged, isNull);
    });

    testWidgets('the switch hides a category from customers', (tester) async {
      final harness = await open(tester);
      final toggle = find.descendant(
        of: find.byKey(const ValueKey('category-active-cat-brakes')),
        matching: find.byType(Switch),
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(harness.catalog.calls, contains('updateCategory:cat-brakes:is_active'));
      expect(harness.catalog.categories.firstWhere((c) => c.id == 'cat-brakes').isActive, isFalse);
      expect(find.textContaining('hidden'), findsOneWidget);
    });

    testWidgets('dragging a category saves the new order', (tester) async {
      final harness = await open(tester);
      await tester.drag(find.byIcon(Icons.drag_handle).first, const Offset(0, 130));
      await tester.pumpAndSettle();
      expect(
        harness.catalog.calls.where((c) => c.startsWith('reorderCategories')),
        isNotEmpty,
      );
    });
  });

  group('service editor pictures', () {
    Future<AppHarness> open(WidgetTester tester, {String? id}) async {
      useTallScreen(tester, height: 6000);
      final harness = AppHarness(
        role: UserRole.admin,
        catalog: FakeCatalogRepository([
          service(
            id: 's1',
            bannerUrl: id == null ? null : 'https://cdn.test/old-banner.jpg',
          ),
        ]),
      );
      await harness.pump(tester);
      goTo(
        tester,
        id == null ? AppRoutes.adminServiceNew : AppRoutes.adminServiceEdit(id),
      );
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('a gallery picture is uploaded as the banner', (tester) async {
      final harness = await open(tester);
      harness.imagePicker.queue.add(PickedImage(bytes: fakeJpeg, name: 'a.jpg'));
      await tapKey(tester, 'banner-gallery');

      expect(harness.imagePicker.sources, [PickSource.gallery]);
      expect(harness.catalog.calls, contains('uploadImage:banner:image/jpeg:8'));
      expect(find.byKey(const ValueKey('banner-preview')), findsOneWidget);
      expect(find.byKey(const ValueKey('banner-remove')), findsOneWidget);
    });

    testWidgets('a camera photo is uploaded as the thumbnail', (tester) async {
      final harness = await open(tester);
      harness.imagePicker.queue.add(PickedImage(bytes: fakeJpeg, name: 'b.jpg'));
      await tapKey(tester, 'thumbnail-camera');

      expect(harness.imagePicker.sources, [PickSource.camera]);
      expect(harness.catalog.calls, contains('uploadImage:thumbnail:image/jpeg:8'));
      expect(find.byKey(const ValueKey('thumbnail-preview')), findsOneWidget);
    });

    testWidgets('a file that is not a picture is refused before uploading',
        (tester) async {
      final harness = await open(tester);
      harness.imagePicker.queue.add(
        PickedImage(bytes: Uint8List.fromList([1, 2, 3, 4]), name: 'x.pdf'),
      );
      await tapKey(tester, 'banner-gallery');
      expect(find.text('Use a JPG, PNG or WebP picture.'), findsOneWidget);
      expect(harness.catalog.uploads, isEmpty);
    });

    testWidgets('a picture over 5 MB is refused', (tester) async {
      final harness = await open(tester);
      final big = Uint8List(maxPictureBytes + 1)..setRange(0, 3, [0xFF, 0xD8, 0xFF]);
      harness.imagePicker.queue.add(PickedImage(bytes: big, name: 'big.jpg'));
      await tapKey(tester, 'banner-gallery');
      expect(find.text('That picture is too large. Use one under 5 MB.'), findsOneWidget);
      expect(harness.catalog.uploads, isEmpty);
    });

    testWidgets('backing out of the picker changes nothing', (tester) async {
      final harness = await open(tester);
      await tapKey(tester, 'banner-gallery');
      expect(harness.catalog.uploads, isEmpty);
      expect(find.byKey(const ValueKey('banner-preview')), findsNothing);
    });

    testWidgets('a camera that cannot open shows a message', (tester) async {
      final harness = await open(tester);
      harness.imagePicker.failWith = Exception('denied');
      await tapKey(tester, 'banner-camera');
      expect(find.textContaining('camera could not be opened'), findsOneWidget);
    });

    testWidgets('replacing a fresh upload discards the first one', (tester) async {
      final harness = await open(tester);
      harness.imagePicker.queue
        ..add(PickedImage(bytes: fakeJpeg, name: '1.jpg'))
        ..add(PickedImage(bytes: fakeJpeg, name: '2.jpg'));
      await tapKey(tester, 'banner-gallery');
      await tapKey(tester, 'banner-gallery');
      expect(harness.catalog.uploads.length, 2);
      expect(harness.catalog.discarded, [harness.catalog.uploads.first]);
    });

    testWidgets('removing a fresh upload discards it', (tester) async {
      final harness = await open(tester);
      harness.imagePicker.queue.add(PickedImage(bytes: fakeJpeg, name: '1.jpg'));
      await tapKey(tester, 'banner-gallery');
      await tapKey(tester, 'banner-remove');
      expect(harness.catalog.discarded, harness.catalog.uploads);
      expect(find.byKey(const ValueKey('banner-preview')), findsNothing);
    });

    testWidgets('leaving without saving discards the new uploads', (tester) async {
      final harness = await open(tester);
      harness.imagePicker.queue.add(PickedImage(bytes: fakeJpeg, name: '1.jpg'));
      await tapKey(tester, 'banner-gallery');
      goTo(tester, AppRoutes.adminServices);
      await tester.pumpAndSettle();
      expect(harness.catalog.discarded, harness.catalog.uploads);
    });

    testWidgets('removing a saved picture does not delete it before Save',
        (tester) async {
      final harness = await open(tester, id: 's1');
      await tapKey(tester, 'banner-remove');
      expect(harness.catalog.discarded, isEmpty);
      await tapText(tester, 'Save changes');
      expect(harness.catalog.lastChanges, {'banner_url': null});
    });

    testWidgets('part pictures are added and removed, up to eight',
        (tester) async {
      final harness = await open(tester);
      for (var i = 0; i < 2; i++) {
        harness.imagePicker.queue.add(PickedImage(bytes: fakeJpeg, name: '$i.jpg'));
        await tapKey(tester, 'part-gallery');
      }
      expect(find.byKey(const ValueKey('part-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('part-1')), findsOneWidget);
      expect(find.text('Part pictures (2/8)'), findsOneWidget);

      await tapKey(tester, 'part-remove-0');
      expect(find.text('Part pictures (1/8)'), findsOneWidget);
      expect(harness.catalog.discarded.length, 1);
    });

    testWidgets('saving a new service sends the pictures and details',
        (tester) async {
      final harness = await open(tester);
      harness.imagePicker.queue
        ..add(PickedImage(bytes: fakeJpeg, name: 'b.jpg'))
        ..add(PickedImage(bytes: fakeJpeg, name: 't.jpg'));
      await tapKey(tester, 'banner-gallery');
      await tapKey(tester, 'thumbnail-gallery');

      await enter(tester, 'Service name', 'Chain Lube');
      await enter(tester, 'Price', '150');
      await enter(tester, 'Original price (optional)', '200');
      await enter(tester, 'Advance payment (optional)', '30');
      await enter(tester, 'Labour charge (optional)', '100');
      await enter(tester, 'Warranty (optional)', '15');
      await enter(tester, 'Repeat interval (optional)', '60');
      await enter(tester, 'What is included (one per line)', 'Clean\nLube');
      await enter(tester, 'Parts included (one per line)', 'Chain oil');
      await tester.enterText(
        find.byKey(const ValueKey('service-short')),
        'Clean and lube the chain',
      );
      await tapKey(tester, 'make-Honda');
      await tapText(tester, 'Publish service');

      final create = harness.catalog.lastCreate!;
      expect(create['banner_url'], harness.catalog.uploads[0]);
      expect(create['thumbnail_url'], harness.catalog.uploads[1]);
      expect(create['short_description'], 'Clean and lube the chain');
      expect(create['supported_makes'], ['Honda']);
      final pkg = harness.catalog.lastPackage!;
      expect(pkg['original_price'], 200);
      expect(pkg['advance_percent'], 30);
      expect(pkg['labour_charge'], 100);
      expect(pkg['warranty_days'], 15);
      expect(pkg['repeat_interval_days'], 60);
      expect(pkg['included_parts'], ['Chain oil']);
      expect(harness.catalog.discarded, isEmpty, reason: 'both pictures were used');
    });

    testWidgets('invalid amounts are caught before saving', (tester) async {
      final harness = await open(tester);
      await enter(tester, 'Service name', 'Chain Lube');
      await enter(tester, 'Price', '100');
      await enter(tester, 'Original price (optional)', '50');
      await enter(tester, 'Advance payment (optional)', '150');
      await enter(tester, 'Labour charge (optional)', '500');
      await tapText(tester, 'Publish service');
      expect(find.text('Cannot be lower than the price'), findsOneWidget);
      expect(find.text('Enter 1 to 100'), findsOneWidget);
      expect(find.text('Cannot be more than the price'), findsOneWidget);
      expect(harness.catalog.calls.where((c) => c.startsWith('createService')), isEmpty);
    });

    testWidgets('Preview shows the unsaved service as a customer sees it',
        (tester) async {
      await open(tester);
      await enter(tester, 'Service name', 'Chain Lube');
      await enter(tester, 'Price', '150');
      await tapKey(tester, 'service-preview');
      expect(find.text('Preview as customer'), findsOneWidget);
      expect(find.text('Chain Lube'), findsWidgets);
      expect(find.text('₹150'), findsWidgets);
    });

    testWidgets('a service with several packages points to the service page',
        (tester) async {
      useTallScreen(tester, height: 6000);
      final harness = AppHarness(
        role: UserRole.admin,
        catalog: FakeCatalogRepository([
          service(id: 's1', packages: [
            package(id: 'p1', serviceId: 's1'),
            package(id: 'p2', serviceId: 's1', name: 'Premium'),
          ]),
        ]),
      );
      await harness.pump(tester);
      goTo(tester, AppRoutes.adminServiceEdit('s1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('multi-package-note')), findsOneWidget);
      expect(find.text('Estimated duration (optional)'), findsNothing);
    });

    testWidgets('models can be chosen for the supported makes', (tester) async {
      final harness = await open(tester);
      await tapText(tester, 'Bike');
      await tapKey(tester, 'make-Honda');
      await tapKey(tester, 'pick-models');
      await tapKey(tester, 'model-Shine');
      await tapKey(tester, 'models-done');
      expect(find.text('Models: 1 chosen'), findsOneWidget);

      await enter(tester, 'Service name', 'Honda Care');
      await enter(tester, 'Price', '300');
      await tapText(tester, 'Publish service');
      expect(harness.catalog.lastCreate!['supported_models'], ['Shine']);
    });
  });
}
