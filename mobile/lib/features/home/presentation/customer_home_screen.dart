import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../auth/providers/auth_controller.dart';
import '../../catalog/presentation/pincode_check_card.dart';
import '../../notifications/presentation/notification_bell.dart';

/// Customer landing screen: browse services, bookings, help, service-area check.
class CustomerHomeScreen extends ConsumerWidget {
  const CustomerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider.select((s) => s.profile));
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('F&F Garage'),
        actions: [
          const NotificationBell(),
          IconButton(
            tooltip: 'Help & support',
            icon: const Icon(Icons.support_agent),
            onPressed: () => context.push(AppRoutes.support),
          ),
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.push(AppRoutes.profile),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Hello, ${profile?.displayName ?? 'there'}',
              style: textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Doorstep bike and scooter servicing.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.build_outlined),
                title: const Text('Browse services'),
                subtitle: const Text('Packages, prices and what is included'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.browseServices),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('My bookings'),
                subtitle: const Text('Track, change or cancel your bookings'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.bookings),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.support_agent),
                title: const Text('Help & support'),
                subtitle: const Text('Call, WhatsApp or email the garage'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.support),
              ),
            ),
            const PincodeCheckCard(),
          ],
        ),
      ),
    );
  }
}
