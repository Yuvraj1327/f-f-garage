import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/driver_job.dart';
import '../../../data/models/enums.dart';
import '../../../data/providers/data_providers.dart';

/// Bumped when the driver changed a booking, so the lists reload.
final driverJobsRefreshProvider = StateProvider<int>((ref) => 0);

final driverJobProvider = FutureProvider.autoDispose.family<DriverJob, String>(
  (ref, id) => ref.watch(driverWorkRepositoryProvider).get(id),
);

/// Reloads the lists and the open booking after a status step.
void refreshDriverJobs(WidgetRef ref, {String? jobId}) {
  ref.read(driverJobsRefreshProvider.notifier).state++;
  if (jobId != null) {
    ref.invalidate(driverJobProvider(jobId));
  }
}

/// Real figures for the driver's dashboard, worked out from the same API the
/// job lists use (no separate endpoint, no prices).
class DriverSummary {
  const DriverSummary({
    required this.today,
    required this.completedToday,
    required this.open,
    required this.completedThisMonth,
    required this.finishedTotal,
  });

  /// Jobs scheduled for today (open or finished).
  final int today;
  final int completedToday;

  /// Jobs still to do, whatever the day.
  final int open;

  /// Completed bookings dated this calendar month.
  final int completedThisMonth;

  /// Every finished booking (completed or cancelled) the driver has had.
  final int finishedTotal;
}

final driverSummaryProvider = FutureProvider.autoDispose<DriverSummary>((ref) async {
  ref.watch(driverJobsRefreshProvider);
  final repo = ref.watch(driverWorkRepositoryProvider);
  final open = await repo.list(scope: 'open', limit: 100);
  final history = await repo.list(scope: 'history', limit: 100);
  final now = DateTime.now();
  bool isToday(DateTime d) =>
      d.year == now.year && d.month == now.month && d.day == now.day;
  final all = [...open.items, ...history.items];
  return DriverSummary(
    today: all.where((j) => isToday(j.date)).length,
    completedToday: history.items
        .where((j) => j.status == BookingStatus.completed && isToday(j.date))
        .length,
    open: open.total,
    completedThisMonth: history.items
        .where((j) =>
            j.status == BookingStatus.completed &&
            j.date.year == now.year &&
            j.date.month == now.month)
        .length,
    finishedTotal: history.total,
  );
});
