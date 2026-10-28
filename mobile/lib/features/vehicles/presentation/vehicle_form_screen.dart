import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/vehicle.dart';
import '../../../data/providers/data_providers.dart';
import '../../../data/vehicle_catalog.dart';
import '../../auth/presentation/widgets/auth_widgets.dart';
import '../providers/vehicle_providers.dart';
import 'option_picker.dart';

/// Add a vehicle ([vehicleId] null) or edit a saved one. Two-wheelers only.
class VehicleFormScreen extends ConsumerWidget {
  const VehicleFormScreen({super.key, this.vehicleId});

  final String? vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editing = vehicleId != null;
    Vehicle? existing;
    if (editing) {
      final vehicles = ref.watch(vehiclesProvider);
      if (vehicles.isLoading && !vehicles.hasValue) {
        return Scaffold(
          appBar: AppBar(title: const Text('Edit vehicle')),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      for (final v in vehicles.valueOrNull ?? const <Vehicle>[]) {
        if (v.id == vehicleId) existing = v;
      }
      if (existing == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Edit vehicle')),
          body: const Center(child: Text('This vehicle is no longer saved.')),
        );
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit vehicle' : 'Add vehicle')),
      body: SafeArea(child: _VehicleForm(existing: existing)),
    );
  }
}

class _VehicleForm extends ConsumerStatefulWidget {
  const _VehicleForm({this.existing});

  final Vehicle? existing;

  @override
  ConsumerState<_VehicleForm> createState() => _VehicleFormState();
}

class _VehicleFormState extends ConsumerState<_VehicleForm> {
  final _formKey = GlobalKey<FormState>();
  late VehicleType _type = widget.existing?.type ?? VehicleType.scooter;
  late final _registration =
      TextEditingController(text: widget.existing?.registrationPretty ?? '');
  late final _make = TextEditingController(text: widget.existing?.make ?? '');
  late final _model = TextEditingController(text: widget.existing?.model ?? '');
  late final _nickname =
      TextEditingController(text: widget.existing?.nickname ?? '');
  bool _busy = false;
  String? _error;

  // Typing by hand instead of picking from the list. A saved vehicle whose
  // make or model is not in the list opens in manual mode.
  late bool _makeManual = _initialMakeManual();
  late bool _modelManual = _initialModelManual();

  bool _initialMakeManual() {
    final v = widget.existing;
    return v != null && knownMake(v.make) == null;
  }

  bool _initialModelManual() {
    final v = widget.existing;
    if (v == null) return false;
    final make = knownMake(v.make);
    return make == null || !vehicleModels(make, v.type).contains(v.model);
  }

  String? get _listedMake => _makeManual ? null : knownMake(_make.text);

  void _pickMake(PickResult result) {
    setState(() {
      if (result.manual) {
        _makeManual = true;
        _modelManual = true;
        _make.clear();
        _model.clear();
        return;
      }
      _make.text = result.value!;
      _makeManual = false;
      // Keep the model only when it still belongs to this make.
      if (!vehicleModels(result.value!, _type).contains(_model.text)) {
        _model.clear();
      }
      _modelManual = false;
    });
  }

  void _pickModel(PickResult result) {
    setState(() {
      if (result.manual) {
        _modelManual = true;
        _model.clear();
      } else {
        _model.text = result.value!;
        _modelManual = false;
      }
    });
  }

  void _changeType(VehicleType type) {
    setState(() {
      _type = type;
      final make = _listedMake;
      if (make != null &&
          !_modelManual &&
          !vehicleModels(make, type).contains(_model.text)) {
        _model.clear();
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_registration, _make, _model, _nickname]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(vehicleRepositoryProvider);
    final registration = normalizeRegistration(_registration.text)!;
    final make = _make.text.trim();
    final model = _model.text.trim();
    try {
      final Vehicle saved;
      if (widget.existing == null) {
        saved = await repo.add(
          type: _type,
          registration: registration,
          make: make,
          model: model,
          nickname: _nickname.text,
        );
        // A newly added vehicle becomes the one to service.
        await ref.read(selectedVehicleIdProvider.notifier).select(saved.id);
      } else {
        saved = await repo.update(
          widget.existing!.id,
          type: _type,
          registration: registration,
          make: make,
          model: model,
          nickname: _nickname.text,
        );
      }
      ref.invalidate(vehiclesProvider);
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    Widget typeChip(VehicleType type, String label) {
      final selected = _type == type;
      return ChoiceChip(
        key: ValueKey('type-${type.name}'),
        selected: selected,
        showCheckmark: false,
        avatar: Icon(
          selected ? Icons.check_circle : Icons.circle_outlined,
          size: 20,
          color: selected ? scheme.onPrimary : scheme.outline,
        ),
        label: Text(label),
        onSelected: _busy ? null : (_) => _changeType(type),
      );
    }

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Text(
            'The registration number should match your RC document.',
            style: textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (_error != null) MessageBanner(message: _error!),
          Text('Select vehicle type', style: textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: [
              typeChip(VehicleType.scooter, 'Scooter'),
              typeChip(VehicleType.bike, 'Bike'),
            ],
          ),
          const SizedBox(height: 4),
          Text('Two-wheelers only.', style: textTheme.bodySmall),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('vehicle-registration'),
            controller: _registration,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            validator: (value) => normalizeRegistration(value ?? '') == null
                ? 'Enter a valid registration number, e.g. MH12 AB 1234'
                : null,
            decoration: InputDecoration(
              labelText: 'Registration number',
              hintText: 'AB 12 CD 3456',
              prefixIcon: Container(
                width: 56,
                margin: const EdgeInsets.only(right: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(12),
                  ),
                ),
                child: Text('IND',
                    style: textTheme.labelLarge
                        ?.copyWith(color: scheme.onPrimary)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_makeManual)
            TextFormField(
              key: const ValueKey('vehicle-make'),
              controller: _make,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: 40,
              validator: (v) {
                final t = (v ?? '').trim();
                return t.length < 2 ? 'Enter the make, e.g. Honda' : null;
              },
              decoration: InputDecoration(
                labelText: 'Vehicle make',
                suffixIcon: TextButton(
                  key: const ValueKey('make-use-list'),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _makeManual = false;
                            _modelManual = false;
                            _make.clear();
                            _model.clear();
                          }),
                  child: const Text('Pick from list'),
                ),
              ),
            )
          else
            OptionPickerField(
              key: const ValueKey('vehicle-make'),
              controller: _make,
              label: 'Vehicle make',
              sheetTitle: 'Select vehicle make',
              options: vehicleMakes(),
              manualLabel: "Can't find vehicle make? Enter manually",
              enabled: !_busy,
              onPicked: _pickMake,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Select the vehicle make' : null,
            ),
          const SizedBox(height: 16),
          if (_modelManual)
            TextFormField(
              key: const ValueKey('vehicle-model'),
              controller: _model,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: 40,
              validator: (v) => (v ?? '').trim().isEmpty
                  ? 'Enter the model, e.g. Activa'
                  : null,
              decoration: InputDecoration(
                labelText: 'Vehicle model',
                suffixIcon: _listedMake == null
                    ? null
                    : TextButton(
                        key: const ValueKey('model-use-list'),
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _modelManual = false;
                                  _model.clear();
                                }),
                        child: const Text('Pick from list'),
                      ),
              ),
            )
          else
            OptionPickerField(
              key: const ValueKey('vehicle-model'),
              controller: _model,
              label: 'Vehicle model',
              sheetTitle: 'Select vehicle model',
              options: vehicleModels(_listedMake ?? '', _type),
              manualLabel: "Can't find model? Enter manually",
              enabled: !_busy && _listedMake != null,
              helper: _listedMake == null ? 'Select the make first' : null,
              onPicked: _pickModel,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Select the vehicle model' : null,
            ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('vehicle-nickname'),
            controller: _nickname,
            enabled: !_busy,
            textInputAction: TextInputAction.done,
            maxLength: 30,
            onFieldSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              labelText: 'Nickname (optional)',
              hintText: 'My daily ride',
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(Icons.shield_outlined, color: scheme.secondary),
              title: Text(
                'Your vehicle details are used only to service your bookings.',
                style: textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 16),
          BusyButton(
            label: widget.existing == null ? 'Confirm vehicle' : 'Save changes',
            busy: _busy,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
