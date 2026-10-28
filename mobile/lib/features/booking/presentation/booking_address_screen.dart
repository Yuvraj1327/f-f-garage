import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../data/models/place.dart';
import '../../../data/providers/data_providers.dart';
import '../../maps/location_field.dart';
import '../providers/booking_providers.dart';
import 'booking_widgets.dart';

/// Step 1 of booking: where should we come? The PIN code is checked with the
/// server so only serviceable addresses go further.
class BookingAddressScreen extends ConsumerStatefulWidget {
  const BookingAddressScreen({super.key, this.pickOnly = false});

  /// Opened from the checkout to confirm or change the location: saving goes
  /// back to it instead of continuing to the time step.
  final bool pickOnly;

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

  /// The map pin, and the PIN code it was chosen with. Typing a different PIN
  /// code afterwards drops the pin: it would point at the wrong place.
  MapPoint? _point;
  String? _pinnedPincode;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(bookingFlowProvider).address;
    _pincode = TextEditingController(text: saved?.pincode ?? '');
    _address = TextEditingController(text: saved?.addressLine ?? '');
    _landmark = TextEditingController(text: saved?.landmark ?? '');
    _point = saved?.point;
    _pinnedPincode = saved?.point == null ? null : saved?.pincode;
  }

  /// The customer chose a spot on the map (or used their location).
  void _onPicked(PickedLocation picked) {
    final place = picked.place;
    final pin = place?.pincode;
    final keptTypedAddress = _address.text.trim().isNotEmpty;
    setState(() {
      _point = picked.point;
      if (pin != null) {
        _pincode.text = pin;
      }
      final known = Validators.normalizePincode(_pincode.text);
      _pinnedPincode = known.isEmpty ? null : known;
      if (place != null && !keptTypedAddress) {
        _address.text = _shortAddress(place.formattedAddress);
      }
    });
    if (place != null && keptTypedAddress) {
      showSnack(context, 'Location saved. The address you typed was kept.');
    }
  }

  /// A previous booking's address, used again with its map pin.
  void _usePrevious(PreviousAddress previous) {
    setState(() {
      _pincode.text = previous.pincode;
      _address.text = previous.addressLine;
      _landmark.text = previous.landmark ?? '';
      _point = previous.point;
      _pinnedPincode = previous.point == null ? null : previous.pincode;
      _error = null;
    });
  }

  void _onPincodeChanged(String value) {
    if (_point == null) {
      return;
    }
    final typed = Validators.normalizePincode(value);
    final pinned = _pinnedPincode;
    if (pinned == null) {
      // The pin was chosen before any PIN code was known (the address lookup
      // was unavailable): the first full PIN code typed belongs to it.
      if (typed.length == 6) {
        _pinnedPincode = typed;
      }
      return;
    }
    if (typed != pinned) {
      setState(() {
        _point = null;
        _pinnedPincode = null;
      });
    }
  }

  /// Someone pasted a whole address: take the PIN code out of it.
  void _onAddressChanged(String value) {
    if (_pincode.text.trim().isNotEmpty) {
      return;
    }
    final found = Validators.extractPincode(value);
    if (found != null) {
      _pincode.text = found;
    }
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
              latitude: _point?.latitude,
              longitude: _point?.longitude,
            ),
          );
      setState(() => _busy = false);
      if (widget.pickOnly) {
        context.pop();
      } else {
        context.push(AppRoutes.bookSchedule);
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
    final flow = ref.watch(bookingFlowProvider);
    final package = flow.package;
    if (!widget.pickOnly && (!flow.hasPackage || package == null)) {
      return const NothingSelectedView();
    }
    return FormPage(
      title: widget.pickOnly ? 'Service location' : 'Where should we come?',
      formKey: _formKey,
      busy: _busy,
      error: _error,
      onSave: _continue,
      saveLabel: widget.pickOnly ? 'Use this location' : 'Continue',
      children: [
        if (package != null && flow.service != null)
          Text(
            '${flow.service!.name} - ${package.name} (${formatMoney(package.price)})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        _PreviousAddresses(onUse: _busy ? null : _usePrevious),
        fieldGap,
        TextFormField(
          controller: _pincode,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          maxLength: 7,
          validator: Validators.pincode,
          onChanged: _onPincodeChanged,
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
          onChanged: _onAddressChanged,
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
        fieldGap,
        LocationField(
          point: _point,
          enabled: !_busy,
          onPicked: _onPicked,
          onCleared: () => setState(() {
            _point = null;
            _pinnedPincode = null;
          }),
        ),
      ],
    );
  }
}

/// Google's formatted address ends with ", India"; the form does not need it,
/// and the field allows at most 250 characters.
String _shortAddress(String formatted) {
  var text = formatted.trim();
  if (text.endsWith(', India')) {
    text = text.substring(0, text.length - ', India'.length);
  }
  return text.length > 250 ? text.substring(0, 250) : text;
}

/// "Use a previous address": shown only when there is something to offer.
class _PreviousAddresses extends ConsumerWidget {
  const _PreviousAddresses({required this.onUse});

  final ValueChanged<PreviousAddress>? onUse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previous = ref.watch(previousAddressesProvider).valueOrNull;
    if (previous == null || previous.isEmpty) {
      return const SizedBox.shrink();
    }
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fieldGap,
        Text('Use a previous address', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final address in previous)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              key: ValueKey('previous-${address.pincode}-${address.addressLine}'),
              leading: Icon(
                address.point == null
                    ? Icons.home_outlined
                    : Icons.location_on_outlined,
              ),
              title: Text(
                address.addressLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                address.point == null
                    ? 'PIN ${address.pincode}'
                    : 'PIN ${address.pincode} - map pin saved',
              ),
              onTap: onUse == null ? null : () => onUse!(address),
            ),
          ),
      ],
    );
  }
}
