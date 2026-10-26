import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_nav.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/skeleton.dart';
import '../providers/driver_providers.dart';

/// The driver's "Earnings" tab. The garage does not record driver pay in the
/// app, so this shows real work counts only and says so, rather than inventing
/// amounts.
class DriverEarningsScreen extends ConsumerWidget {
  const DriverEarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(driverSummaryProvider);
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget figure(String label, int value, Color color) => Card(
          child: ListTile(
            title: Text(label),
            trailing: Text(
              '$value',
              style: textTheme.headlineSmall?.copyWith(color: color),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      bottomNavigationBar: navFor(ref, NavTab.earnings),
      body: SafeArea(
        child: AsyncView<DriverSummary>(
          value: summary,
          loading: const ListSkeleton(count: 3),
          onRetry: () => ref.invalidate(driverSummaryProvider),
          builder: (data) => RefreshIndicator(
            onRefresh: () => ref.refresh(driverSummaryProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                figure('Completed today', data.completedToday, scheme.secondary),
                figure('Completed this month', data.completedThisMonth,
                    scheme.primary),
                figure('Jobs finished in total', data.finishedTotal,
                    scheme.primary),
                figure('Open jobs', data.open, scheme.tertiary),
                const SizedBox(height: 8),
                Text(
                  'Payouts are not recorded in this app yet, so no amounts are '
                  'shown. Ask the garage for your earnings statement.',
                  key: const ValueKey('earnings-note'),
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
