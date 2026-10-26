import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/preferences/app_preferences.dart';
import '../../../data/providers/data_providers.dart';
import '../../booking/providers/booking_providers.dart';

/// How often the app checks for booking updates while a screen that shows them
/// is open. (There is no push connection: the app asks.) Tests override it.
final trackingPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 30),
);

/// The unread count seen on the previous check; null before the first one.
final _lastUnreadProvider = StateProvider<int?>((ref) => null);

/// How many notifications are unread. It checks again every
/// [trackingPollIntervalProvider] while something is watching it. When the
/// count goes up, something happened to a booking, so the booking screens are
/// told to reload too.
final unreadCountProvider = FutureProvider.autoDispose<int>((ref) async {
  if (ref.watch(notificationPrefsProvider.select((p) => p.autoRefresh))) {
    final timer =
        Timer(ref.watch(trackingPollIntervalProvider), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  final count = await ref.watch(notificationRepositoryProvider).unreadCount();
  final last = ref.read(_lastUnreadProvider);
  ref.read(_lastUnreadProvider.notifier).state = count;
  if (last != null && count > last) {
    ref.read(bookingsRefreshProvider.notifier).state++;
  }
  return count;
});
