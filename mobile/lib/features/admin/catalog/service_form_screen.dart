import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/enums.dart';
import '../../../data/providers/data_providers.dart';
import '../providers/admin_providers.dart';

/// Create (serviceId == null) or edit a service.
class ServiceFormScreen extends ConsumerWidget {
  const ServiceFormScreen({super.key, this.serviceId});

  final String? serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = serviceId;
    if (id == null) {
      return const _ServiceForm();
    }
    final value = ref.watch(adminServiceProvider(id));
    return value.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Edit service')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Edit service')),
        body: ErrorView(
          message: errorMessage(error),
          onRetry: () => ref.invalidate(adminServiceProvider(id)),
        ),
      ),
      data: (service) => _ServiceForm(existing: service),
    );
  }
}

class _ServiceForm extends ConsumerStatefulWidget {
  const _ServiceForm({this.existing});

  final GarageService? existing;

  @override
  ConsumerState<_ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends ConsumerState<_ServiceForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _description;
  late final TextEditingController _order;
  late VehicleType _vehicle;
  late bool _active;
  bool _busy = false;
  String? _error;

  GarageService? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final s = _existing;
    _name = TextEditingController(text: s?.name ?? '');
    _category = TextEditingController(text: s?.category ?? 'General');
    _description = TextEditingController(text: s?.description ?? '');
    _order = TextEditingController(text: (s?.displayOrder ?? 0).toString());
    _vehicle = s?.vehicleType ?? VehicleType.scooter;
    _active = s?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _description.dispose();
    _order.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(catalogRepositoryProvider);
    final name = Validators.normalizeName(_name.text);
    final category = Validators.normalizeName(_category.text);
    final description =
        _description.text.trim().isEmpty ? null : _description.text.trim();
    final order = int.tryParse(_order.text.trim()) ?? 0;
    try {
      final existing = _existing;
      if (existing == null) {
        final created = await repo.createService(
          name: name,
          vehicleType: _vehicle,
          category: category,
          description: description,
          displayOrder: order,
          isActive: _active,
        );
        refreshCatalog(ref);
        if (mounted) {
          context.pushReplacement(AppRoutes.adminService(created.id));
        }
      } else {
        final changes = <String, dynamic>{
          if (name != existing.name) 'name': name,
          if (category != existing.category) 'category': category,
          if (description != existing.description) 'description': description,
          if (order != existing.displayOrder) 'display_order': order,
          if (_active != existing.isActive) 'is_active': _active,
        };
        if (changes.isNotEmpty) {
          await repo.updateService(existing.id, changes);
          refreshCatalog(ref);
        }
        if (mounted) {
          context.pop();
        }
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
    final editing = _existing != null;
    return FormPage(
      title: editing ? 'Edit service' : 'New service',
      formKey: _formKey,
      busy: _busy,
      error: _error,
      onSave: _save,
      children: [
        TextFormField(
          controller: _name,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          validator: (v) =>
              Validators.requiredText(v, label: 'service name', max: 80),
          decoration: const InputDecoration(labelText: 'Service name'),
        ),
        fieldGap,
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Vehicle type',
            helperText: editing ? 'Cannot be changed after creation' : null,
            border: InputBorder.none,
          ),
          child: SegmentedButton<VehicleType>(
            showSelectedIcon: false,
            segments: [
              for (final type in VehicleType.values)
                ButtonSegment(value: type, label: Text(vehicleLabel(type))),
            ],
            selected: {_vehicle},
            onSelectionChanged: editing || _busy
                ? null
                : (selection) => setState(() => _vehicle = selection.first),
          ),
        ),
        fieldGap,
        TextFormField(
          controller: _category,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          validator: (v) =>
              Validators.requiredText(v, label: 'category', max: 60),
          decoration: const InputDecoration(
            labelText: 'Category',
            helperText: 'Groups similar services, e.g. Maintenance or Washing',
          ),
        ),
        fieldGap,
        TextFormField(
          controller: _description,
          enabled: !_busy,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          validator: (v) =>
              Validators.optionalText(v, label: 'description', max: 1000),
          decoration: const InputDecoration(labelText: 'Description (optional)'),
        ),
        fieldGap,
        TextFormField(
          controller: _order,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          validator: Validators.displayOrder,
          decoration: const InputDecoration(
            labelText: 'Display order',
            helperText: 'Lower numbers are listed first',
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Visible to customers'),
          value: _active,
          onChanged: _busy ? null : (v) => setState(() => _active = v),
        ),
      ],
    );
  }
}
