import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../data/models/enums.dart';
import '../../features/auth/providers/auth_controller.dart';

/// Every tab of every role's bottom bar. A role only ever sees its own tabs
/// (see [navItemsFor]).
enum NavTab {
  // Customer
  home,
  bookings,
  support,
  // Driver
  jobs,
  history,
  earnings,
  // Admin
  dashboard,
  adminBookings,
  drivers,
  services,
  // Everyone
  settings,
}

class NavItem {
  const NavItem(this.tab, this.label, this.icon, this.selectedIcon, this.route);

  final NavTab tab;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String route;
}

const _settings = NavItem(
  NavTab.settings,
  'Settings',
  Icons.settings_outlined,
  Icons.settings,
  AppRoutes.settings,
);

/// The bottom-bar items a role is allowed to see, in order.
List<NavItem> navItemsFor(UserRole role) {
  switch (role) {
    case UserRole.customer:
      return const [
        NavItem(NavTab.home, 'Home', Icons.home_outlined, Icons.home,
            AppRoutes.customerHome),
        NavItem(NavTab.bookings, 'My Bookings', Icons.receipt_long_outlined,
            Icons.receipt_long, AppRoutes.bookings),
        NavItem(NavTab.support, 'Support', Icons.support_agent_outlined,
            Icons.support_agent, AppRoutes.support),
        _settings,
      ];
    case UserRole.driver:
      return const [
        NavItem(NavTab.jobs, 'My Jobs', Icons.two_wheeler_outlined,
            Icons.two_wheeler, AppRoutes.driverHome),
        NavItem(NavTab.history, 'History', Icons.history, Icons.history,
            AppRoutes.driverHistory),
        NavItem(NavTab.earnings, 'Earnings', Icons.payments_outlined,
            Icons.payments, AppRoutes.driverEarnings),
        _settings,
      ];
    case UserRole.admin:
      return const [
        NavItem(NavTab.dashboard, 'Dashboard', Icons.dashboard_outlined,
            Icons.dashboard, AppRoutes.adminHome),
        NavItem(NavTab.adminBookings, 'Bookings', Icons.receipt_long_outlined,
            Icons.receipt_long, AppRoutes.adminBookings),
        NavItem(NavTab.drivers, 'Drivers', Icons.badge_outlined, Icons.badge,
            AppRoutes.adminDrivers),
        NavItem(NavTab.services, 'Services', Icons.build_outlined,
            Icons.build, AppRoutes.adminServices),
        _settings,
      ];
  }
}

/// The signed-in user's bottom navigation bar, to pass straight to
/// `Scaffold.bottomNavigationBar`. Null when nobody is signed in or [current]
/// is not one of the role's tabs (so a driver never gets a customer tab).
Widget? navFor(WidgetRef ref, NavTab current) {
  final role = ref.watch(authControllerProvider.select((s) => s.profile?.role));
  if (role == null) {
    return null;
  }
  final items = navItemsFor(role);
  if (!items.any((i) => i.tab == current)) {
    return null;
  }
  return AppBottomNav(items: items, current: current);
}

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.items, required this.current});

  final List<NavItem> items;
  final NavTab current;

  @override
  Widget build(BuildContext context) {
    final selected = items.indexWhere((i) => i.tab == current);
    return NavigationBar(
      selectedIndex: selected < 0 ? 0 : selected,
      onDestinationSelected: (index) {
        final item = items[index];
        if (item.tab != current) {
          context.go(item.route);
        }
      },
      destinations: [
        for (final item in items)
          NavigationDestination(
            key: ValueKey('nav-${item.tab.name}'),
            icon: Icon(item.icon),
            selectedIcon: Icon(item.selectedIcon),
            label: item.label,
          ),
      ],
    );
  }
}
