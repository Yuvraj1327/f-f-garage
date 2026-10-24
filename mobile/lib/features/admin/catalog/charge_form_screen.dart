import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/enums.dart';
import '../../../data/providers/data_providers.dart';
import '../providers/admin_providers.dart';

/// Create (chargeId == "new") or edit an extra charge. [initialPackageId]
/// pre-selects "applies to" when adding from a package card.
class ChargeFormScreen extends ConsumerWidget {
  const ChargeFormScreen({
    super.key,
    required this.serviceId,
    required this.chargeId,
    this.initialPackageId,
  });

  final String serviceId;
  final String chargeId;
  final String? initialPackageId;

  bool get _isNew => chargeId == AppRoutes.newItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = _isNew ? 'New extra charge' : 'Edit extra charge';
    final value = ref.watch(adminServiceProvider(serviceId));
    return value.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ErrorView(
          message: errorMessage(error),
          onRetry: () => ref.invalidate(adminServiceProvider(serviceId)),
        ),
      ),
      data: (service) {
        if (_isNew) {
          return _ChargeForm(service: service, packageId: initialPackageId);
        }
        final all = [
          ...service.extraCharges,
          for (final p in service.packages) ...p.extraCharges,
        ];
        final matches = all.where((c) => c.id == chargeId);
        if (matches.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: const EmptyView(message: 'This charge no longer exists.'),
          );
        }
        return _ChargeForm(
          service: service,
          existing: matches.first,
          packageId: matches.first.packageId,
        );
      },
    );
  }
}

class _ChargeForm extends ConsumerStatefulWidget {
  const _ChargeForm({required this.service, this.existing, this.packageId});

  final GarageService service;
  final ExtraCharge? existing;
  final String? packageId;

  @override
  ConsumerState<_ChargeForm> createState() => _ChargeFormState();
}

class _ChargeFormState extends ConsumerState<_ChargeForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _description;
  late ExtraChargeType _type;
  late bool _active;
  String? _packageId;
  bool _busy = false;
  String? _error;

  ExtraCharge? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final c = _existing;
    _name = TextEditingController(text: c?.name ?? '');
    final amount = c?.amount;
    _amount = TextEditingController(
      text: amount == null
          ? ''
          : (amount == amount.roundToDouble()
              ? amount.toStringAsFixed(0)
              : amount.toStringAsFixed(2)),
    );
    _description = TextEditingController(text: c?.description ?? '');
    _type = c?.chargeType ?? ExtraChargeType.sparePart;
    _active = c?.isActive ?? true;
    // Only keep a pre-selected package that really belongs to this service.
    final wanted = widget.packageId;
    _packageId = widget.service.packages.any((p) => p.id == wanted) ? wanted : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _description.dispose();
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
    final amount = Validators.parseAmount(_amount.text);
    final description =
        _description.text.trim().isEmpty ? null : _description.text.trim();
    try {
      final existing = _existing;
      if (existing == null) {
        await repo.createCharge(
          widget.service.id,
          name: name,
          chargeType: _type,
          amount: amount,
          description: description,
          packageId: _packageId,
          isActive: _active,
        );
      } else {
        final changes = <String, dynamic>{
          if (name != existing.name) 'name': name,
          if (_type != existing.chargeType) 'charge_type': _type.apiValue,
          if (amount != existing.amount) 'amount': amount?.toStringAsFixed(2),
          if (description != existing.description) 'description': description,
          if (_active != existing.isActive) 'is_active': _active,
        };
        if (changes.isNotEmpty) {
          await repo.updateCharge(existing.id, changes);
        }
      }
      refreshCatalog(ref);
      if (mounted) {
        context.pop();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(error);
      });
    }
  }

  Future<void> _delete() async {
    final existing = _existing;
    if (existing == null || _busy) {
      return;
    }
    final confirmed = await confirmAction(
      context,
      title: 'Delete charge?',
      message: '"${existing.name}" will no longer be offered. '
          'Past bookings are not affected.',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(catalogRepositoryProvider).deleteCharge(existing.id);
      refreshCatalog(ref);
      if (mounted) {
        context.pop();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(error);
      });
    }
  }

  String get _appliesToText {
    final id = _existing?.packageId ?? _packageId;
    if (id == null) {
      return 'All packages';
    }
    final matches = widget.service.packages.where((p) => p.id == id);
    return matches.isEmpty ? 'One package' : matches.first.name;
  }

  @override
  Widget build(BuildContext context) {
    final editing = _existing != null;
    return FormPage(
      title: editing ? 'Edit extra charge' : 'New extra charge',
      formKey: _formKey,
      busy: _busy,
      error: _error,
      onSave: _save,
      actions: [
        if (editing)
          IconButton(
            tooltip: 'Delete charge',
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy ? null : _delete,
          ),
      ],
      children: [
        Text(
          widget.service.name,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        fieldGap,
        DropdownButtonFormField<ExtraChargeType>(
          value: _type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: [
            for (final type in ExtraChargeType.values)
              DropdownMenuItem(value: type, child: Text(chargeTypeLabel(type))),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() => _type = value ?? _type),
        ),
        fieldGap,
        TextFormField(
          controller: _name,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          validator: (v) =>
              Validators.requiredText(v, label: 'charge name', max: 80),
          decoration: const InputDecoration(
            labelText: 'Name',
            helperText: 'e.g. Engine oil 10W-30, Air filter',
          ),
        ),
        fieldGap,
        TextFormField(
          controller: _amount,
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          validator: Validators.optionalAmount,
          decoration: const InputDecoration(
            labelText: 'Amount (optional)',
            prefixText: '₹ ',
            helperText: 'Leave empty if it is charged at actuals on the day',
          ),
        ),
        fieldGap,
        if (editing)
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Applies to',
              helperText: 'Fixed once created. Delete and re-add to change it.',
            ),
            child: Text(_appliesToText),
          )
        else
          DropdownButtonFormField<String?>(
            value: _packageId,
            decoration: const InputDecoration(labelText: 'Applies to'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All packages'),
              ),
              for (final package in widget.service.packages)
                DropdownMenuItem<String?>(
                  value: package.id,
                  child: Text(package.name),
                ),
            ],
            onChanged: _busy ? null : (value) => setState(() => _packageId = value),
          ),
        fieldGap,
        TextFormField(
          controller: _description,
          enabled: !_busy,
          minLines: 2,
          maxLines: 4,
          validator: (v) =>
              Validators.optionalText(v, label: 'description', max: 1000),
          decoration: const InputDecoration(labelText: 'Note (optional)'),
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
