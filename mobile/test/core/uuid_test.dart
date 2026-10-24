import 'dart:math';

import 'package:ff_garage/core/utils/uuid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final shape = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  test('looks like a version 4 UUID', () {
    for (var i = 0; i < 50; i++) {
      expect(newUuidV4(), matches(shape));
    }
  });

  test('is different every time', () {
    final ids = {for (var i = 0; i < 200; i++) newUuidV4()};
    expect(ids.length, 200);
  });

  test('the same random source gives the same value (no hidden state)', () {
    expect(newUuidV4(Random(7)), newUuidV4(Random(7)));
  });
}
