import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/dashboard.dart';
import '../../../data/models/enums.dart';
import '../../auth/providers/auth_controller.dart';
import '../../booking/presentation/booking_widgets.dart';
import '../providers/admin_providers.dart';
import 'admin_scaffold.dart';

/// The admin dashboard: real figures from the server (bookings per status,
/// revenue, active drivers), the newest bookings and quick actions. Every
/// management screen is in the sidebar, not repeated here.
class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(adminDashboardProvider);
    ref.invalidate(adminRecentBookingsProvider);
    await Future.wait([
      ref.read(adminDashboardProvider.future).then((_) {}, onError: (_) {}),
      ref.read(adminRecentBookingsProvider.future).then((_) {}, onError: (_) {}),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider.select((s) => s.profile));
    final dashboard = ref.watch(adminDashboardProvider);
    final recent = ref.watch(adminRecentBookingsProvider);

    final breakdown = _Panel(
      title: 'Booking status',
      child: AsyncView<AdminDashboard>(
        value: dashboard,
        loading: const _PanelLoading(),
        onRetry: () => ref.invalidate(adminDashboardProvider),
        builder: (data) => _StatusBreakdown(data: data),
      ),
    );
    final recentPanel = _Panel(
      title: 'Recent bookings',
      action: TextButton(
        key: const ValueKey('view-all-bookings'),
        onPressed: () => context.go(AppRoutes.adminBookings),
        child: const Text('View all'),
      ),
      child: AsyncView<List<Booking>>(
        value: recent,
        loading: const _PanelLoading(),
        onRetry: () => ref.invalidate(adminRecentBookingsProvider),
        builder: (items) => _RecentBookings(items: items),
      ),
    );
    const quick = _Panel(title: 'Quick actions', child: _QuickActions());

    return AdminScaffold(
      section: AdminSection.dashboard,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Welcome back, ${profile?.displayName ?? 'admin'}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _StatCards(dashboard: dashboard, width: constraints.maxWidth - 32),
                  const SizedBox(height: 16),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: recentPanel),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: Column(children: [breakdown, const SizedBox(height: 16), quick]),
                        ),
                      ],
                    )
                  else ...[
                    quick,
                    const SizedBox(height: 16),
                    breakdown,
                    const SizedBox(height: 16),
                    recentPanel,
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A titled white card.
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium),
                ),
                if (action != null) action!,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _PanelLoading extends StatelessWidget {
  const _PanelLoading();

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 96,
        child: Center(child: CircularProgressIndicator()),
      );
}

// ---- figures --------------------------------------------------------------------------

class _StatCards extends ConsumerWidget {
  const _StatCards({required this.dashboard, required this.width});

  final AsyncValue<AdminDashboard> dashboard;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columns = width >= 900 ? 5 : (width >= 560 ? 3 : 2);
    const gap = 12.0;
    final cardWidth = (width - gap * (columns - 1)) / columns;
    final scheme = Theme.of(context).colorScheme;

    return dashboard.when(
      skipLoadingOnRefresh: true,
      loading: () => Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < columns; i++)
            SizedBox(
              key: ValueKey('stat-loading-$i'),
              width: cardWidth,
              height: 96,
              child: const SkeletonBox(height: 96, radius: 12),
            ),
        ],
      ),
      error: (error, _) => Card(
        margin: EdgeInsets.zero,
        child: ErrorView(
          message: errorMessage(error),
          onRetry: () => ref.invalidate(adminDashboardProvider),
        ),
      ),
      data: (data) {
        Widget card(String key, String label, String value, IconData icon,
                Color color, {String? note, VoidCallback? onTap}) =>
            SizedBox(
              width: cardWidth,
              child: _StatCard(
                key: ValueKey(key),
                label: label,
                value: value,
                icon: icon,
                color: color,
                note: note,
                onTap: onTap,
              ),
            );
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            card('stat-total', 'Total bookings', '${data.total}',
                Icons.receipt_long_outlined, scheme.primary,
                onTap: () => context.go(AppRoutes.adminBookings)),
            card('stat-pending', 'Pending', '${data.pending}',
                Icons.hourglass_top_outlined, scheme.tertiary,
                note: 'Awaiting payment or a driver',
                onTap: () => context.go(AppRoutes.adminBookings)),
            card('stat-completed', 'Completed', '${data.completed}',
                Icons.check_circle_outline, scheme.secondary,
                onTap: () => context.go(AppRoutes.adminBookings)),
            card('stat-drivers', 'Active drivers', '${data.activeDrivers}',
                Icons.badge_outlined, scheme.primary,
                onTap: () => context.go(AppRoutes.adminDrivers)),
            card('stat-revenue', 'Revenue', formatMoney(data.revenueNet),
                Icons.payments_outlined, scheme.secondary,
                note: data.revenueRefunded > 0
                    ? '${formatMoney(data.revenueCollected)} collected, '
                        '${formatMoney(data.revenueRefunded)} refunded'
                    : 'Collected through the gateway'),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.note,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label,
                        style: textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (note != null) ...[
                const SizedBox(height: 2),
                Text(note!,
                    style: textTheme.labelSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---- status breakdown -----------------------------------------------------------------

const _statusOrder = [
  BookingStatus.pendingPayment,
  BookingStatus.confirmed,
  BookingStatus.assigned,
  BookingStatus.onTheWay,
  BookingStatus.inProgress,
  BookingStatus.completed,
  BookingStatus.cancelled,
];

Color _toneColor(BuildContext context, BadgeTone tone) {
  final scheme = Theme.of(context).colorScheme;
  switch (tone) {
    case BadgeTone.success:
      return scheme.secondary;
    case BadgeTone.warning:
      return scheme.tertiary;
    case BadgeTone.danger:
      return scheme.error;
    case BadgeTone.info:
    case BadgeTone.neutral:
      return scheme.primary;
  }
}

class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({required this.data});

  final AdminDashboard data;

  @override
  Widget build(BuildContext context) {
    if (data.total == 0) {
      return const _Empty(
        key: ValueKey('breakdown-empty'),
        icon: Icons.bar_chart,
        message: 'No bookings yet. The breakdown appears with the first one.',
      );
    }
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        for (final status in _statusOrder)
          Padding(
            key: ValueKey('status-row-${status.apiValue}'),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(bookingStatusLabel(status),
                          style: textTheme.bodyMedium),
                    ),
                    Text('${data.count(status)}',
                        style: textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: data.count(status) / data.total,
                    color: _toneColor(context, bookingStatusTone(status)),
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---- recent bookings ------------------------------------------------------------------

class _RecentBookings extends StatelessWidget {
  const _RecentBookings({required this.items});

  final List<Booking> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _Empty(
        key: ValueKey('recent-empty'),
        icon: Icons.receipt_long_outlined,
        message: 'No bookings yet.',
      );
    }
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          InkWell(
            key: ValueKey('recent-${items[i].id}'),
            onTap: () => context.push(AppRoutes.adminBooking(items[i].id)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${items[i].code} - ${items[i].serviceName}',
                          style: textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${items[i].customerName} - '
                          '${formatDate(items[i].date)}',
                          style: textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      BookingStatusChip(status: items[i].status),
                      const SizedBox(height: 4),
                      Text(formatMoney(items[i].totalAmount),
                          style: textTheme.labelMedium),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(icon, size: 32, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

// ---- quick actions --------------------------------------------------------------------

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    Widget action(String key, IconData icon, String label, VoidCallback onTap) =>
        FilledButton.tonalIcon(
          key: ValueKey(key),
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        action('quick-service', Icons.build_outlined, 'Add service',
            () => context.push(AppRoutes.adminServiceNew)),
        action('quick-driver', Icons.person_add_alt, 'Add driver',
            () => context.push(AppRoutes.adminDriverNew)),
        action('quick-coupon', Icons.local_offer_outlined, 'Coupons',
            () => context.go(AppRoutes.adminCoupons)),
        action('quick-area', Icons.location_on_outlined, 'Service areas',
            () => context.go(AppRoutes.adminAreas)),
        action('quick-availability', Icons.event_available_outlined,
            'Availability', () => context.go(AppRoutes.adminAvailability)),
      ],
    );
  }
}
