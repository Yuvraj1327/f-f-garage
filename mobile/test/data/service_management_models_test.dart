import 'dart:typed_data';

import 'package:ff_garage/core/media/image_picker_service.dart';
import 'package:ff_garage/data/models/catalog.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/models/support_contact.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes_catalog.dart';

Uint8List _bytes(List<int> head, [int length = 20]) {
  final b = Uint8List(length);
  b.setRange(0, head.length, head);
  return b;
}

void main() {
  group('package pricing labels', () {
    test('discount label rounds down and hides tiny discounts', () {
      expect(package(price: 240, originalPrice: 300).discountLabel, '20% OFF');
      expect(package(price: 299, originalPrice: 300).discountLabel, isNull);
      expect(package(price: 100).discountLabel, isNull);
      expect(package(price: 100, originalPrice: 100).hasDiscount, isFalse);
      expect(package(price: 71, originalPrice: 100).discountLabel, '29% OFF');
    });

    test('repeat label', () {
      expect(package().repeatLabel, 'As needed');
      expect(package(repeatIntervalDays: 1).repeatLabel, 'Every day');
      expect(package(repeatIntervalDays: 45).repeatLabel, 'Every 45 days');
      expect(package(repeatIntervalDays: 90).repeatLabel, 'Every 3 months');
    });

    test('advance uses the package percent, else the default', () {
      expect(package(price: 500).advanceFor(20), 100);
      expect(package(price: 500, advancePercent: 50).advanceFor(20), 250);
      expect(package(price: 499).advanceFor(20), 99.8);
    });

    test('parses the new package fields', () {
      final p = ServicePackage.fromJson({
        'id': 'p',
        'service_id': 's',
        'name': 'Standard',
        'price': '299.00',
        'original_price': '399.00',
        'advance_percent': '25.00',
        'repeat_interval_days': 90,
        'labour_charge': '150.00',
        'included_parts': ['Oil', 'Filter'],
        'inclusions': ['Wash'],
        'display_order': 0,
        'is_active': true,
      });
      expect(p.advancePercent, 25);
      expect(p.repeatIntervalDays, 90);
      expect(p.labourCharge, 150);
      expect(p.includedParts, ['Oil', 'Filter']);
    });

    test('an old response without the new fields still parses', () {
      final p = ServicePackage.fromJson({
        'id': 'p',
        'service_id': 's',
        'name': 'Standard',
        'price': '299.00',
        'inclusions': <String>[],
        'display_order': 0,
        'is_active': true,
      });
      expect(p.advancePercent, isNull);
      expect(p.includedParts, isEmpty);
    });
  });

  group('service model', () {
    Map<String, dynamic> json([Map<String, dynamic> extra = const {}]) => {
          'id': 's',
          'name': 'Check My Vehicle',
          'vehicle_type': 'bike',
          'category': 'Book a Mechanic',
          'display_order': 0,
          'is_active': true,
          'packages': <Map<String, dynamic>>[],
          'extra_charges': <Map<String, dynamic>>[],
          ...extra,
        };

    test('pictures fall back thumbnail -> older image', () {
      final plain = GarageService.fromJson(json({'image_url': 'https://x/old.jpg'}));
      expect(plain.thumbnail, 'https://x/old.jpg');
      expect(plain.banner, 'https://x/old.jpg');
      final full = GarageService.fromJson(json({
        'image_url': 'https://x/old.jpg',
        'thumbnail_url': 'https://x/t.jpg',
        'banner_url': 'https://x/b.jpg',
      }));
      expect(full.thumbnail, 'https://x/t.jpg');
      expect(full.banner, 'https://x/b.jpg');
    });

    test('the card text prefers the short description', () {
      final s = GarageService.fromJson(json({
        'short_description': 'Short',
        'description': 'Long text',
      }));
      expect(s.cardText, 'Short');
      expect(GarageService.fromJson(json({'description': 'Long'})).cardText, 'Long');
    });

    test('compatibility: empty lists mean every vehicle', () {
      final all = GarageService.fromJson(json());
      expect(all.supports('Hero', 'Splendor'), isTrue);
    });

    test('compatibility needs the make and the model to match, ignoring case', () {
      final s = GarageService.fromJson(json({
        'supported_makes': ['Honda'],
        'supported_models': ['Shine', 'Unicorn'],
      }));
      expect(s.supports('honda', ' shine '), isTrue);
      expect(s.supports('Honda', 'Activa'), isFalse);
      expect(s.supports('Hero', 'Shine'), isFalse);
    });

    test('parses part pictures, system key and category', () {
      final s = GarageService.fromJson(json({
        'part_image_urls': ['https://x/1.jpg'],
        'system_key': 'check_vehicle',
        'category_id': 'c1',
      }));
      expect(s.partImageUrls, ['https://x/1.jpg']);
      expect(s.systemKey, 'check_vehicle');
      expect(s.categoryId, 'c1');
    });
  });

  group('ServiceCategory', () {
    test('parses', () {
      final c = ServiceCategory.fromJson({
        'id': 'c',
        'name': 'Brakes',
        'tab': 'repair',
        'icon_key': 'brakes',
        'display_order': 40,
        'is_active': false,
        'system_key': null,
      });
      expect(c.tab, CatalogTab.repair);
      expect(c.iconKey, 'brakes');
      expect(c.isActive, isFalse);
      expect(c.systemKey, isNull);
    });
  });

  group('support contact advance percent', () {
    test('defaults to 20 and reads strings or numbers', () {
      expect(SupportContact.fromJson({'name': 'x'}).advancePercent, 20);
      expect(
        SupportContact.fromJson({'name': 'x', 'advance_percent': '25.00'})
            .advancePercent,
        25,
      );
      expect(
        SupportContact.fromJson({'name': 'x', 'advance_percent': 30}).advancePercent,
        30,
      );
      expect(
        SupportContact.fromJson({'name': 'x', 'advance_percent': 'bad'})
            .advancePercent,
        20,
      );
      expect(
        SupportContact.fromJson({'name': 'x', 'advance_percent': 0}).advancePercent,
        20,
      );
    });
  });

  group('picture checks', () {
    test('type comes from the first bytes, not the name', () {
      expect(sniffImageType(_bytes([0xFF, 0xD8, 0xFF])), 'image/jpeg');
      expect(
        sniffImageType(_bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
        'image/png',
      );
      expect(
        sniffImageType(_bytes(
          [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50],
          24,
        )),
        'image/webp',
      );
      expect(sniffImageType(_bytes([0x25, 0x50, 0x44, 0x46])), isNull);
      expect(sniffImageType(Uint8List(0)), isNull);
    });

    test('checkPicture rejects empty, huge and non-image files', () {
      PickedImage pic(Uint8List b) => PickedImage(bytes: b, name: 'p');
      expect(checkPicture(pic(Uint8List(0))), 'That picture is empty.');
      expect(checkPicture(pic(_bytes([1, 2, 3]))), 'Use a JPG, PNG or WebP picture.');
      expect(
        checkPicture(pic(_bytes([0xFF, 0xD8, 0xFF], maxPictureBytes + 1))),
        'That picture is too large. Use one under 5 MB.',
      );
      expect(checkPicture(pic(_bytes([0xFF, 0xD8, 0xFF]))), isNull);
      expect(
        checkPicture(pic(_bytes([0xFF, 0xD8, 0xFF], maxPictureBytes))),
        isNull,
      );
    });
  });
}
