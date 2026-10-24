import 'package:ff_garage/app/app.dart';
import 'package:ff_garage/app/router/app_router.dart';
import 'package:ff_garage/core/config/app_config.dart';
import 'package:ff_garage/core/providers/core_providers.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/providers/data_providers.dart';
import 'package:ff_garage/features/notifications/providers/notification_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'fakes_booking.dart';
import 'fakes_catalog.dart';
import 'fakes_driver.dart';
import 'fakes_notification.dart';
import 'fakes_payment.dart';
import 'fakes_support.dart';

class AppHarness {
  AppHarness({
    required this.role,
    FakeCatalogRepository? catalog,
    FakeServiceAreaRepository? areas,
    FakeAvailabilityRepository? availability,
    FakeBookingRepository? bookingRepo,
    FakePaymentRepository? paymentRepo,
    FakeCheckoutLauncher? launcher,
    FakeAdminBookingRepository? adminBookings,
    FakeAdminDriverRepository? adminDrivers,
    FakeDriverWorkRepository? driverWork,
    FakeNotificationRepository? notifications,
    FakeSupportRepository? support,
    FakeContactLauncher? contactLauncher,
    Duration? pollInterval,
  })  : support = support ?? FakeSupportRepository(),
        contactLauncher = contactLauncher ?? FakeContactLauncher(),
        notifications = notifications ?? FakeNotificationRepository(),
        pollInterval = pollInterval ?? const Duration(days: 1),
        adminBookings = adminBookings ?? FakeAdminBookingRepository(),
        adminDrivers = adminDrivers ?? FakeAdminDriverRepository(),
        driverWork = driverWork ?? FakeDriverWorkRepository(),
        bookingRepo = bookingRepo ?? FakeBookingRepository(),
        launcher = launcher ?? FakeCheckoutLauncher(),
        catalog = catalog ?? FakeCatalogRepository([service()]),
        areas = areas ?? FakeServiceAreaRepository([]),
        availability = availability ?? FakeAvailabilityRepository() {
    this.paymentRepo = paymentRepo ?? FakePaymentRepository(this.bookingRepo);
  }

  final UserRole role;
  final FakeCatalogRepository catalog;
  final FakeServiceAreaRepository areas;
  final FakeAvailabilityRepository availability;
  final FakeBookingRepository bookingRepo;
  late final FakePaymentRepository paymentRepo;
  final FakeCheckoutLauncher launcher;
  final FakeAdminBookingRepository adminBookings;
  final FakeAdminDriverRepository adminDrivers;
  final FakeDriverWorkRepository driverWork;
  final FakeNotificationRepository notifications;
  final FakeSupportRepository support;
  final FakeContactLauncher contactLauncher;

  /// How often screens check for booking updates. Long by default so no test
  /// sees a surprise reload; tests of live updates pass a short one.
  final Duration pollInterval;
  final FakeAuthGateway gateway = FakeAuthGateway(hasStoredSession: true);

  /// Starts the whole app signed in as [role] and settles on the home screen.
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://x',
              supabaseUrl: 'http://x',
              supabaseAnonKey: 'anon',
            ),
          ),
          authGatewayProvider.overrideWithValue(gateway),
          profileRepositoryProvider.overrideWithValue(
            FakeProfileRepository(profileFor(role)),
          ),
          catalogRepositoryProvider.overrideWithValue(catalog),
          serviceAreaRepositoryProvider.overrideWithValue(areas),
          availabilityRepositoryProvider.overrideWithValue(availability),
          bookingRepositoryProvider.overrideWithValue(bookingRepo),
          paymentRepositoryProvider.overrideWithValue(paymentRepo),
          checkoutLauncherProvider.overrideWithValue(launcher),
          adminBookingRepositoryProvider.overrideWithValue(adminBookings),
          adminDriverRepositoryProvider.overrideWithValue(adminDrivers),
          driverWorkRepositoryProvider.overrideWithValue(driverWork),
          notificationRepositoryProvider.overrideWithValue(notifications),
          supportRepositoryProvider.overrideWithValue(support),
          contactLauncherProvider.overrideWithValue(contactLauncher),
          trackingPollIntervalProvider.overrideWithValue(pollInterval),
        ],
        child: const FfGarageApp(),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

Future<void> enter(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(field(label));
  await tester.enterText(field(label), text);
}

/// Navigates the running app like a deep link would.
void goTo(WidgetTester tester, String location) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(FfGarageApp)),
  );
  container.read(routerProvider).go(location);
}
