/// Paths of the FastAPI backend, relative to `AppConfig.apiBaseUrl`
/// (which already ends in `/api/v1`). One constant per endpoint; feature phases
/// add theirs here.
abstract final class ApiEndpoints {
  static const String health = '/health';
  static const String myProfile = '/profiles/me';

  // Customer-facing catalogue
  static const String catalogServices = '/catalog/services';
  static String catalogService(String id) => '/catalog/services/$id';
  static const String pincodeCheck = '/service-areas/check';
  static const String availability = '/availability';

  // Admin: services, packages, extra charges
  static const String adminServices = '/admin/services';
  static String adminService(String id) => '/admin/services/$id';
  static String adminServicePackages(String serviceId) =>
      '/admin/services/$serviceId/packages';
  static String adminPackage(String id) => '/admin/packages/$id';
  static String adminServiceCharges(String serviceId) =>
      '/admin/services/$serviceId/extra-charges';
  static String adminCharge(String id) => '/admin/extra-charges/$id';

  // Admin: service areas
  static const String adminAreas = '/admin/service-areas';
  static String adminArea(String id) => '/admin/service-areas/$id';

  // Admin: availability
  static const String adminSlots = '/admin/availability/slots';
  static String adminSlot(String id) => '/admin/availability/slots/$id';
  static const String adminExceptions = '/admin/availability/exceptions';
  static String adminException(String id) =>
      '/admin/availability/exceptions/$id';

  // Address lookup (customers). The Google key stays on the server.
  static const String mapsGeocode = '/maps/geocode';
  static const String mapsReverse = '/maps/reverse';

  // Customer bookings
  static const String bookings = '/bookings';
  static const String bookingQuote = '/bookings/quote';
  static String booking(String id) => '/bookings/$id';
  static String cancelBooking(String id) => '/bookings/$id/cancel';

  // Payments
  static String bookingPayments(String bookingId) =>
      '/bookings/$bookingId/payments';
  static String payment(String id) => '/payments/$id';
  static String verifyPayment(String id) => '/payments/$id/verify';
  static String cancelPayment(String id) => '/payments/$id/cancel';

  // Admin: bookings, driver assignment, drivers
  static const String adminBookings = '/admin/bookings';
  static String adminBooking(String id) => '/admin/bookings/$id';
  static String adminBookingDriver(String id) => '/admin/bookings/$id/driver';
  static String adminBookingAssignments(String id) =>
      '/admin/bookings/$id/assignments';
  static const String adminDrivers = '/admin/drivers';
  static String adminDriver(String id) => '/admin/drivers/$id';
  static String adminDriverPassword(String id) => '/admin/drivers/$id/password';
  static String adminDriverBookings(String id) => '/admin/drivers/$id/bookings';

  // Driver: own bookings
  static const String driverBookings = '/driver/bookings';
  static String driverBooking(String id) => '/driver/bookings/$id';
  static String driverBookingStatus(String id) =>
      '/driver/bookings/$id/status';

  // Customer: in-app notifications
  static const String notifications = '/notifications';
  static const String notificationsUnreadCount = '/notifications/unread-count';
  static const String notificationsRead = '/notifications/read';

  // Support: garage contact details (any signed-in role)
  static const String supportContact = '/support/contact';

  // Customer: saved two-wheelers
  static const String vehicles = '/vehicles';
  static String vehicle(String id) => '/vehicles/$id';

  // Admin: the garage's own details (name, phone, email, ...)
  static const String adminGarageSettings = '/admin/garage-settings';
}
