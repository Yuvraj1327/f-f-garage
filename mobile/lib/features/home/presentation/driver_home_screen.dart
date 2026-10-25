import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../data/models/driver_job.dart';
import '../../../data/providers/data_providers.dart';
import '../../auth/providers/auth_controller.dart';
import '../../booking/presentation/booking_widgets.dart';
import '../../driver/presentation/driver_widgets.dart';
import '../../driver/providers/driver_providers.dart';

const int _pageSize = 25;

/// The driver's dashboard: the bookings assigned to them (open work first, then
/// what they have finished).
class DriverHomeScreen extends ConsumerWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider.select((s) => s.profile));
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('F&F Garage - Driver'),
          actions: [
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
          bottom: const TabBar(
            tabs: [
              Tab(key: ValueKey('tab-open'), text: 'My jobs'),
              Tab(key: ValueKey('tab-history'), text: 'History'),
            ],
          ),
        ),
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
              const Expanded(
                child: TabBarView(
                  children: [
                    _JobList(scope: 'open'),
                    _JobList(scope: 'history'),
                  ],
                ),
              ),
            ],
          ),
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

/// One tab: loading, error with retry, empty message, the list with paging,
/// and pull-to-refresh.
class _JobList extends ConsumerStatefulWidget {
  const _JobList({required this.scope});

  final String scope;

  @override
  ConsumerState<_JobList> createState() => _JobListState();
}

class _JobListState extends ConsumerState<_JobList>
    with AutomaticKeepAliveClientMixin {
  List<DriverJob> _items = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _generation = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(driverWorkRepositoryProvider)
          .list(scope: widget.scope, limit: _pageSize);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = errorMessage(error);
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await ref.read(driverWorkRepositoryProvider).list(
            scope: widget.scope,
            limit: _pageSize,
            offset: _items.length,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = [..._items, ...page.items];
        _total = page.total;
      });
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // A step was recorded (or the admin changed something we reloaded): refresh.
    ref.listen<int>(driverJobsRefreshProvider, (_, __) => _reload());
    if (_loading && _items.isEmpty) {
      return const ListSkeleton(count: 3);
    }
    if (_error != null && _items.isEmpty) {
      return ErrorView(message: _error!, onRetry: _reload);
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            EmptyView(
              icon: widget.scope == 'open'
                  ? Icons.two_wheeler
                  : Icons.history,
              message: widget.scope == 'open'
                  ? 'No jobs assigned to you right now.\nPull down to check again.'
                  : 'No finished jobs yet.',
            ),
          ],
        ),
      );
    }
    final hasMore = _items.length < _total;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 24),
        itemCount: _items.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton(
                        onPressed: _loadMore,
                        child: const Text('Load more'),
                      ),
              ),
            );
          }
          return _JobTile(job: _items[index]);
        },
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job});

  final DriverJob job;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('job-${job.id}'),
        onTap: () => context.push(AppRoutes.driverBooking(job.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${job.code} - ${job.serviceName}',
                      style: textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  BookingStatusChip(status: job.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(job.customerName, style: textTheme.bodyMedium),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.event_outlined,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('${formatDate(job.date)}, ${job.timeLabel}'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.place_outlined,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      jobAddressLine(job),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
