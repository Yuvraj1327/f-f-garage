import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/json_reader.dart';
import '../../../data/providers/data_providers.dart';
import '../providers/booking_providers.dart';
import 'schedule_picker.dart';

/// Change the address, notes or time of a booking that has not been assigned
/// yet. The service, package and price cannot be changed here.
class BookingEditScreen extends ConsumerWidget {
  const BookingEditScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(bookingProvider(bookingId));
    return value.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Change booking')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Change booking')),
        body: ErrorView(
          message: errorMessage(error),
          onRetry: () => ref.invalidate(bookingProvider(bookingId)),
        ),
      ),
      data: (booking) => _EditForm(booking: booking),
    );
  }
}

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({required this.booking});

  final Booking booking;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _pincode;
  late final TextEditingController _address;
  late final TextEditingController _landmark;
  late final TextEditingController _notes;
  BookingSchedule? _newSchedule;
  bool _changingTime = false;
  bool _busy = false;
  String? _error;

  Booking get _booking => widget.booking;

  @override
  void initState() {
    super.initState();
    _pincode = TextEditingController(text: _booking.pincode);
    _address = TextEditingController(text: _booking.addressLine);
    _landmark = TextEditingController(text: _booking.landmark ?? '');
    _notes = TextEditingController(text: _booking.notes ?? '');
  }

  @override
  void dispose() {
    _pincode.dispose();
    _address.dispose();
    _landmark.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Only what actually changed, in the API's field names. A field the customer
  /// emptied is sent as null so it is cleared.
  Map<String, dynamic> _changes() {
    final changes = <String, dynamic>{};
    final pincode = Validators.normalizePincode(_pincode.text);
    if (pincode != _booking.pincode) {
      changes['pincode'] = pincode;
    }
    final address = Validators.normalizeName(_address.text);
    if (address != _booking.addressLine) {
      changes['address_line'] = address;
    }
    final landmark = _landmark.text.trim();
    if (landmark != (_booking.landmark ?? '')) {
      changes['landmark'] = landmark.isEmpty ? null : landmark;
    }
    final notes = _notes.text.trim();
    if (notes != (_booking.notes ?? '')) {
      changes['customer_notes'] = notes.isEmpty ? null : notes;
    }
    final schedule = _newSchedule;
    if (schedule != null &&
        !(schedule.date == _booking.date &&
            schedule.start == _booking.slotStart &&
            schedule.end == _booking.slotEnd)) {
      changes['scheduled_date'] = formatApiDate(schedule.date);
      changes['time_slot_id'] = schedule.slotId;
    }
    return changes;
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) {
      return;
    }
    final changes = _changes();
    if (changes.isEmpty) {
      showSnack(context, 'No changes to save');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(bookingRepositoryProvider).update(_booking.id, changes);
      if (!mounted) return;
      refreshBookings(ref, bookingId: _booking.id);
      ref.invalidate(bookableDaysProvider);
      showSnack(context, 'Booking updated');
      context.pop();
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
    final schedule = _newSchedule;
    return FormPage(
      title: 'Change booking',
      formKey: _formKey,
      busy: _busy,
      error: _error,
      onSave: _save,
      children: [
        Text(
          '${_booking.code} - ${_booking.serviceName}, ${_booking.packageName}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'The service and price cannot be changed. To book something else, '
          'cancel this booking and make a new one.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        fieldGap,
        TextFormField(
          controller: _pincode,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          maxLength: 7,
          validator: Validators.pincode,
          decoration: const InputDecoration(
            labelText: 'PIN code',
            counterText: '',
          ),
        ),
        fieldGap,
        TextFormField(
          controller: _address,
          enabled: !_busy,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          validator: (v) => Validators.requiredText(
            v,
            label: 'address',
            min: 5,
            max: 250,
          ),
          decoration: const InputDecoration(
            labelText: 'House / flat, street and area',
          ),
        ),
        fieldGap,
        TextFormField(
          controller: _landmark,
          enabled: !_busy,
          validator: (v) =>
              Validators.optionalText(v, label: 'landmark', max: 120),
          decoration: const InputDecoration(labelText: 'Landmark (optional)'),
        ),
        fieldGap,
        TextFormField(
          controller: _notes,
          enabled: !_busy,
          minLines: 1,
          maxLines: 3,
          validator: (v) => Validators.optionalText(v, label: 'notes', max: 500),
          decoration: const InputDecoration(
            labelText: 'Notes for the driver (optional)',
          ),
        ),
        fieldGap,
        Text('Visit time', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          schedule == null
              ? '${formatDate(_booking.date)}, ${_booking.timeLabel}'
              : '${formatDate(schedule.date)}, ${schedule.timeLabel} (new)',
        ),
        const SizedBox(height: 8),
        if (!_changingTime)
          OutlinedButton(
            onPressed: _busy ? null : () => setState(() => _changingTime = true),
            child: const Text('Change date or time'),
          )
        else
          SchedulePicker(
            selected: schedule,
            onChanged: (value) => setState(() => _newSchedule = value),
          ),
      ],
    );
  }
}
