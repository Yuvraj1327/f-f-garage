import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../providers/booking_providers.dart';
import 'booking_widgets.dart';
import 'schedule_picker.dart';

/// Step 2 of booking: pick the date and time slot.
class BookingScheduleScreen extends ConsumerWidget {
  const BookingScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(bookingFlowProvider);
    if (!flow.hasPackage || flow.address == null) {
      return const NothingSelectedView();
    }
    final schedule = flow.schedule;
    return Scaffold(
      appBar: AppBar(title: const Text('When should we come?')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SchedulePicker(
                    selected: schedule,
                    onChanged: (value) => ref
                        .read(bookingFlowProvider.notifier)
                        .setSchedule(value),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: schedule == null
                      ? null
                      : () => context.push(AppRoutes.bookSummary),
                  child: const Text('Continue'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
