import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_nav.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/content_width.dart';
import '../../../core/widgets/skeleton.dart';
import '../../booking/presentation/booking_widgets.dart';
import '../../../data/models/driver_job.dart';
import '../providers/driver_providers.dart';

/// The driver's "Earnings" tab. The garage does not record driver pay in the
/// app, so this shows the real work done (completed jobs per period and the
/// latest ones) and says so, rather than inventing amounts.
class DriverEarningsScreen extends ConsumerWidget {
  const DriverEarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(driverSummaryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      bottomNavigationBar: navFor(ref, NavTab.earnings),
      body: SafeArea(
        child: ContentWidth(
          child: AsyncView<DriverSummary>(
            value: summary,
            loading: const ListSkeleton(count: 3),
            onRetry: () => ref.invalidate(driverSummaryProvider),
            builder: (data) => RefreshIndicator(
              onRefresh: () => ref.refresh(driverSummaryProvider.future),
              child: _Body(data: data),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.data});

  final DriverSummary data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget figure(String key, String label, int value, IconData icon, Color color) =>
        Expanded(
          child: Card(
            key: ValueKey(key),
            margin: const EdgeInsets.all(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(height: 8),
                  Text(
                    '$value',
                    style: textTheme.headlineSmall
                        ?.copyWith(color: color, fontWeight: FontWeight.w800),
                  ),
                  Text(label, style: textTheme.bodySmall),
                ],
              ),
            ),
          ),
        );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: scheme.primary,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Jobs completed this month',
                    style: textTheme.bodyMedium
                        ?.copyWith(color: scheme.onPrimary)),
                const SizedBox(height: 4),
                Text(
                  '${data.completedThisMonth}',
                  key: const ValueKey('earnings-month'),
                  style: textTheme.displaySmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        Row(children: [
          figure('earnings-today', 'Completed today', data.completedToday,
              Icons.today_outlined, scheme.primary),
          figure('earnings-week', 'Last 7 days', data.completedThisWeek,
              Icons.date_range_outlined, scheme.secondary),
        ]),
        Row(children: [
          figure('earnings-open', 'Open jobs', data.open,
              Icons.pending_actions_outlined, scheme.tertiary),
          figure('earnings-finished', 'Finished in total', data.finishedTotal,
              Icons.task_alt, scheme.primary),
        ]),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('Recently completed', style: textTheme.titleMedium),
        ),
        if (data.recentCompleted.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Completed jobs will be listed here.',
              key: const ValueKey('earnings-empty'),
              style: textTheme.bodyMedium,
            ),
          )
        else
          for (final job in data.recentCompleted) _CompletedRow(job: job),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Payouts are not recorded in this app yet, so no amounts are '
            'shown. Ask the garage for your earnings statement.',
            key: const ValueKey('earnings-note'),
            style: textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _CompletedRow extends StatelessWidget {
  const _CompletedRow({required this.job});

  final DriverJob job;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        title: Text('${job.code} - ${job.serviceName}'),
        subtitle: Text('${job.customerName} - ${formatDate(job.date)}'),
        trailing: BookingStatusChip(status: job.status),
      ),
    );
  }
}
