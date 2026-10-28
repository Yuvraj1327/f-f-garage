import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../data/models/app_notification.dart';
import '../../../data/providers/data_providers.dart';
import '../../booking/providers/booking_providers.dart';
import '../providers/notification_providers.dart';

const int _pageSize = 20;

/// The customer's booking and payment updates, newest first.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<AppNotification> _items = const [];
  int _total = 0;
  int _unread = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _markingAll = false;
  String? _error;

  /// Ignores answers to requests that were superseded.
  int _generation = 0;

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
          .read(notificationRepositoryProvider)
          .list(limit: _pageSize);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        _unread = page.unread;
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
      final page = await ref
          .read(notificationRepositoryProvider)
          .list(limit: _pageSize, offset: _items.length);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = [..._items, ...page.items];
        _total = page.total;
        _unread = page.unread;
      });
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _open(AppNotification item) async {
    if (!item.isRead) {
      setState(() {
        _items = [for (final n in _items) n.id == item.id ? n.asRead() : n];
        _unread = _unread > 0 ? _unread - 1 : 0;
      });
      try {
        await ref.read(notificationRepositoryProvider).markRead([item.id]);
        ref.invalidate(unreadCountProvider);
      } catch (_) {
        // Not marked on the server: show the truth on the next load.
        if (mounted) _reload();
      }
    }
    if (!mounted || item.bookingId == null) return;
    await context.push(AppRoutes.booking(item.bookingId!));
  }

  Future<void> _markAll() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    try {
      await ref.read(notificationRepositoryProvider).markRead();
      if (!mounted) return;
      setState(() {
        _items = [for (final n in _items) n.asRead()];
        _unread = 0;
      });
      ref.invalidate(unreadCountProvider);
      showSnack(context, 'All notifications marked as read');
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Something changed on a booking: a new notification may be waiting.
    ref.listen<int>(bookingsRefreshProvider, (_, __) => _reload());
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            key: const ValueKey('mark-all-read'),
            onPressed: _unread > 0 && !_markingAll ? _markAll : null,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return ErrorView(message: _error!, onRetry: _reload);
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          children: const [
            SizedBox(height: 80),
            EmptyView(
              message: 'No notifications yet.\n'
                  'Updates about your bookings will appear here.',
            ),
          ],
        ),
      );
    }
    final hasMore = _items.length < _total;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
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
          return _Tile(item: _items[index], onTap: _open);
        },
      ),
    );
  }
}

IconData _iconFor(String kind) {
  switch (kind) {
    case 'booking_confirmed':
      return Icons.check_circle_outline;
    case 'payment_failed':
      return Icons.error_outline;
    case 'driver_assigned':
    case 'driver_changed':
    case 'driver_removed':
      return Icons.person_outline;
    case 'driver_on_the_way':
      return Icons.two_wheeler;
    case 'service_started':
      return Icons.build_outlined;
    case 'service_completed':
      return Icons.verified_outlined;
    case 'booking_cancelled':
      return Icons.cancel_outlined;
    case 'extra_charge_requested':
      return Icons.build_circle_outlined;
    case 'refund_recorded':
      return Icons.currency_rupee;
    default:
      return Icons.notifications_outlined;
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.onTap});

  final AppNotification item;
  final Future<void> Function(AppNotification item) onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      key: ValueKey('notification-${item.id}'),
      leading: Icon(_iconFor(item.kind)),
      title: Text(
        item.title,
        style: item.isRead
            ? null
            : textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.body),
          Text(formatDateTime(item.createdAt), style: textTheme.bodySmall),
        ],
      ),
      isThreeLine: true,
      trailing: item.isRead
          ? null
          : Icon(
              Icons.circle,
              key: ValueKey('unread-dot-${item.id}'),
              size: 10,
              color: Theme.of(context).colorScheme.primary,
            ),
      onTap: () => onTap(item),
    );
  }
}
