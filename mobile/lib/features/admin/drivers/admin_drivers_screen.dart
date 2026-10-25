import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/driver.dart';
import '../providers/admin_providers.dart';

/// Every driver account with its status and how many bookings it still has.
class AdminDriversScreen extends ConsumerWidget {
  const AdminDriversScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drivers = ref.watch(adminDriversProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Drivers')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-driver'),
        onPressed: () => context.push(AppRoutes.adminDriverNew),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add driver'),
      ),
      body: SafeArea(
        child: AsyncView<List<DriverAccount>>(
          value: drivers,
          onRetry: () => ref.invalidate(adminDriversProvider),
          builder: (items) {
            if (items.isEmpty) {
              return const EmptyView(
                message: 'No drivers yet.\nAdd one so bookings can be assigned.',
              );
            }
            return RefreshIndicator(
              onRefresh: () => ref.refresh(adminDriversProvider.future),
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: items.length,
                itemBuilder: (context, index) => _DriverTile(driver: items[index]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DriverTile extends StatelessWidget {
  const _DriverTile({required this.driver});

  final DriverAccount driver;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final open = driver.openBookings;
    final contact = '${driver.loginId}'
        '${driver.phone == null ? '' : ' - ${driver.phone}'}';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('driver-${driver.id}'),
        onTap: () => context.push(AppRoutes.adminDriver(driver.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.primaryContainer,
                child: Icon(Icons.badge_outlined, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver.label, style: textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(contact, style: textTheme.bodySmall),
                    Text(
                      open == 0
                          ? 'No open bookings'
                          : '$open open booking${open == 1 ? '' : 's'}',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (driver.isActive)
                const StatusBadge(label: 'Active', tone: BadgeTone.success)
              else
                const InactiveBadge(),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
