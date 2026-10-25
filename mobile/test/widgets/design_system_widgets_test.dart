import 'package:ff_garage/app/theme/app_colors.dart';
import 'package:ff_garage/app/theme/app_theme.dart';
import 'package:ff_garage/core/widgets/brand_logo.dart';
import 'package:ff_garage/core/widgets/filter_pill.dart';
import 'package:ff_garage/core/widgets/section_header.dart';
import 'package:ff_garage/core/widgets/service_icon.dart';
import 'package:ff_garage/core/widgets/stat_tile.dart';
import 'package:ff_garage/core/widgets/status_badge.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/features/booking/presentation/booking_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Color? _badgeColor(WidgetTester tester, String label) {
  final container = tester.widget<Container>(
    find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
  );
  return (container.decoration as BoxDecoration?)?.color;
}

void main() {
  group('StatusBadge', () {
    testWidgets('uses the design system colour for each tone', (tester) async {
      await tester.pumpWidget(_host(const Column(
        children: [
          StatusBadge(label: 'Ongoing', tone: BadgeTone.info),
          StatusBadge(label: 'Done', tone: BadgeTone.success),
          StatusBadge(label: 'Pending', tone: BadgeTone.warning),
          StatusBadge(label: 'Cancelled', tone: BadgeTone.danger),
        ],
      )));
      expect(_badgeColor(tester, 'Ongoing'), AppColors.primarySoft);
      expect(_badgeColor(tester, 'Done'), AppColors.secondarySoft);
      expect(_badgeColor(tester, 'Pending'), AppColors.accentSoft);
      expect(_badgeColor(tester, 'Cancelled'), AppColors.errorSoft);
    });

    testWidgets('shows an icon next to the label when given one',
        (tester) async {
      await tester.pumpWidget(_host(const StatusBadge(
        label: 'Done',
        tone: BadgeTone.success,
        icon: Icons.check_circle,
      )));
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });
  });

  group('BookingStatusChip', () {
    testWidgets('keeps the status wording and tone for every status',
        (tester) async {
      await tester.pumpWidget(_host(Column(
        children: [
          for (final status in BookingStatus.values)
            BookingStatusChip(status: status),
        ],
      )));
      expect(find.byType(StatusBadge), findsNWidgets(BookingStatus.values.length));
      expect(
        tester
            .widget<StatusBadge>(find.byType(StatusBadge).at(
                BookingStatus.values.indexOf(BookingStatus.completed)))
            .tone,
        BadgeTone.success,
      );
      expect(
        tester
            .widget<StatusBadge>(find.byType(StatusBadge).at(
                BookingStatus.values.indexOf(BookingStatus.cancelled)))
            .tone,
        BadgeTone.danger,
      );
      expect(
        tester
            .widget<StatusBadge>(find.byType(StatusBadge).at(
                BookingStatus.values.indexOf(BookingStatus.pendingPayment)))
            .tone,
        BadgeTone.warning,
      );
    });
  });

  group('FilterPill', () {
    testWidgets('is a ChoiceChip that reports taps and selection',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(Row(
        children: [
          FilterPill(label: 'All', selected: true, onSelected: () => taps++),
          FilterPill(label: 'Upcoming', selected: false, onSelected: () => taps++),
        ],
      )));
      expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All')).selected,
        isTrue,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Upcoming'))
            .selected,
        isFalse,
      );
      await tester.tap(find.text('Upcoming'));
      expect(taps, 1);
    });
  });

  group('StatTile and StatGrid', () {
    testWidgets('show the label and value, and lay out two per row',
        (tester) async {
      await tester.pumpWidget(_host(const StatGrid(tiles: [
        StatTile(label: 'Total Bookings', value: '12'),
        StatTile(label: 'Completed', value: '7', color: AppColors.success),
        StatTile(label: 'Pending', value: '3', color: AppColors.accent),
      ])));
      expect(find.text('Total Bookings'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      final first = tester.getTopLeft(find.widgetWithText(StatTile, 'Total Bookings'));
      final second = tester.getTopLeft(find.widgetWithText(StatTile, 'Completed'));
      final third = tester.getTopLeft(find.widgetWithText(StatTile, 'Pending'));
      expect(second.dy, first.dy);
      expect(second.dx, greaterThan(first.dx));
      expect(third.dy, greaterThan(first.dy));
      expect(third.dx, first.dx);
    });

    testWidgets('a tile with onTap responds to taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(
        StatTile(label: 'Drivers', value: '4', onTap: () => taps++),
      ));
      await tester.tap(find.text('Drivers'));
      expect(taps, 1);
    });
  });

  group('SectionHeader', () {
    testWidgets('shows the action only when there is a label', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(
        SectionHeader(
          title: 'Popular Services',
          actionLabel: 'See All',
          onAction: () => taps++,
        ),
      ));
      expect(find.text('Popular Services'), findsOneWidget);
      await tester.tap(find.text('See All'));
      expect(taps, 1);

      await tester.pumpWidget(_host(const SectionHeader(title: 'Manage')));
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('BrandLogo', () {
    testWidgets('shows the logo picture whole, never stretched', (tester) async {
      await tester.pumpWidget(_host(const BrandLogo(size: 64)));
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.contain);
      expect(image.width, 64);
      expect(image.height, 64);
      expect((image.image as AssetImage).assetName, BrandAssets.logo);
    });

    testWidgets('falls back to a badge when the picture is missing',
        (tester) async {
      await tester.pumpWidget(_host(const BrandLogo(size: 64)));
      final image = tester.widget<Image>(find.byType(Image));
      final fallback = image.errorBuilder!(
        tester.element(find.byType(Image)),
        Exception('missing'),
        StackTrace.empty,
      );
      await tester.pumpWidget(_host(fallback));
      expect(find.byIcon(Icons.two_wheeler), findsOneWidget);
    });
  });

  group('serviceIconFor', () {
    test('maps known categories and falls back to a spanner', () {
      expect(serviceIconFor('Brakes'), Icons.stop_circle_outlined);
      expect(serviceIconFor('Tyre care'), Icons.tire_repair);
      expect(serviceIconFor('Battery'), Icons.battery_charging_full);
      expect(serviceIconFor('Something else'), Icons.build_outlined);
    });
  });

  group('theme', () {
    test('uses the reference palette and the Inter font', () {
      final theme = AppTheme.light();
      expect(theme.colorScheme.primary, AppColors.primary);
      expect(theme.colorScheme.secondary, AppColors.secondary);
      expect(theme.colorScheme.error, AppColors.error);
      expect(theme.scaffoldBackgroundColor, AppColors.background);
      expect(theme.textTheme.bodyLarge?.fontFamily, AppTheme.fontFamily);
    });

    test('dark theme builds', () {
      expect(AppTheme.dark().brightness, Brightness.dark);
    });
  });
}
