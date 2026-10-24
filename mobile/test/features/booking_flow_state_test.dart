import 'package:ff_garage/data/models/availability.dart';
import 'package:ff_garage/features/booking/providers/booking_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes_catalog.dart';

const _address = BookingAddress(
  pincode: '560001',
  addressLine: '12 MG Road',
  areaName: 'MG Road',
  city: 'Bengaluru',
);

final _schedule = BookingSchedule(
  date: DateTime(2026, 10, 21),
  slotId: 'slot1',
  start: const ClockTime(9, 0),
  end: const ClockTime(11, 0),
);

void main() {
  late ProviderContainer container;
  BookingFlowController flow() => container.read(bookingFlowProvider.notifier);
  BookingFlowState state() => container.read(bookingFlowProvider);

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('starts empty with a request id', () {
    expect(state().hasPackage, isFalse);
    expect(state().isComplete, isFalse);
    expect(state().requestId, isNotEmpty);
  });

  test('is complete only with a package, an address and a time', () {
    final s = service();
    flow().start(s, s.packages.first);
    expect(state().hasPackage, isTrue);
    expect(state().isComplete, isFalse);
    flow().setAddress(_address);
    expect(state().isComplete, isFalse);
    flow().setSchedule(_schedule);
    expect(state().isComplete, isTrue);
  });

  test('starting again drops everything and issues a new request id', () {
    final s = service();
    flow().start(s, s.packages.first);
    flow().setAddress(_address);
    flow().setSchedule(_schedule);
    flow().setExtraCharge('c1', true);
    flow().setNotes('Gate 4');
    final firstId = state().requestId;

    flow().start(s, s.packages.first);
    expect(state().address, isNull);
    expect(state().schedule, isNull);
    expect(state().extraChargeIds, isEmpty);
    expect(state().notes, isEmpty);
    expect(state().requestId, isNot(firstId));
  });

  test('keeps the request id while the customer edits their choices', () {
    final s = service();
    flow().start(s, s.packages.first);
    final id = state().requestId;
    flow().setAddress(_address);
    flow().setSchedule(_schedule);
    flow().setExtraCharge('c1', true);
    flow().setNotes('x');
    expect(state().requestId, id, reason: 'a retried Confirm must reuse the key');
  });

  test('add-ons can be ticked and unticked', () {
    flow().setExtraCharge('c1', true);
    flow().setExtraCharge('c2', true);
    expect(state().extraChargeIds, {'c1', 'c2'});
    flow().setExtraCharge('c1', false);
    expect(state().extraChargeIds, {'c2'});
    flow().setExtraCharge('c1', false);
    expect(state().extraChargeIds, {'c2'});
  });

  test('reset clears the booking and issues a new request id', () {
    final s = service();
    flow().start(s, s.packages.first);
    final id = state().requestId;
    flow().reset();
    expect(state().hasPackage, isFalse);
    expect(state().requestId, isNot(id));
  });

  test('history filters map to the right statuses', () {
    expect(BookingFilter.all.statuses, isNull);
    expect(BookingFilter.completed.statuses, hasLength(1));
    expect(BookingFilter.cancelled.statuses, hasLength(1));
    expect(BookingFilter.active.statuses, hasLength(5));
    expect(
      BookingFilter.active.statuses!.map((s) => s.apiValue),
      isNot(contains('completed')),
    );
  });
}
