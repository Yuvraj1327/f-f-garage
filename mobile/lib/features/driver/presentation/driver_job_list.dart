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
import '../../booking/presentation/booking_widgets.dart';
import '../providers/driver_providers.dart';
import 'driver_widgets.dart';

const int _pageSize = 25;

/// The driver's jobs for one scope ('open' or 'history'): loading, error with
/// retry, empty message, the list with paging, and pull-to-refresh.
class DriverJobList extends ConsumerStatefulWidget {
  const DriverJobList({required this.scope});

  /// `open` (still to do) or `history` (finished).
  final String scope;

  @override
  ConsumerState<DriverJobList> createState() => _DriverJobListState();
}

class _DriverJobListState extends ConsumerState<DriverJobList>
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
      // Pull-to-refresh works here too, so a failed load never leaves the
      // screen stuck.
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 48),
            ErrorView(message: _error!, onRetry: _reload),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 48),
            _EmptyJobs(open: widget.scope == 'open'),
          ],
        ),
      );
    }
    final hasMore = _items.length < _total;
    // A refresh that failed keeps the old list but says so.
    final banner = _error == null ? 0 : 1;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: banner + _items.length + (hasMore ? 1 : 0),
        itemBuilder: (context, rawIndex) {
          if (banner == 1 && rawIndex == 0) {
            return Padding(
              key: const ValueKey('refresh-error'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.error_outline,
                      color: Theme.of(context).colorScheme.onErrorContainer),
                  title: Text(
                    '${_error!} Showing the last list.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer),
                  ),
                  trailing: TextButton(
                    onPressed: _reload,
                    child: const Text('Retry'),
                  ),
                ),
              ),
            );
          }
          final index = rawIndex - banner;
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
          return _JobTile(job: _items[index], finished: widget.scope == 'history');
        },
      ),
    );
  }
}

class _EmptyJobs extends StatelessWidget {
  const _EmptyJobs({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              open ? Icons.two_wheeler : Icons.history,
              size: 40,
              color: scheme.secondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            open
                ? 'No jobs assigned to you right now.\nPull down to check again.'
                : 'No finished jobs yet.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

/// One job: booking code and status, the service, the customer, the vehicle,
/// when and where. Finished jobs are drawn a little quieter.
class _JobTile extends StatelessWidget {
  const _JobTile({required this.job, required this.finished});

  final DriverJob job;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget info(IconData icon, String text, {int lines = 1}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: textTheme.bodyMedium,
                  maxLines: lines,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('job-${job.id}'),
        onTap: () => context.push(AppRoutes.driverBooking(job.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Opacity(
            opacity: finished ? 0.85 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        job.code,
                        style: textTheme.labelLarge
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    BookingStatusChip(status: job.status),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  job.serviceName,
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (job.packageName.isNotEmpty)
                  Text(job.packageName, style: textTheme.bodySmall),
                const SizedBox(height: 6),
                info(
                  Icons.person_outline,
                  job.customerPhone.isEmpty
                      ? job.customerName
                      : '${job.customerName} - ${job.customerPhone}',
                ),
                info(Icons.two_wheeler, vehicleLabel(job.vehicleType)),
                info(Icons.schedule,
                    '${formatDate(job.date)}, ${job.timeLabel}'),
                info(Icons.place_outlined, jobAddressLine(job), lines: 2),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        !finished && job.nextStatus != null
                            ? 'Next: ${driverStepLabel(job.nextStatus!)}'
                            : 'View details',
                        style: textTheme.labelLarge
                            ?.copyWith(color: scheme.primary),
                      ),
                      Icon(Icons.chevron_right, size: 18, color: scheme.primary),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
