import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_widgets.dart';
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
    final open = driver.openBookings;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        key: ValueKey('driver-${driver.id}'),
        leading: const Icon(Icons.badge_outlined),
        title: Row(
          children: [
            Flexible(child: Text(driver.label)),
            if (!driver.isActive) ...[
              const SizedBox(width: 8),
              const InactiveBadge(),
            ],
          ],
        ),
        subtitle: Text(
          '${driver.loginId}'
          '${driver.phone == null ? '' : ' - ${driver.phone}'}\n'
          '${open == 0 ? 'No open bookings' : '$open open booking${open == 1 ? '' : 's'}'}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(AppRoutes.adminDriver(driver.id)),
      ),
    );
  }
}
