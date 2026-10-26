import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_nav.dart';
import '../../auth/providers/auth_controller.dart';
import '../../driver/presentation/driver_job_list.dart';
import '../../driver/providers/driver_providers.dart';

/// The driver's "My Jobs" tab: today's summary and the bookings still to do.
/// Finished work is on the History tab.
class DriverHomeScreen extends ConsumerWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider.select((s) => s.profile));
    return Scaffold(
      appBar: AppBar(title: const Text('My Jobs')),
      bottomNavigationBar: navFor(ref, NavTab.jobs),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Hello, ${profile?.displayName ?? 'driver'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const _SummaryCard(),
            const Expanded(child: DriverJobList(scope: 'open')),
          ],
        ),
      ),
    );
  }
}

/// "Today's Summary": real counts from the driver's own jobs. Left out while
/// loading or if the numbers cannot be loaded (the lists below show errors).
class _SummaryCard extends ConsumerWidget {
  const _SummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(driverSummaryProvider).valueOrNull;
    if (summary == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    Widget figure(String value, String label, Color color) => Expanded(
          child: Column(
            children: [
              Text(
                value,
                style: textTheme.headlineMedium?.copyWith(color: color),
              ),
              Text(label, style: textTheme.bodySmall),
            ],
          ),
        );
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: Text("Today's Summary", style: textTheme.titleSmall),
            ),
            Row(
              children: [
                figure('${summary.today}', 'Today', scheme.primary),
                figure(
                  '${summary.completedToday}',
                  'Completed',
                  scheme.secondary,
                ),
                figure('${summary.open}', 'Open jobs', scheme.tertiary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
