import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/preferences/app_preferences.dart';
import '../providers/notification_providers.dart';

/// The bell in the customer's app bar, with the number of unread updates.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final showBadge = ref.watch(notificationPrefsProvider.select((p) => p.showBadge));
    return IconButton(
      key: const ValueKey('notifications-bell'),
      tooltip: unread > 0 ? 'Notifications ($unread unread)' : 'Notifications',
      icon: Badge(
        isLabelVisible: showBadge && unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () async {
        await context.push(AppRoutes.notifications);
        ref.invalidate(unreadCountProvider);
      },
    );
  }
}
