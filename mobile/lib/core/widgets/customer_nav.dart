import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../data/models/enums.dart';
import '../../features/auth/providers/auth_controller.dart';

/// Which tab of the customer bottom bar a screen belongs to.
enum CustomerTab { home, bookings, support, profile }

/// The customer's bottom navigation bar: Home, My Bookings, Support, Profile.
/// Returns null for drivers and admins (the shared Profile and Support screens
/// show no customer tabs to them), so it can be passed straight to
/// `Scaffold.bottomNavigationBar`.
Widget? customerNavFor(WidgetRef ref, CustomerTab current) {
  final role = ref.watch(authControllerProvider.select((s) => s.profile?.role));
  if (role != UserRole.customer) {
    return null;
  }
  return CustomerBottomNav(current: current);
}

class CustomerBottomNav extends StatelessWidget {
  const CustomerBottomNav({super.key, required this.current});

  final CustomerTab current;

  static const _routes = {
    CustomerTab.home: AppRoutes.customerHome,
    CustomerTab.bookings: AppRoutes.bookings,
    CustomerTab.support: AppRoutes.support,
    CustomerTab.profile: AppRoutes.profile,
  };

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: CustomerTab.values.indexOf(current),
      onDestinationSelected: (index) {
        final tab = CustomerTab.values[index];
        if (tab != current) {
          context.go(_routes[tab]!);
        }
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long),
          label: 'My Bookings',
        ),
        NavigationDestination(
          icon: Icon(Icons.support_agent_outlined),
          selectedIcon: Icon(Icons.support_agent),
          label: 'Support',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }
}
