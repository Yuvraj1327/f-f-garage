import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/models/availability.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/models/service_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes_catalog.dart';
import '../support/pump_app.dart';
import '../support/booking_journey.dart';

ServiceArea area({
  String id = 'a1',
  String pincode = '560001',
  bool isActive = true,
}) =>
    ServiceArea(
      id: id,
      pincode: pincode,
      areaName: 'MG Road',
      city: 'Bengaluru',
      state: 'Karnataka',
      isActive: isActive,
    );

TimeSlot slot({String id = 'sl1', bool isActive = true}) => TimeSlot(
      id: id,
      start: const ClockTime(9, 0),
      end: const ClockTime(11, 0),
      capacity: 2,
      daysOfWeek: const [1, 2, 3, 4, 5],
      isActive: isActive,
    );

void main() {
  group('service areas', () {
    Future<AppHarness> open(
      WidgetTester tester,
      List<ServiceArea> areas,
    ) async {
      final harness = AppHarness(
        role: UserRole.admin,
        areas: FakeServiceAreaRepository(areas),
      );
      await harness.pump(tester);
      await tapKey(tester, 'side-areas');
      return harness;
    }

    testWidgets('lists areas and filters with the search box', (tester) async {
      await open(tester, [area(), area(id: 'a2', pincode: '110001')]);
      expect(find.text('560001'), findsOneWidget);
      expect(find.text('110001'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Search PIN code, area or city'),
        '1100',
      );
      await tester.pumpAndSettle();
      expect(find.text('560001'), findsNothing);
      expect(find.text('110001'), findsOneWidget);
    });

    testWidgets('adding validates the PIN code first', (tester) async {
      final harness = await open(tester, []);
      await tapText(tester, 'Add PIN code');
      await enter(tester, 'PIN code', '012345');
      await tapText(tester, 'Save');

      expect(find.text('Enter a valid 6-digit PIN code'), findsOneWidget);
      expect(find.text('Enter the area name'), findsOneWidget);
      expect(harness.areas.calls.where((c) => c.startsWith('create')), isEmpty);
    });

    testWidgets('a valid area is created and listed', (tester) async {
      final harness = await open(tester, []);
      await tapText(tester, 'Add PIN code');
      await enter(tester, 'PIN code', '560 001');
      await enter(tester, 'Area name', 'MG Road');
      await enter(tester, 'City', 'Bengaluru');
      await enter(tester, 'State', 'Karnataka');
      await tapText(tester, 'Save');

      expect(
        harness.areas.calls,
        contains('create:560001:MG Road:Bengaluru:Karnataka:true'),
      );
      expect(find.text('560001'), findsOneWidget);
    });

    testWidgets('a duplicate PIN code shows the server message in the dialog',
        (tester) async {
      final harness = await open(tester, [area()]);
      await tapText(tester, 'Add PIN code');
      await enter(tester, 'PIN code', '560001');
      await enter(tester, 'Area name', 'Other');
      await enter(tester, 'City', 'Bengaluru');
      await enter(tester, 'State', 'Karnataka');
      harness.areas.error = conflictError;
      await tapText(tester, 'Save');

      expect(
        find.text('A service area with this PIN code already exists'),
        findsOneWidget,
      );
      expect(find.text('Add service area'), findsOneWidget);
    });

    testWidgets('the switch deactivates an area', (tester) async {
      final harness = await open(tester, [area()]);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(harness.areas.lastChanges, {'is_active': false});
      expect(find.text('Inactive'), findsOneWidget);
    });

    testWidgets('removing needs confirmation', (tester) async {
      final harness = await open(tester, [area()]);
      await tester.tap(find.byTooltip('Remove 560001'));
      await tester.pumpAndSettle();
      expect(find.text('Remove 560001?'), findsOneWidget);

      await tapText(tester, 'Cancel');
      expect(harness.areas.calls.where((c) => c.startsWith('delete')), isEmpty);

      await tester.tap(find.byTooltip('Remove 560001'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Remove');
      expect(harness.areas.calls, contains('delete:a1'));
      expect(find.text('560001'), findsNothing);
    });
  });

  group('availability', () {
    Future<AppHarness> open(
      WidgetTester tester, {
      List<TimeSlot>? slots,
    }) async {
      final harness = AppHarness(
        role: UserRole.admin,
        availability: FakeAvailabilityRepository(slots: slots),
      );
      await harness.pump(tester);
      await tapKey(tester, 'side-availability');
      return harness;
    }

    testWidgets('lists the weekly time slots', (tester) async {
      await open(tester, slots: [slot()]);
      expect(find.text(slot().label), findsOneWidget);
    });

    testWidgets('a new slot rejects an invalid capacity', (tester) async {
      final harness = await open(tester);
      await tapText(tester, 'Add slot');
      await enter(tester, 'Bookings at a time', '0');
      await tapText(tester, 'Save');

      expect(find.text('Enter a whole number from 1 to 50'), findsOneWidget);
      expect(
        harness.availability.calls.where((c) => c.startsWith('createSlot')),
        isEmpty,
      );
    });

    testWidgets('a slot is created with the default window and all days',
        (tester) async {
      final harness = await open(tester);
      await tapText(tester, 'Add slot');
      await enter(tester, 'Bookings at a time', '3');
      await tapText(tester, 'Save');

      expect(
        harness.availability.calls,
        contains('createSlot:09:00-11:00:3:1,2,3,4,5,6,7'),
      );
    });

    testWidgets('an overlap error from the server stays in the dialog',
        (tester) async {
      final harness = await open(tester, slots: [slot()]);
      await tapText(tester, 'Add slot');
      harness.availability.error = const ApiException(
        type: ApiErrorType.conflict,
        message: 'This time overlaps another slot',
        statusCode: 409,
      );
      await tapText(tester, 'Save');
      expect(find.text('Add time slot'), findsOneWidget);
      expect(find.text('This time overlaps another slot'), findsOneWidget);
    });

    testWidgets('deleting a slot needs confirmation', (tester) async {
      final harness = await open(tester, slots: [slot()]);
      await tester.tap(find.byTooltip('Delete ${slot().label}'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Cancel');
      expect(
        harness.availability.calls.where((c) => c.startsWith('deleteSlot')),
        isEmpty,
      );

      await tester.tap(find.byTooltip('Delete ${slot().label}'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Delete');
      expect(harness.availability.calls, contains('deleteSlot:sl1'));
    });

    testWidgets('a whole-day closure can be added with a reason',
        (tester) async {
      final harness = await open(tester);
      await tapText(tester, 'Closures');
      await tapText(tester, 'Add closure');
      await enter(tester, 'Reason (optional)', 'Closed for Diwali');
      await tapText(tester, 'Save');

      expect(
        harness.availability.calls,
        contains('createException:null:false:null:Closed for Diwali'),
      );
    });
  });
}
