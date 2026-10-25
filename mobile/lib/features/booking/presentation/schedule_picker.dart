import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/async_view.dart';
import '../../../data/models/availability.dart';
import '../providers/booking_providers.dart';

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String slotReasonText(String? reason) {
  switch (reason) {
    case 'fully_booked':
      return 'Fully booked';
    case 'lead_time_passed':
      return 'Too late to book';
    case 'closed':
      return 'Closed';
    default:
      return 'Not available';
  }
}

/// Pick a date, then one of that day's time slots. Days and slots that cannot
/// be booked are shown but cannot be chosen; the server checks again when the
/// booking is made.
class SchedulePicker extends ConsumerStatefulWidget {
  const SchedulePicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final BookingSchedule? selected;
  final ValueChanged<BookingSchedule> onChanged;

  @override
  ConsumerState<SchedulePicker> createState() => _SchedulePickerState();
}

class _SchedulePickerState extends ConsumerState<SchedulePicker> {
  DateTime? _day;

  @override
  void initState() {
    super.initState();
    _day = widget.selected?.date;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(bookableDaysProvider);
    return AsyncView<List<DayAvailability>>(
      value: value,
      onRetry: () => ref.invalidate(bookableDaysProvider),
      builder: (days) {
        if (!days.any((d) => d.isOpen)) {
          return const EmptyView(
            message: 'No dates are open for booking right now. '
                'Please check back soon.',
          );
        }
        final day = _day == null
            ? null
            : days.where((d) => _sameDay(d.date, _day!)).firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose a date', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: days.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) => _DayChip(
                  day: days[index],
                  selected: day != null && _sameDay(days[index].date, day.date),
                  onTap: () => setState(() => _day = days[index].date),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Choose a time', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (day == null)
              const Text('Pick a date to see the available times.')
            else ...[
              if (day.note != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(day.note!),
                ),
              if (day.slots.isEmpty)
                const Text('There are no time slots on this date.')
              else
                for (final slot in day.slots)
                  _SlotTile(
                    slot: slot,
                    selected: widget.selected?.slotId == slot.slotId &&
                        widget.selected != null &&
                        _sameDay(widget.selected!.date, day.date),
                    onTap: () => widget.onChanged(
                      BookingSchedule(
                        date: day.date,
                        slotId: slot.slotId,
                        start: slot.start,
                        end: slot.end,
                      ),
                    ),
                  ),
            ],
          ],
        );
      },
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final DayAvailability day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = day.date;
    final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final scheme = Theme.of(context).colorScheme;
    final textColor = selected ? scheme.onPrimary : scheme.onSurface;
    return ChoiceChip(
      key: ValueKey('day-$key'),
      selected: selected,
      selectedColor: scheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: day.isOpen ? (_) => onTap() : null,
      label: SizedBox(
        width: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              weekdayShortNames[date.weekday - 1],
              style: TextStyle(color: textColor),
            ),
            Text(
              '${date.day}',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: textColor),
            ),
            Text(_months[date.month - 1], style: TextStyle(color: textColor)),
          ],
        ),
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.slot,
    required this.selected,
    required this.onTap,
  });

  final SlotAvailability slot;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final available = slot.available;
    final label = '${slot.start.format()} - ${slot.end.format()}';
    return Card(
      key: ValueKey('slot-${slot.slotId}'),
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            )
          : null,
      child: ListTile(
        enabled: available,
        selected: selected,
        title: Text(label),
        subtitle: Text(
          available
              ? (slot.spotsLeft == 1 ? '1 spot left' : '${slot.spotsLeft} spots left')
              : slotReasonText(slot.reason),
        ),
        trailing: selected ? const Icon(Icons.check_circle) : null,
        onTap: available ? onTap : null,
      ),
    );
  }
}
