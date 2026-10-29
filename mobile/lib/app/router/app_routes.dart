/// Route paths. Add one constant per screen as features are built.
abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String register = '/register';
  /// The one sign-in for drivers and admins.
  static const String staffLogin = '/staff-login';

  /// Old addresses of the separate screens; they open [staffLogin].
  static const String driverLogin = '/driver-login';
  static const String adminLogin = '/admin-login';
  static const String profile = '/profile';

  // Settings: one screen for every role, plus its pages.
  static const String settings = '/settings';
  static const String settingsPassword = '/settings/password';
  static const String settingsAbout = '/settings/about';
  static const String settingsPrivacy = '/settings/privacy';

  /// Garage name, phone, email, ... (administrators only).
  static const String settingsGarage = '/settings/garage';
  static const String support = '/support';

  /// Support screen opened from a booking, so the message can quote its code.
  static String supportForBooking(String code) =>
      Uri(path: support, queryParameters: {'booking': code}).toString();

  // Customer area: everything under /home
  static const String customerHome = '/home';
  static const String browseServices = '/home/services';
  static String serviceDetail(String id) => '/home/services/$id';

  // Booking flow (a customer chooses a package first, then these three steps)
  static const String cart = '/home/cart';
  static const String checkout = '/home/checkout';
  static const String bookAddress = '/home/book-address';
  static const String bookSchedule = '/home/book-schedule';
  static const String bookSummary = '/home/book-summary';

  // Booking history and details
  static const String bookings = '/home/bookings';
  static String booking(String id) => '/home/bookings/$id';
  static String bookingEdit(String id) => '/home/bookings/$id/edit';
  static String bookingPay(String id) => '/home/bookings/$id/pay';

  /// Full-screen map where the customer pins the service location. Returns a
  /// `PickedLocation` (and takes the starting `MapPoint` as `extra`).
  static const String pickLocation = '/home/pick-location';

  static const String notifications = '/home/notifications';

  // Saved vehicles (customers)
  static const String vehicles = '/home/vehicles';
  static const String vehicleNew = '/home/vehicles/new';
  static String vehicleEdit(String id) => '/home/vehicles/$id/edit';

  // Driver area: everything under /driver
  static const String driverHome = '/driver';
  static const String driverHistory = '/driver/history';
  static const String driverEarnings = '/driver/earnings';
  static String driverBooking(String id) => '/driver/bookings/$id';

  // Admin area: everything under /admin
  static const String adminHome = '/admin';
  static const String adminBookings = '/admin/bookings';
  static String adminBooking(String id) => '/admin/bookings/$id';
  static const String adminDrivers = '/admin/drivers';
  static const String adminDriverNew = '/admin/drivers/new';
  static String adminDriver(String id) => '/admin/drivers/$id';
  static const String adminServices = '/admin/services';
  static const String adminServiceNew = '/admin/services/new';
  static String adminService(String id) => '/admin/services/$id';
  static String adminServiceEdit(String id) => '/admin/services/$id/edit';
  static String adminServicePreview(String id) => '/admin/services/$id/preview';
  static const String adminCategories = '/admin/services/categories';
  static String adminPackage(String serviceId, String packageId) =>
      '/admin/services/$serviceId/packages/$packageId';
  static String adminCharge(String serviceId, String chargeId) =>
      '/admin/services/$serviceId/charges/$chargeId';
  static const String adminCoupons = '/admin/coupons';
  static const String adminAreas = '/admin/areas';
  static const String adminAvailability = '/admin/availability';

  /// Placeholder id in the package/charge routes meaning "create a new one".
  static const String newItem = 'new';
}
