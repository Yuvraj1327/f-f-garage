import 'package:ff_garage/app/router/app_routes.dart';
import 'package:ff_garage/app/router/auth_redirect.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/features/auth/providers/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';

String? _go(AuthStatus status, UserRole? role, String location) =>
    authRedirect(status: status, role: role, location: location);

void main() {
  group('while the session is being checked', () {
    for (final status in [AuthStatus.unknown, AuthStatus.connectionError]) {
      test('$status keeps everyone on the splash screen', () {
        expect(_go(status, null, AppRoutes.splash), isNull);
        expect(_go(status, null, AppRoutes.login), AppRoutes.splash);
        expect(_go(status, null, AppRoutes.customerHome), AppRoutes.splash);
        expect(_go(status, null, AppRoutes.driverHome), AppRoutes.splash);
      });
    }
  });

  group('signed out', () {
    test('may open only the login and register screens', () {
      for (final route in [
        AppRoutes.login,
        AppRoutes.register,
        AppRoutes.driverLogin,
      ]) {
        expect(_go(AuthStatus.unauthenticated, null, route), isNull);
      }
    });
    test('is sent to login from everywhere else', () {
      for (final route in [
        AppRoutes.splash,
        AppRoutes.customerHome,
        AppRoutes.driverHome,
        AppRoutes.profile,
      ]) {
        expect(
          _go(AuthStatus.unauthenticated, null, route),
          AppRoutes.login,
          reason: route,
        );
      }
    });
  });

  group('customer', () {
    test('lands on the customer home from splash and login screens', () {
      for (final route in [
        AppRoutes.splash,
        AppRoutes.login,
        AppRoutes.register,
        AppRoutes.driverLogin,
      ]) {
        expect(
          _go(AuthStatus.authenticated, UserRole.customer, route),
          AppRoutes.customerHome,
        );
      }
    });
    test('cannot open the driver area', () {
      expect(
        _go(AuthStatus.authenticated, UserRole.customer, AppRoutes.driverHome),
        AppRoutes.customerHome,
      );
    });
    test('can open home and profile', () {
      expect(
        _go(AuthStatus.authenticated, UserRole.customer, AppRoutes.customerHome),
        isNull,
      );
      expect(
        _go(AuthStatus.authenticated, UserRole.customer, AppRoutes.profile),
        isNull,
      );
    });
  });

  group('driver', () {
    test('lands on the driver home and cannot open the customer area', () {
      expect(
        _go(AuthStatus.authenticated, UserRole.driver, AppRoutes.login),
        AppRoutes.driverHome,
      );
      expect(
        _go(AuthStatus.authenticated, UserRole.driver, AppRoutes.customerHome),
        AppRoutes.driverHome,
      );
      expect(
        _go(AuthStatus.authenticated, UserRole.driver, AppRoutes.driverHome),
        isNull,
      );
      expect(
        _go(AuthStatus.authenticated, UserRole.driver, AppRoutes.profile),
        isNull,
      );
    });
  });

  group('admin', () {
    test('lands on the admin home and stays inside /admin', () {
      expect(homeFor(UserRole.admin), AppRoutes.adminHome);
      for (final route in [
        AppRoutes.splash,
        AppRoutes.login,
        AppRoutes.adminLogin,
        AppRoutes.customerHome,
        AppRoutes.driverHome,
        AppRoutes.browseServices,
      ]) {
        expect(
          _go(AuthStatus.authenticated, UserRole.admin, route),
          AppRoutes.adminHome,
          reason: route,
        );
      }
      for (final route in [
        AppRoutes.adminHome,
        AppRoutes.adminServices,
        AppRoutes.adminService('abc'),
        AppRoutes.adminPackage('abc', AppRoutes.newItem),
        AppRoutes.adminAreas,
        AppRoutes.adminAvailability,
        AppRoutes.profile,
      ]) {
        expect(_go(AuthStatus.authenticated, UserRole.admin, route), isNull, reason: route);
      }
    });

    test('the admin sign-in screen is public', () {
      expect(_go(AuthStatus.unauthenticated, null, AppRoutes.adminLogin), isNull);
    });
  });

  group('area separation', () {
    final adminPages = [
      AppRoutes.adminHome,
      AppRoutes.adminServices,
      AppRoutes.adminServiceNew,
      AppRoutes.adminService('abc'),
      AppRoutes.adminServiceEdit('abc'),
      AppRoutes.adminCharge('abc', 'new'),
      AppRoutes.adminAreas,
      AppRoutes.adminAvailability,
      AppRoutes.adminBookings,
      AppRoutes.adminBooking('abc'),
      AppRoutes.adminDrivers,
      AppRoutes.adminDriverNew,
      AppRoutes.adminDriver('abc'),
    ];

    test('signed-out users are sent to login from every admin page', () {
      for (final route in adminPages) {
        expect(_go(AuthStatus.unauthenticated, null, route), AppRoutes.login, reason: route);
      }
    });

    test('customers and drivers cannot open any admin page', () {
      for (final route in adminPages) {
        expect(
          _go(AuthStatus.authenticated, UserRole.customer, route),
          AppRoutes.customerHome,
          reason: route,
        );
        expect(
          _go(AuthStatus.authenticated, UserRole.driver, route),
          AppRoutes.driverHome,
          reason: route,
        );
      }
    });

    test('customers can open the catalogue pages under /home', () {
      for (final route in [
        AppRoutes.browseServices,
        AppRoutes.serviceDetail('abc'),
      ]) {
        expect(_go(AuthStatus.authenticated, UserRole.customer, route), isNull, reason: route);
        expect(
          _go(AuthStatus.authenticated, UserRole.driver, route),
          AppRoutes.driverHome,
          reason: route,
        );
      }
    });

    test('only customers can open the booking pages', () {
      final pages = [
        AppRoutes.notifications,
        AppRoutes.bookAddress,
        AppRoutes.bookSchedule,
        AppRoutes.bookSummary,
        AppRoutes.bookings,
        AppRoutes.booking('abc'),
        AppRoutes.bookingEdit('abc'),
        AppRoutes.bookingPay('abc'),
      ];
      for (final route in pages) {
        expect(_go(AuthStatus.authenticated, UserRole.customer, route), isNull, reason: route);
        expect(_go(AuthStatus.authenticated, UserRole.driver, route), AppRoutes.driverHome, reason: route);
        expect(_go(AuthStatus.authenticated, UserRole.admin, route), AppRoutes.adminHome, reason: route);
        expect(_go(AuthStatus.unauthenticated, null, route), AppRoutes.login, reason: route);
      }
    });

    test('only drivers can open a driver booking', () {
      final route = AppRoutes.driverBooking('abc');
      expect(_go(AuthStatus.authenticated, UserRole.driver, route), isNull);
      expect(
        _go(AuthStatus.authenticated, UserRole.customer, route),
        AppRoutes.customerHome,
      );
      expect(
        _go(AuthStatus.authenticated, UserRole.admin, route),
        AppRoutes.adminHome,
      );
      expect(_go(AuthStatus.unauthenticated, null, route), AppRoutes.login);
    });

    test('a lookalike prefix does not count as inside an area', () {
      expect(
        _go(AuthStatus.authenticated, UserRole.driver, '/driver-login'),
        AppRoutes.driverHome,
      );
      expect(
        _go(AuthStatus.authenticated, UserRole.customer, '/homepage'),
        AppRoutes.customerHome,
      );
      expect(
        _go(AuthStatus.authenticated, UserRole.admin, '/administrator'),
        AppRoutes.adminHome,
      );
    });
  });

  group('support screen', () {
    test('every signed-in role may open it', () {
      for (final role in UserRole.values) {
        expect(
          _go(AuthStatus.authenticated, role, AppRoutes.support),
          isNull,
          reason: '$role',
        );
      }
    });

    test('signed-out users are sent to login', () {
      expect(
        _go(AuthStatus.unauthenticated, null, AppRoutes.support),
        AppRoutes.login,
      );
    });

    test('is not reachable while the session is being checked', () {
      expect(
        _go(AuthStatus.unknown, null, AppRoutes.support),
        AppRoutes.splash,
      );
    });

    test('a booking link carries the code in the query', () {
      expect(AppRoutes.supportForBooking('FF-000007'),
          '/support?booking=FF-000007');
    });
  });
}
