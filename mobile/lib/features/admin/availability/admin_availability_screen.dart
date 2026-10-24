import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../data/models/availability.dart';
import '../../../data/providers/data_providers.dart';
import '../providers/admin_providers.dart';

/// Time slots (the weekly routine) and closures / special openings (changes
/// for particular dates).
class AdminAvailabilityScreen extends StatelessWidget {
  const AdminAvailabilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Availability'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Time slots'), Tab(text: 'Closures')],
          ),
        ),
        body: const SafeArea(
          child: TabBarView(children: [_SlotsTab(), _ClosuresTab()]),
        ),
      ),
    );
  }
}

// =============================================================================
// Time slots
// =============================================================================

class _SlotsTab extends ConsumerWidget {
  const _SlotsTab();

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, [
    TimeSlot? slot,
  ]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _SlotDialog(existing: slot),
    );
    if (saved == true) {
      ref.invalidate(adminSlotsProvider);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, TimeSlot slot) async {
    final confirmed = await confirmAction(
      context,
      title: 'Delete ${slot.label}?',
      message: 'Its closures are removed too. A slot with upcoming bookings '
          'cannot be deleted; switch it off instead.',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await ref.read(availabilityRepositoryProvider).deleteSlot(slot.id);
      ref.invalidate(adminSlotsProvider);
      ref.invalidate(adminExceptionsProvider);
    } catch (error) {
      if (context.mounted) {
        showErrorSnack(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(adminSlotsProvider);
    return Stack(
      children: [
        AsyncView<List<TimeSlot>>(
          value: slots,
          onRetry: () => ref.invalidate(adminSlotsProvider),
          builder: (items) {
            if (items.isEmpty) {
              return const EmptyView(
                message: 'No time slots yet. Add the visit windows customers '
                    'can choose from.',
              );
            }
            return RefreshIndicator(
              onRefresh: () => ref.refresh(adminSlotsProvider.future),
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final slot = items[index];
                  return ListTile(
                    title: Row(
                      children: [
                        Flexible(child: Text(slot.label)),
                        if (!slot.isActive) ...[
                          const SizedBox(width: 8),
                          const InactiveBadge(),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      '${describeWeekdays(slot.daysOfWeek)} - '
                      '${slot.capacity} ${slot.capacity == 1 ? 'booking' : 'bookings'} '
                      'at a time',
                    ),
                    onTap: () => _openForm(context, ref, slot),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ActiveSwitch(
                          value: slot.isActive,
                          semanticLabel: '${slot.label} active',
                          onChanged: (value) async {
                            await ref
                                .read(availabilityRepositoryProvider)
                                .updateSlot(slot.id, {'is_active': value});
                            ref.invalidate(adminSlotsProvider);
                          },
                        ),
                        IconButton(
                          tooltip: 'Delete ${slot.label}',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(context, ref, slot),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'add-slot',
            onPressed: () => _openForm(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Add slot'),
          ),
        ),
      ],
    );
  }
}

class _SlotDialog extends ConsumerStatefulWidget {
  const _SlotDialog({this.existing});

  final TimeSlot? existing;

  @override
  ConsumerState<_SlotDialog> createState() => _SlotDialogState();
}

class _SlotDialogState extends ConsumerState<_SlotDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _capacity;
  late ClockTime _start;
  late ClockTime _end;
  late Set<int> _days;
  late bool _active;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _capacity = TextEditingController(text: (s?.capacity ?? 1).toString());
    _start = s?.start ?? const ClockTime(9, 0);
    _end = s?.end ?? const ClockTime(11, 0);
    _days = {...(s?.daysOfWeek ?? const [1, 2, 3, 4, 5, 6, 7])};
    _active = s?.isActive ?? true;
  }

  @override
  void dispose() {
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _pick(bool isStart) async {
    final current = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      final time = ClockTime(picked.hour, picked.minute);
      if (isStart) {
        _start = time;
      } else {
        _end = time;
      }
    });
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) {
      return;
    }
    final orderError = Validators.slotOrder(_start.totalMinutes, _end.totalMinutes);
    if (orderError != null) {
      setState(() => _error = orderError);
      return;
    }
    if (_days.isEmpty) {
      setState(() => _error = 'Choose at least one day of the week');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(availabilityRepositoryProvider);
    final capacity = int.parse(_capacity.text.trim());
    final days = (_days.toList()..sort());
    try {
      final existing = widget.existing;
      if (existing == null) {
        await repo.createSlot(
          start: _start,
          end: _end,
          capacity: capacity,
          daysOfWeek: days,
          isActive: _active,
        );
      } else {
        final changes = <String, dynamic>{
          if (_start != existing.start) 'start_time': _start.toApi(),
          if (_end != existing.end) 'end_time': _end.toApi(),
          if (capacity != existing.capacity) 'capacity': capacity,
          if (days.join(',') != existing.daysOfWeek.join(','))
            'days_of_week': days,
          if (_active != existing.isActive) 'is_active': _active,
        };
        if (changes.isNotEmpty) {
          await repo.updateSlot(existing.id, changes);
        }
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add time slot' : 'Edit time slot'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _pick(true),
                      child: Text('Starts ${_start.format()}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _pick(false),
                      child: Text('Ends ${_end.format()}'),
                    ),
                  ),
                ],
              ),
              fieldGap,
              Text('Days', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var day = 1; day <= 7; day++)
                    FilterChip(
                      label: Text(weekdayShortNames[day - 1]),
                      selected: _days.contains(day),
                      onSelected: _busy
                          ? null
                          : (selected) => setState(() {
                                if (selected) {
                                  _days.add(day);
                                } else {
                                  _days.remove(day);
                                }
                              }),
                    ),
                ],
              ),
              fieldGap,
              TextFormField(
                controller: _capacity,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                validator: Validators.capacity,
                decoration: const InputDecoration(
                  labelText: 'Bookings at a time',
                  helperText: 'For example, how many crews are available',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Available to customers'),
                value: _active,
                onChanged: _busy ? null : (v) => setState(() => _active = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

// =============================================================================
// Closures and special openings
// =============================================================================

class _ClosuresTab extends ConsumerWidget {
  const _ClosuresTab();

  Future<void> _openForm(BuildContext context, WidgetRef ref) async {
    final slots = ref.read(adminSlotsProvider).valueOrNull ?? const <TimeSlot>[];
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ExceptionDialog(slots: slots),
    );
    if (saved == true) {
      ref.invalidate(adminExceptionsProvider);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AvailabilityException exception,
  ) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove this entry?',
      message: 'The normal weekly routine applies again on '
          '${formatDate(exception.date)}.',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await ref.read(availabilityRepositoryProvider).deleteException(exception.id);
      ref.invalidate(adminExceptionsProvider);
    } catch (error) {
      if (context.mounted) {
        showErrorSnack(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exceptions = ref.watch(adminExceptionsProvider);
    final slots = ref.watch(adminSlotsProvider).valueOrNull ?? const <TimeSlot>[];
    String slotLabel(String? id) {
      if (id == null) {
        return 'Whole day';
      }
      final matches = slots.where((s) => s.id == id);
      return matches.isEmpty ? 'One slot' : matches.first.label;
    }

    return Stack(
      children: [
        AsyncView<List<AvailabilityException>>(
          value: exceptions,
          onRetry: () => ref.invalidate(adminExceptionsProvider),
          builder: (items) {
            if (items.isEmpty) {
              return const EmptyView(
                message: 'No closures in the next '
                    '$closuresLookAheadDays days. Add a holiday or a day off.',
              );
            }
            return RefreshIndicator(
              onRefresh: () => ref.refresh(adminExceptionsProvider.future),
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final e = items[index];
                  final what = e.isOpen
                      ? 'Special opening'
                      : (e.isWholeDay ? 'Closed' : 'Slot closed');
                  final extras = [
                    slotLabel(e.timeSlotId),
                    if (e.isOpen && e.capacity != null)
                      '${e.capacity} at a time',
                    if (e.reason != null) e.reason!,
                  ];
                  return ListTile(
                    leading: Icon(
                      e.isOpen ? Icons.event_available : Icons.event_busy,
                    ),
                    title: Text('${formatDate(e.date)} - $what'),
                    subtitle: Text(extras.join(' - ')),
                    trailing: IconButton(
                      tooltip: 'Remove entry',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(context, ref, e),
                    ),
                  );
                },
              ),
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'add-closure',
            onPressed: () => _openForm(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Add closure'),
          ),
        ),
      ],
    );
  }
}

class _ExceptionDialog extends ConsumerStatefulWidget {
  const _ExceptionDialog({required this.slots});

  final List<TimeSlot> slots;

  @override
  ConsumerState<_ExceptionDialog> createState() => _ExceptionDialogState();
}

class _ExceptionDialogState extends ConsumerState<_ExceptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _capacity = TextEditingController();
  late DateTime _date;
  String? _slotId; // null = whole day
  bool _open = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _reason.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  String? _validateCapacity(String? value) {
    if (!_open || (value ?? '').trim().isEmpty) {
      return null;
    }
    return Validators.capacity(value);
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final reason = _reason.text.trim().isEmpty ? null : _reason.text.trim();
    final capacityText = _capacity.text.trim();
    try {
      await ref.read(availabilityRepositoryProvider).createException(
            date: _date,
            timeSlotId: _slotId,
            isOpen: _slotId != null && _open,
            capacity: _slotId != null && _open && capacityText.isNotEmpty
                ? int.parse(capacityText)
                : null,
            reason: reason,
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add closure or special opening'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(formatDate(_date)),
              ),
              fieldGap,
              DropdownButtonFormField<String?>(
                value: _slotId,
                decoration: const InputDecoration(labelText: 'Applies to'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Whole day'),
                  ),
                  for (final slot in widget.slots)
                    DropdownMenuItem<String?>(
                      value: slot.id,
                      child: Text(slot.label),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                          _slotId = value;
                          if (value == null) {
                            _open = false;
                          }
                        }),
              ),
              if (_slotId != null) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Open this slot on this date'),
                  subtitle: const Text(
                    'Use for a day it does not normally run. Off = close it.',
                  ),
                  value: _open,
                  onChanged: _busy ? null : (v) => setState(() => _open = v),
                ),
                if (_open)
                  TextFormField(
                    controller: _capacity,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    validator: _validateCapacity,
                    decoration: const InputDecoration(
                      labelText: 'Bookings at a time (optional)',
                      helperText: 'Empty = the slot\'s usual capacity',
                    ),
                  ),
              ],
              fieldGap,
              TextFormField(
                controller: _reason,
                enabled: !_busy,
                maxLength: 200,
                validator: (v) =>
                    Validators.optionalText(v, label: 'reason', max: 200),
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  helperText: 'Shown to customers, e.g. "Closed for Diwali"',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
