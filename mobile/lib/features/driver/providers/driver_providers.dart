import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/driver_job.dart';
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
