import 'package:ff_garage/data/models/availability.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/models/service_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes_booking.dart';
import 'fakes_catalog.dart';
import 'fakes_notification.dart';
import 'fakes_payment.dart';
import 'pump_app.dart';

DateTime today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

DateTime tomorrow() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + 1);
}

DateTime dayAfterTomorrow() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + 2);
}

String dayKey(DateTime d) =>
    'day-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Today (too late for its only slot), tomorrow (two open slots and a full
/// one) and the day after (closed). Built from the device clock because the
/// app's date range starts at the device's today.
List<DayAvailability> openDays() => [
      DayAvailability(
        date: today(),
        isOpen: true,
        slots: const [
          SlotAvailability(
            slotId: 'late',
            start: ClockTime(7, 0),
            end: ClockTime(8, 0),
            available: false,
            reason: 'lead_time_passed',
            spotsLeft: 0,
          ),
        ],
      ),
      DayAvailability(
        date: tomorrow(),
        isOpen: true,
        slots: const [
          SlotAvailability(
            slotId: 'slot1',
            start: ClockTime(9, 0),
            end: ClockTime(11, 0),
            available: true,
            spotsLeft: 2,
          ),
          SlotAvailability(
            slotId: 'slot2',
            start: ClockTime(12, 0),
            end: ClockTime(14, 0),
            available: true,
            spotsLeft: 1,
          ),
          SlotAvailability(
            slotId: 'slot3',
            start: ClockTime(15, 0),
            end: ClockTime(17, 0),
            available: false,
            reason: 'fully_booked',
            spotsLeft: 0,
          ),
        ],
      ),
      DayAvailability(
        date: dayAfterTomorrow(),
        isOpen: false,
        closedReason: 'closed',
        slots: const [],
      ),
    ];

const ServiceArea bengaluru = ServiceArea(
  id: 'a1',
  pincode: '560001',
  areaName: 'MG Road',
  city: 'Bengaluru',
  state: 'Karnataka',
  isActive: true,
);

AppHarness customerHarness({
  FakeBookingRepository? bookings,
  List<DayAvailability>? days,
  FakePaymentRepository? payments,
  FakeCheckoutLauncher? launcher,
  FakeNotificationRepository? notifications,
  Duration? pollInterval,
}) {
  final availability = FakeAvailabilityRepository()
    ..days = days ?? openDays();
  return AppHarness(
    role: UserRole.customer,
    areas: FakeServiceAreaRepository([bengaluru]),
    availability: availability,
    bookingRepo: bookings,
    paymentRepo: payments,
    launcher: launcher,
    notifications: notifications,
    pollInterval: pollInterval,
  );
}

/// A tall phone, so long forms and lists are laid out without scrolling.
void useTallScreen(WidgetTester tester, {double height = 2400}) {
  tester.view.physicalSize = Size(800, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  expect(finder, findsOneWidget, reason: 'no widget with key $key');
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> tapButton(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(FilledButton, label);
  expect(finder, findsOneWidget, reason: 'no button "$label"');
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

bool buttonEnabled(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, label))
        .onPressed !=
    null;

/// Home -> Browse services -> service -> "Book this package".
Future<void> startBooking(WidgetTester tester) async {
  await tapText(tester, 'Browse services');
  await tapText(tester, 'General Service');
  await tapKey(tester, 'book-p1');
}

Future<void> fillAddress(
  WidgetTester tester, {
  String pincode = '560001',
  String address = '12 MG Road, Flat 4',
  String? landmark,
}) async {
  await enter(tester, 'PIN code', pincode);
  await enter(tester, 'House / flat, street and area', address);
  if (landmark != null) {
    await enter(tester, 'Landmark (optional)', landmark);
  }
}

/// Address step done, on the schedule screen.
Future<void> toSchedule(WidgetTester tester, {String? landmark}) async {
  await startBooking(tester);
  await fillAddress(tester, landmark: landmark);
  await tapButton(tester, 'Continue');
}

/// Tomorrow 9:00 AM - 11:00 AM chosen, on the summary screen.
Future<void> toSummary(WidgetTester tester, {String? landmark}) async {
  await toSchedule(tester, landmark: landmark);
  await tapKey(tester, dayKey(tomorrow()));
  await tapKey(tester, 'slot-slot1');
  await tapButton(tester, 'Continue');
}
