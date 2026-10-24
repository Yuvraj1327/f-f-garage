import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/enums.dart';
import '../../../data/providers/data_providers.dart';
import '../../booking/presentation/booking_widgets.dart';
import '../providers/admin_providers.dart';

const int _pageSize = 25;

/// What the admin is looking for in the booking list.
enum AdminBookingFilter {
  needsDriver('Needs driver', [BookingStatus.confirmed]),
  assigned('Assigned', [
    BookingStatus.assigned,
    BookingStatus.onTheWay,
    BookingStatus.inProgress,
  ]),
  awaitingPayment('Awaiting payment', [BookingStatus.pendingPayment]),
  completed('Completed', [BookingStatus.completed]),
  cancelled('Cancelled', [BookingStatus.cancelled]),
  all('All', null);

  const AdminBookingFilter(this.label, this.statuses);

  final String label;
  final List<BookingStatus>? statuses;
}

/// All bookings, filtered by what needs doing, with search and paging.
class AdminBookingsScreen extends ConsumerStatefulWidget {
  const AdminBookingsScreen({super.key});

  @override
  ConsumerState<AdminBookingsScreen> createState() =>
      _AdminBookingsScreenState();
}

class _AdminBookingsScreenState extends ConsumerState<AdminBookingsScreen> {
  final _search = TextEditingController();
  AdminBookingFilter _filter = AdminBookingFilter.needsDriver;
  List<Booking> _items = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  /// Ignores answers to requests that were superseded.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(adminBookingRepositoryProvider).list(
            statuses: _filter.statuses,
            query: _search.text,
            limit: _pageSize,
          );
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
      final page = await ref.read(adminBookingRepositoryProvider).list(
            statuses: _filter.statuses,
            query: _search.text,
            limit: _pageSize,
            offset: _items.length,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = [..._items, ...page.items];
        _total = page.total;
      });
    } catch (error) {
      if (!mounted) return;
      showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A booking or assignment changed on another screen: reload.
    ref.listen<int>(adminBookingsRefreshProvider, (_, __) => _reload());
    return Scaffold(
      appBar: AppBar(title: const Text('Bookings')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                key: const ValueKey('booking-search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Booking number, customer name or phone',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      if (_search.text.isEmpty) return;
                      _search.clear();
                      _reload();
                    },
                  ),
                ),
                onSubmitted: (_) => _reload(),
              ),
            ),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final filter in AdminBookingFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: ValueKey('filter-${filter.name}'),
                        label: Text(filter.label),
                        selected: _filter == filter,
                        onSelected: (_) {
                          if (_filter == filter) return;
                          setState(() => _filter = filter);
                          _reload();
                        },
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return ErrorView(message: _error!, onRetry: _reload);
    }
    if (_items.isEmpty) {
      return EmptyView(
        message: _search.text.trim().isNotEmpty
            ? 'No bookings match your search.'
            : _filter == AdminBookingFilter.needsDriver
                ? 'No paid bookings are waiting for a driver.'
                : _filter == AdminBookingFilter.all
                    ? 'There are no bookings yet.'
                    : 'No ${_filter.label.toLowerCase()} bookings.',
      );
    }
    final hasMore = _items.length < _total;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _items.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton(
                        key: const ValueKey('load-more'),
                        onPressed: _loadMore,
                        child: const Text('Load more'),
                      ),
              ),
            );
          }
          return _BookingTile(booking: _items[index]);
        },
      ),
    );
  }
}

class _BookingTile extends StatelessWidget {
  const _BookingTile({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final assignment = booking.assignment;
    final driverText = assignment == null
        ? (booking.isCancelled ? 'No driver' : 'No driver assigned')
        : 'Driver: ${assignment.label}'
            '${assignment.driverIsActive ? '' : ' (switched off)'}';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        key: ValueKey('booking-${booking.id}'),
        title: Text('${booking.code} - ${booking.serviceName}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(booking.customerName),
            Text('${formatDate(booking.date)}, ${booking.timeLabel}'),
            Text(driverText, key: ValueKey('driver-line-${booking.id}')),
            const SizedBox(height: 4),
            BookingStatusChip(status: booking.status),
          ],
        ),
        isThreeLine: true,
        onTap: () => context.push(AppRoutes.adminBooking(booking.id)),
      ),
    );
  }
}
