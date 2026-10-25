import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stat_tile.dart';
import '../../auth/providers/auth_controller.dart';
import '../providers/admin_providers.dart';

/// The admin dashboard: live booking and driver figures from the API and
/// shortcuts to every management screen.
class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider.select((s) => s.profile));
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    // Figures are a bonus here: left out while loading or if they cannot be
    // loaded (each management screen reports its own errors).
    final stats = ref.watch(adminStatsProvider).valueOrNull;
    void openBookings() => context.push(AppRoutes.adminBookings);

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
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(adminStatsProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Hello, ${profile?.displayName ?? 'admin'}',
                style: textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              if (stats != null) ...[
                StatGrid(
                  tiles: [
                    StatTile(
                      label: 'Total Bookings',
                      value: '${stats.total}',
                      onTap: openBookings,
                    ),
                    StatTile(
                      label: 'Completed',
                      value: '${stats.completed}',
                      color: scheme.secondary,
                      onTap: openBookings,
                    ),
                    StatTile(
                      label: 'Pending',
                      value: '${stats.pending}',
                      color: scheme.tertiary,
                      onTap: openBookings,
                    ),
                    StatTile(
                      label: 'Cancelled',
                      value: '${stats.cancelled}',
                      color: scheme.error,
                      onTap: openBookings,
                    ),
                    StatTile(
                      label: 'Active Drivers',
                      value: '${stats.activeDrivers}',
                      onTap: () => context.push(AppRoutes.adminDrivers),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              const SectionHeader(title: 'Manage'),
              _Tile(
                icon: Icons.assignment_outlined,
                title: 'Bookings',
                subtitle: 'See bookings and assign drivers',
                onTap: openBookings,
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
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.primary,
          child: Icon(icon),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
