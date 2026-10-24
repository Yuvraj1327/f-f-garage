import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../auth/providers/auth_controller.dart';

/// Entry point of the admin area.
class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider.select((s) => s.profile));
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('F&F Garage - Admin'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.push(AppRoutes.profile),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Hello, ${profile?.displayName ?? 'admin'}',
              style: textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            _Tile(
              icon: Icons.assignment_outlined,
              title: 'Bookings',
              subtitle: 'See bookings and assign drivers',
              onTap: () => context.push(AppRoutes.adminBookings),
            ),
            _Tile(
              icon: Icons.badge_outlined,
              title: 'Drivers',
              subtitle: 'Driver accounts, passwords and workload',
              onTap: () => context.push(AppRoutes.adminDrivers),
            ),
            _Tile(
              icon: Icons.build_outlined,
              title: 'Services',
              subtitle: 'Services, packages, prices and extra charges',
              onTap: () => context.push(AppRoutes.adminServices),
            ),
            _Tile(
              icon: Icons.location_on_outlined,
              title: 'Service areas',
              subtitle: 'PIN codes where doorstep service is available',
              onTap: () => context.push(AppRoutes.adminAreas),
            ),
            _Tile(
              icon: Icons.event_available_outlined,
              title: 'Availability',
              subtitle: 'Time slots, closed days and capacity',
              onTap: () => context.push(AppRoutes.adminAvailability),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
