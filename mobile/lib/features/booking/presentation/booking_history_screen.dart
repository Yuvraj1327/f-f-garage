import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../data/models/booking.dart';
import '../../../data/providers/data_providers.dart';
import '../providers/booking_providers.dart';
import '../../payment/presentation/payment_widgets.dart';
import 'booking_widgets.dart';

const int _pageSize = 20;

/// The customer's bookings, newest first, with a status filter and
/// "Load more" paging.
class BookingHistoryScreen extends ConsumerStatefulWidget {
  const BookingHistoryScreen({super.key});

  @override
  ConsumerState<BookingHistoryScreen> createState() =>
      _BookingHistoryScreenState();
}

class _BookingHistoryScreenState extends ConsumerState<BookingHistoryScreen> {
  BookingFilter _filter = BookingFilter.all;
  List<Booking> _items = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  /// Ignores answers to requests that were superseded (filter changed, refresh).
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    // After the first frame, so the loading state is drawn before the request starts.
    Future.microtask(_reload);
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(bookingRepositoryProvider).list(
            statuses: _filter.statuses,
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
      final page = await ref.read(bookingRepositoryProvider).list(
            statuses: _filter.statuses,
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
      showSnack(context, errorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Something was booked, changed or cancelled elsewhere: reload.
    ref.listen<int>(bookingsRefreshProvider, (_, __) => _reload());
    return Scaffold(
      appBar: AppBar(title: const Text('My bookings')),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final filter in BookingFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
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
            Expanded(child: _buildList(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const ListSkeleton();
    }
    if (_error != null && _items.isEmpty) {
      return ErrorView(message: _error!, onRetry: _reload);
    }
    if (_items.isEmpty) {
      return EmptyView(
        icon: Icons.receipt_long_outlined,
        message: _filter == BookingFilter.all
            ? 'You have no bookings yet.'
            : 'No ${_filter.label.toLowerCase()} bookings.',
        action: _filter == BookingFilter.all
            ? FilledButton(
                onPressed: () => context.push(AppRoutes.browseServices),
                child: const Text('Browse services'),
              )
            : null,
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        key: ValueKey('booking-${booking.id}'),
        title: Text(
          '${booking.code} - ${booking.serviceName}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(booking.packageName),
            Text('${formatDate(booking.date)}, ${booking.timeLabel}'),
            Text(
              bookingProgressLine(booking),
              key: ValueKey('progress-line-${booking.id}'),
            ),
            if (booking.payment != null)
              Text(
                paymentSummaryLine(booking.payment!),
                key: ValueKey('payment-line-${booking.id}'),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                BookingStatusChip(status: booking.status),
                const Spacer(),
                Text(formatMoney(booking.totalAmount)),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(AppRoutes.booking(booking.id)),
      ),
    );
  }
}
