import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/areas/admin_areas_screen.dart';
import '../../features/admin/availability/admin_availability_screen.dart';
import '../../features/admin/bookings/admin_booking_detail_screen.dart';
import '../../features/admin/bookings/admin_bookings_screen.dart';
import '../../features/admin/catalog/admin_service_detail_screen.dart';
import '../../features/admin/catalog/admin_services_screen.dart';
import '../../features/admin/catalog/charge_form_screen.dart';
import '../../features/admin/catalog/package_form_screen.dart';
import '../../features/admin/catalog/service_form_screen.dart';
import '../../features/admin/drivers/admin_driver_detail_screen.dart';
import '../../features/admin/drivers/admin_drivers_screen.dart';
import '../../features/admin/drivers/driver_create_screen.dart';
import '../../features/admin/presentation/admin_home_screen.dart';
import '../../features/auth/presentation/admin_login_screen.dart';
import '../../features/auth/presentation/customer_login_screen.dart';
import '../../features/auth/presentation/driver_login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/booking/presentation/booking_address_screen.dart';
import '../../features/booking/presentation/booking_detail_screen.dart';
import '../../features/booking/presentation/booking_edit_screen.dart';
import '../../features/booking/presentation/booking_history_screen.dart';
import '../../features/booking/presentation/booking_schedule_screen.dart';
import '../../features/booking/presentation/booking_summary_screen.dart';
import '../../features/catalog/presentation/browse_services_screen.dart';
import '../../features/catalog/presentation/service_detail_screen.dart';
import '../../features/driver/presentation/driver_job_screen.dart';
import '../../features/home/presentation/customer_home_screen.dart';
import '../../features/home/presentation/driver_home_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/payment/presentation/payment_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/support/presentation/support_screen.dart';
import 'app_routes.dart';
import 'auth_redirect.dart';

/// Re-runs the router's redirect whenever the auth state changes.
class _AuthRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// App-wide router. The redirect is driven by [authControllerProvider]; the
/// router itself is built once and never recreated on sign-in or sign-out.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh();
  ref.listen<AppAuthState>(authControllerProvider, (_, __) => refresh.notify());

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      return authRedirect(
        status: auth.status,
        role: auth.role,
        location: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (context, state) => const CustomerLoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.driverLogin,
        name: 'driver-login',
        builder: (context, state) => const DriverLoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminLogin,
        name: 'admin-login',
        builder: (context, state) => const AdminLoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.customerHome,
        name: 'customer-home',
        builder: (context, state) => const CustomerHomeScreen(),
        routes: [
          GoRoute(
            path: 'services',
            name: 'browse-services',
            builder: (context, state) => const BrowseServicesScreen(),
            routes: [
              GoRoute(
                path: ':id',
                name: 'service-detail',
                builder: (context, state) =>
                    ServiceDetailScreen(serviceId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: 'book-address',
            name: 'book-address',
            builder: (context, state) => const BookingAddressScreen(),
          ),
          GoRoute(
            path: 'book-schedule',
            name: 'book-schedule',
            builder: (context, state) => const BookingScheduleScreen(),
          ),
          GoRoute(
            path: 'book-summary',
            name: 'book-summary',
            builder: (context, state) => const BookingSummaryScreen(),
          ),
          GoRoute(
            path: 'notifications',
            name: 'notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
          GoRoute(
            path: 'bookings',
            name: 'bookings',
            builder: (context, state) => const BookingHistoryScreen(),
            routes: [
              GoRoute(
                path: ':id',
                name: 'booking',
                builder: (context, state) => BookingDetailScreen(
                  bookingId: state.pathParameters['id']!,
                  justCreated: state.uri.queryParameters['created'] == '1',
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    name: 'booking-edit',
                    builder: (context, state) => BookingEditScreen(
                      bookingId: state.pathParameters['id']!,
                    ),
                  ),
                  GoRoute(
                    path: 'pay',
                    name: 'booking-pay',
                    builder: (context, state) => PaymentScreen(
                      bookingId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.adminHome,
        name: 'admin-home',
        builder: (context, state) => const AdminHomeScreen(),
        routes: [
          GoRoute(
            path: 'services',
            name: 'admin-services',
            builder: (context, state) => const AdminServicesScreen(),
            routes: [
              // "new" is declared before ":id" so it is not read as an id.
              GoRoute(
                path: 'new',
                name: 'admin-service-new',
                builder: (context, state) => const ServiceFormScreen(),
              ),
              GoRoute(
                path: ':id',
                name: 'admin-service',
                builder: (context, state) => AdminServiceDetailScreen(
                  serviceId: state.pathParameters['id']!,
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    name: 'admin-service-edit',
                    builder: (context, state) => ServiceFormScreen(
                      serviceId: state.pathParameters['id']!,
                    ),
                  ),
                  GoRoute(
                    path: 'packages/:packageId',
                    name: 'admin-package',
                    builder: (context, state) => PackageFormScreen(
                      serviceId: state.pathParameters['id']!,
                      packageId: state.pathParameters['packageId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'charges/:chargeId',
                    name: 'admin-charge',
                    builder: (context, state) => ChargeFormScreen(
                      serviceId: state.pathParameters['id']!,
                      chargeId: state.pathParameters['chargeId']!,
                      initialPackageId: state.uri.queryParameters['package'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: 'areas',
            name: 'admin-areas',
            builder: (context, state) => const AdminAreasScreen(),
          ),
          GoRoute(
            path: 'availability',
            name: 'admin-availability',
            builder: (context, state) => const AdminAvailabilityScreen(),
          ),
          GoRoute(
            path: 'bookings',
            name: 'admin-bookings',
            builder: (context, state) => const AdminBookingsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                name: 'admin-booking',
                builder: (context, state) => AdminBookingDetailScreen(
                  bookingId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'drivers',
            name: 'admin-drivers',
            builder: (context, state) => const AdminDriversScreen(),
            routes: [
              // "new" is declared before ":id" so it is not read as an id.
              GoRoute(
                path: 'new',
                name: 'admin-driver-new',
                builder: (context, state) => const DriverCreateScreen(),
              ),
              GoRoute(
                path: ':id',
                name: 'admin-driver',
                builder: (context, state) => AdminDriverDetailScreen(
                  driverId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.driverHome,
        name: 'driver-home',
        builder: (context, state) => const DriverHomeScreen(),
        routes: [
          GoRoute(
            path: 'bookings/:id',
            name: 'driver-booking',
            builder: (context, state) => DriverJobScreen(
              bookingId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.profile,
        name: 'profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.support,
        name: 'support',
        builder: (context, state) => SupportScreen(
          bookingCode: state.uri.queryParameters['booking'],
        ),
      ),
    ],
    errorBuilder: (context, state) => const Scaffold(
      body: Center(child: Text('Page not found')),
    ),
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
