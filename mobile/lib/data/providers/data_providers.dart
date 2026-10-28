import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/core_providers.dart';
import '../repositories/admin_booking_repository.dart';
import '../repositories/admin_driver_repository.dart';
import '../repositories/auth_repository.dart';
import '../repositories/availability_repository.dart';
import '../repositories/billing_repository.dart';
import '../repositories/booking_repository.dart';
import '../repositories/catalog_repository.dart';
import '../repositories/driver_work_repository.dart';
import '../repositories/garage_settings_repository.dart';
import '../repositories/health_repository.dart';
import '../repositories/maps_repository.dart';
import '../repositories/notification_repository.dart';
import '../repositories/payment_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/service_area_repository.dart';
import '../repositories/support_repository.dart';
import '../repositories/vehicle_repository.dart';
import '../services/admin_booking_api_service.dart';
import '../services/admin_driver_api_service.dart';
import '../services/availability_api_service.dart';
import '../services/billing_api_service.dart';
import '../services/booking_api_service.dart';
import '../services/catalog_api_service.dart';
import '../services/checkout_launcher.dart';
import '../services/contact_launcher.dart';
import '../services/driver_work_api_service.dart';
import '../services/garage_settings_api_service.dart';
import '../services/health_api_service.dart';
import '../services/location_service.dart';
import '../services/maps_api_service.dart';
import '../services/notification_api_service.dart';
import '../services/payment_api_service.dart';
import '../services/profile_api_service.dart';
import '../services/service_area_api_service.dart';
import '../services/support_api_service.dart';
import '../services/vehicle_api_service.dart';

/// Wiring for the data layer: ApiClient -> service -> repository.
/// Each later feature adds its own service and repository providers here.
final healthApiServiceProvider = Provider<HealthApiService>(
  (ref) => HealthApiService(ref.watch(apiClientProvider)),
);

final healthRepositoryProvider = Provider<HealthRepository>(
  (ref) => HealthRepository(ref.watch(healthApiServiceProvider)),
);

final profileApiServiceProvider = Provider<ProfileApiService>(
  (ref) => ProfileApiService(ref.watch(apiClientProvider)),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(profileApiServiceProvider)),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    gateway: ref.watch(authGatewayProvider),
    profiles: ref.watch(profileRepositoryProvider),
    config: ref.watch(appConfigProvider),
  ),
);

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(CatalogApiService(ref.watch(apiClientProvider))),
);

final serviceAreaRepositoryProvider = Provider<ServiceAreaRepository>(
  (ref) =>
      ServiceAreaRepository(ServiceAreaApiService(ref.watch(apiClientProvider))),
);

final availabilityRepositoryProvider = Provider<AvailabilityRepository>(
  (ref) => AvailabilityRepository(
    AvailabilityApiService(ref.watch(apiClientProvider)),
  ),
);

final bookingRepositoryProvider = Provider<BookingRepository>(
  (ref) => BookingRepository(BookingApiService(ref.watch(apiClientProvider))),
);

final billingRepositoryProvider = Provider<BillingRepository>(
  (ref) => BillingRepository(BillingApiService(ref.watch(apiClientProvider))),
);

final paymentRepositoryProvider = Provider<PaymentRepository>(
  (ref) => PaymentRepository(PaymentApiService(ref.watch(apiClientProvider))),
);

/// Opens the Razorpay checkout. Tests replace this with a fake.
final checkoutLauncherProvider = Provider<CheckoutLauncher>(
  (ref) => const RazorpayCheckoutLauncher(),
);

final adminBookingRepositoryProvider = Provider<AdminBookingRepository>(
  (ref) => AdminBookingRepository(
    AdminBookingApiService(ref.watch(apiClientProvider)),
  ),
);

final adminDriverRepositoryProvider = Provider<AdminDriverRepository>(
  (ref) => AdminDriverRepository(
    AdminDriverApiService(ref.watch(apiClientProvider)),
  ),
);

final driverWorkRepositoryProvider = Provider<DriverWorkRepository>(
  (ref) => DriverWorkRepository(
    DriverWorkApiService(ref.watch(apiClientProvider)),
  ),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(
    NotificationApiService(ref.watch(apiClientProvider)),
  ),
);

final supportRepositoryProvider = Provider<SupportRepository>(
  (ref) => SupportRepository(SupportApiService(ref.watch(apiClientProvider))),
);

final garageSettingsRepositoryProvider = Provider<GarageSettingsRepository>(
  (ref) => GarageSettingsRepository(
    GarageSettingsApiService(ref.watch(apiClientProvider)),
  ),
);

final vehicleRepositoryProvider = Provider<VehicleRepository>(
  (ref) => VehicleRepository(VehicleApiService(ref.watch(apiClientProvider))),
);

final mapsRepositoryProvider = Provider<MapsRepository>(
  (ref) => MapsRepository(MapsApiService(ref.watch(apiClientProvider))),
);

/// The phone's position (asks for permission). Tests replace this with a fake.
final locationServiceProvider = Provider<LocationService>(
  (ref) => const GeolocatorLocationService(),
);

/// Opens calls, WhatsApp, email and maps. Tests replace this with a fake.
final contactLauncherProvider = Provider<ContactLauncher>(
  (ref) => const UrlContactLauncher(),
);
