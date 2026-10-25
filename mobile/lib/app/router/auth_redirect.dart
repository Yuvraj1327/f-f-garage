import '../../data/models/enums.dart';
import '../../features/auth/providers/auth_controller.dart';
import 'app_routes.dart';

const Set<String> _publicRoutes = {
  AppRoutes.onboarding,
  AppRoutes.login,
  AppRoutes.register,
  AppRoutes.driverLogin,
  AppRoutes.adminLogin,
};

/// Decides where the user may be. Returns the location to redirect to, or null
/// to stay. Pure function so every rule is unit-tested without a widget tree.
///
/// - While the session is being checked (or the backend is unreachable) the
///   only reachable screen is the splash.
/// - Signed-out users can reach only the onboarding, login and register
///   screens; until the onboarding has been seen, login redirects to it.
/// - Signed-in users are kept off the login screens, and each role is kept
///   inside its own area (a path prefix). The profile and support screens are shared.
///
/// This is convenience, not security: every backend endpoint enforces the role
/// itself (see `app/api/auth.py`).
String? authRedirect({
  required AuthStatus status,
  required UserRole? role,
  required String location,
  bool onboardingSeen = true,
}) {
  switch (status) {
    case AuthStatus.unknown:
    case AuthStatus.connectionError:
      return location == AppRoutes.splash ? null : AppRoutes.splash;
    case AuthStatus.unauthenticated:
      // First launch: the welcome screens come before the sign-in screen.
      if (!onboardingSeen && location == AppRoutes.login) {
        return AppRoutes.onboarding;
      }
      return _publicRoutes.contains(location) ? null : AppRoutes.login;
    case AuthStatus.authenticated:
      final home = homeFor(role);
      if (home == null) {
        return location == AppRoutes.splash ? null : AppRoutes.splash;
      }
      if (location == AppRoutes.profile || location == AppRoutes.support) {
        return null;
      }
      return _isInside(location, home) ? null : home;
  }
}

/// The landing screen for a role.
String? homeFor(UserRole? role) {
  switch (role) {
    case UserRole.customer:
      return AppRoutes.customerHome;
    case UserRole.driver:
      return AppRoutes.driverHome;
    case UserRole.admin:
      return AppRoutes.adminHome;
    case null:
      return null;
  }
}

/// True when [location] is [area] itself or a page below it. Matching whole
/// path segments keeps `/driver-login` from counting as inside `/driver`.
bool _isInside(String location, String area) =>
    location == area || location.startsWith('$area/');
