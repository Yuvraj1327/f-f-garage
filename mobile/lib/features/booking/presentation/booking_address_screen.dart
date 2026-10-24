import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../data/providers/data_providers.dart';
import '../providers/booking_providers.dart';
import 'booking_widgets.dart';

/// Step 1 of booking: where should we come? The PIN code is checked with the
/// server so only serviceable addresses go further.
class BookingAddressScreen extends ConsumerStatefulWidget {
  const BookingAddressScreen({super.key});

  @override
  ConsumerState<BookingAddressScreen> createState() =>
      _BookingAddressScreenState();
}

class _BookingAddressScreenState extends ConsumerState<BookingAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _pincode;
  late final TextEditingController _address;
  late final TextEditingController _landmark;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(bookingFlowProvider).address;
    _pincode = TextEditingController(text: saved?.pincode ?? '');
    _address = TextEditingController(text: saved?.addressLine ?? '');
    _landmark = TextEditingController(text: saved?.landmark ?? '');
  }

  @override
  void dispose() {
    _pincode.dispose();
    _address.dispose();
    _landmark.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_busy || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final pincode = Validators.normalizePincode(_pincode.text);
    try {
      final check =
          await ref.read(serviceAreaRepositoryProvider).checkPincode(pincode);
      if (!mounted) return;
      if (!check.serviceable) {
        setState(() {
          _busy = false;
          _error = 'Sorry, we do not service $pincode yet.';
        });
        return;
      }
      final landmark = _landmark.text.trim();
      ref.read(bookingFlowProvider.notifier).setAddress(
            BookingAddress(
              pincode: pincode,
              addressLine: Validators.normalizeName(_address.text),
              landmark: landmark.isEmpty ? null : landmark,
              areaName: check.areaName ?? '',
              city: check.city ?? '',
            ),
          );
      setState(() => _busy = false);
      context.push(AppRoutes.bookSchedule);
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
    final flow = ref.watch(bookingFlowProvider);
    final package = flow.package;
    if (!flow.hasPackage || package == null) {
      return const NothingSelectedView();
    }
    return FormPage(
      title: 'Where should we come?',
      formKey: _formKey,
      busy: _busy,
      error: _error,
      onSave: _continue,
      saveLabel: 'Continue',
      children: [
        Text(
          '${flow.service!.name} - ${package.name} (${formatMoney(package.price)})',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        fieldGap,
        TextFormField(
          controller: _pincode,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
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
          textCapitalization: TextCapitalization.sentences,
          validator: (v) =>
              Validators.optionalText(v, label: 'landmark', max: 120),
          decoration: const InputDecoration(
            labelText: 'Landmark (optional)',
            helperText: 'Helps our driver find you',
          ),
        ),
      ],
    );
  }
}
