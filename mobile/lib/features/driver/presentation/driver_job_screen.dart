import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../data/models/driver_job.dart';
import '../../../data/models/enums.dart';
import '../../../data/providers/data_providers.dart';
import '../../auth/presentation/widgets/auth_widgets.dart' show MessageBanner;
import '../../booking/presentation/booking_widgets.dart';
import '../providers/driver_providers.dart';
import 'driver_widgets.dart';

/// One assigned booking: what to do, for whom, where and when, and the single
/// next step the driver may record.
class DriverJobScreen extends ConsumerStatefulWidget {
  const DriverJobScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<DriverJobScreen> createState() => _DriverJobScreenState();
}

class _DriverJobScreenState extends ConsumerState<DriverJobScreen> {
  bool _busy = false;

  Future<void> _step(DriverJob job, BookingStatus next) async {
    final confirmed = await confirmAction(
      context,
      title: driverStepLabel(next),
      message: driverStepQuestion(next),
      confirmLabel: 'Yes',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(driverWorkRepositoryProvider).updateStatus(job.id, next);
      if (!mounted) return;
      refreshDriverJobs(ref, jobId: job.id);
      showSuccessSnack(context, driverStepDone(next));
    } catch (error) {
      if (!mounted) return;
      // The booking may have been cancelled or moved: reload so the screen
      // shows what is true now.
      refreshDriverJobs(ref, jobId: job.id);
      showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(driverJobProvider(widget.bookingId));
    final next = value.valueOrNull?.nextStatus;
    return Scaffold(
      appBar: AppBar(title: Text(value.valueOrNull?.code ?? 'Job')),
      // The one action a driver needs stays pinned, however long the details are.
      bottomNavigationBar: next == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  key: const ValueKey('next-step'),
                  icon: _busy ? const SizedBox.shrink() : Icon(_stepIcon(next)),
                  onPressed: _busy
                      ? null
                      : () => _step(value.requireValue, next),
                  label: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(driverStepLabel(next)),
                ),
              ),
            ),
      body: SafeArea(
        child: AsyncView<DriverJob>(
          value: value,
          onRetry: () => ref.invalidate(driverJobProvider(widget.bookingId)),
          builder: (job) => RefreshIndicator(
            onRefresh: () =>
                ref.refresh(driverJobProvider(widget.bookingId).future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [BookingStatusChip(status: job.status)]),
                ),
                if (job.status == BookingStatus.cancelled)
                  const MessageBanner(
                    message: 'This booking was cancelled. No visit is needed.',
                  ),
                if (job.status == BookingStatus.completed)
                  const MessageBanner(
                    isError: false,
                    message: 'This job is completed.',
                  ),
                _Details(job: job),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData _stepIcon(BookingStatus next) {
  switch (next) {
    case BookingStatus.onTheWay:
      return Icons.two_wheeler;
    case BookingStatus.inProgress:
      return Icons.build_outlined;
    case BookingStatus.completed:
      return Icons.task_alt;
    default:
      return Icons.arrow_forward;
  }
}

/// A one-line row of contact info with a one-tap action (call / open map).
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.child,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Widget child;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: child),
        IconButton(tooltip: tooltip, icon: Icon(icon), onPressed: onPressed),
      ],
    );
  }
}

class _Details extends ConsumerWidget {
  const _Details({required this.job});

  final DriverJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final launcher = ref.read(contactLauncherProvider);
    Future<void> open(Future<bool> Function() action, String fallback) async {
      final opened = await action();
      if (!opened && context.mounted) {
        showSnack(context, "Couldn't open that on this device. $fallback");
      }
    }

    final duration = job.durationMinutes;
    final hasLocation = job.latitude != null && job.longitude != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Service',
          children: [
            Text(
              '${job.serviceName} - ${job.packageName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${vehicleLabel(job.vehicleType)}'
              '${duration == null ? '' : ' - about ${formatDuration(duration)}'}',
            ),
            if (job.inclusions.isNotEmpty) ...[
              const SizedBox(height: 8),
              InclusionList(items: job.inclusions),
            ],
            if (job.charges.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Extras', style: Theme.of(context).textTheme.labelMedium),
              for (final charge in job.charges)
                Text(
                  charge.includedInTotal
                      ? '- ${charge.name}'
                      : '- ${charge.name} (if needed)',
                ),
            ],
          ],
        ),
        SectionCard(
          title: 'When',
          children: [Text(formatDate(job.date)), Text(job.timeLabel)],
        ),
        SectionCard(
          title: 'Customer',
          children: [
            Text(job.customerName),
            _ActionRow(
              icon: Icons.call_outlined,
              tooltip: 'Call customer',
              onPressed: () => open(
                () => launcher.call(job.customerPhone),
                'Customer: ${job.customerPhone}',
              ),
              child: SelectableText(
                job.customerPhone,
                key: const ValueKey('phone'),
              ),
            ),
          ],
        ),
        SectionCard(
          title: 'Where',
          children: [
            _ActionRow(
              icon: Icons.directions_outlined,
              tooltip: 'Open in maps',
              onPressed: () => open(
                () => launcher.map(_mapQuery(job)),
                'Address: ${_mapQuery(job)}',
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(job.addressLine),
                  if (job.landmark != null) Text('Landmark: ${job.landmark}'),
                  Text(
                    '${job.city}${job.state == null ? '' : ', ${job.state}'} '
                    '${job.pincode}',
                  ),
                ],
              ),
            ),
            if (hasLocation)
              Text('Location: ${job.latitude}, ${job.longitude}'),
          ],
        ),
        if (job.notes != null)
          SectionCard(
            title: 'Customer notes',
            children: [Text(job.notes!)],
          ),
      ],
    );
  }
}

/// The coordinates when the customer shared a location, otherwise the address.
String _mapQuery(DriverJob job) {
  if (job.latitude != null && job.longitude != null) {
    return '${job.latitude},${job.longitude}';
  }
  return '${job.addressLine}, ${job.city} ${job.pincode}';
}
