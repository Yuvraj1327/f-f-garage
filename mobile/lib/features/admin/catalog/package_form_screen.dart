import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/enums.dart';
import '../../../data/providers/data_providers.dart';
import '../providers/admin_providers.dart';

/// Create (packageId == "new") or edit a package of a service.
class PackageFormScreen extends ConsumerWidget {
  const PackageFormScreen({
    super.key,
    required this.serviceId,
    required this.packageId,
  });

  final String serviceId;
  final String packageId;

  bool get _isNew => packageId == AppRoutes.newItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = _isNew ? 'New package' : 'Edit package';
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
          return _PackageForm(service: service);
        }
        final matches = service.packages.where((p) => p.id == packageId);
        if (matches.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: const EmptyView(message: 'This package no longer exists.'),
          );
        }
        return _PackageForm(service: service, existing: matches.first);
      },
    );
  }
}

class _PackageForm extends ConsumerStatefulWidget {
  const _PackageForm({required this.service, this.existing});

  final GarageService service;
  final ServicePackage? existing;

  @override
  ConsumerState<_PackageForm> createState() => _PackageFormState();
}

class _PackageFormState extends ConsumerState<_PackageForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _duration;
  late final TextEditingController _description;
  late final TextEditingController _inclusions;
  late final TextEditingController _order;
  late final TextEditingController _original;
  late final TextEditingController _warranty;
  late final TextEditingController _exclusions;
  late final TextEditingController _partsNote;
  late PartsPolicy _partsPolicy;
  late bool _active;
  bool _busy = false;
  String? _error;

  ServicePackage? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final p = _existing;
    _name = TextEditingController(text: p?.name ?? '');
    _price = TextEditingController(text: p == null ? '' : _plain(p.price));
    _duration = TextEditingController(
      text: p?.estimatedDurationMinutes?.toString() ?? '',
    );
    _description = TextEditingController(text: p?.description ?? '');
    _inclusions = TextEditingController(text: p?.inclusions.join('\n') ?? '');
    _order = TextEditingController(text: (p?.displayOrder ?? 0).toString());
    _original = TextEditingController(
      text: p?.originalPrice == null ? '' : _plain(p!.originalPrice!),
    );
    _warranty = TextEditingController(text: p?.warrantyDays?.toString() ?? '');
    _exclusions = TextEditingController(text: p?.exclusions.join('\n') ?? '');
    _partsNote = TextEditingController(text: p?.partsNote ?? '');
    _partsPolicy = p?.partsPolicy ?? PartsPolicy.serviceOnly;
    _active = p?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _duration.dispose();
    _description.dispose();
    _inclusions.dispose();
    _order.dispose();
    _original.dispose();
    _warranty.dispose();
    _exclusions.dispose();
    _partsNote.dispose();
    super.dispose();
  }

  /// 499.0 -> "499", 499.5 -> "499.50" (what a person would type).
  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  /// One inclusion per line; blanks and repeats are dropped (the server does the
  /// same, so what is saved matches what the admin sees after saving).
  List<String> _parseInclusions() {
    final seen = <String>{};
    final result = <String>[];
    for (final line in _inclusions.text.split('\n')) {
      final text = Validators.normalizeName(line);
      if (text.isNotEmpty && seen.add(text.toLowerCase())) {
        result.add(text);
      }
    }
    return result;
  }

  List<String> _parseLines(TextEditingController controller) {
    final seen = <String>{};
    final result = <String>[];
    for (final line in controller.text.split('\n')) {
      final text = Validators.normalizeName(line);
      if (text.isNotEmpty && seen.add(text.toLowerCase())) {
        result.add(text);
      }
    }
    return result;
  }

  String? _validateInclusions(String? _) {
    final items = _parseInclusions();
    if (items.length > 30) {
      return 'At most 30 inclusions';
    }
    if (items.any((i) => i.length > 120)) {
      return 'Each inclusion must be at most 120 characters';
    }
    return null;
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
    final price = Validators.parseAmount(_price.text)!;
    final duration = int.tryParse(_duration.text.trim());
    final description =
        _description.text.trim().isEmpty ? null : _description.text.trim();
    final inclusions = _parseInclusions();
    final order = int.tryParse(_order.text.trim()) ?? 0;
    final original = _original.text.trim().isEmpty
        ? null
        : Validators.parseAmount(_original.text);
    final warranty = int.tryParse(_warranty.text.trim());
    final exclusions = _parseLines(_exclusions);
    final note = _partsNote.text.trim().isEmpty ? null : _partsNote.text.trim();
    try {
      final existing = _existing;
      if (existing == null) {
        await repo.createPackage(
          widget.service.id,
          name: name,
          price: price,
          originalPrice: original,
          warrantyDays: warranty,
          exclusions: exclusions,
          partsPolicy: _partsPolicy,
          partsNote: note,
          description: description,
          inclusions: inclusions,
          estimatedDurationMinutes: duration,
          displayOrder: order,
          isActive: _active,
        );
      } else {
        final changes = <String, dynamic>{
          if (name != existing.name) 'name': name,
          if (price != existing.price) 'price': price.toStringAsFixed(2),
          if (original != existing.originalPrice)
            'original_price': original?.toStringAsFixed(2),
          if (warranty != existing.warrantyDays) 'warranty_days': warranty,
          if (exclusions.join('\n') != existing.exclusions.join('\n'))
            'exclusions': exclusions,
          if (_partsPolicy != existing.partsPolicy)
            'parts_policy': _partsPolicy.apiValue,
          if (note != existing.partsNote) 'parts_note': note,
          if (description != existing.description) 'description': description,
          if (inclusions.join('\n') != existing.inclusions.join('\n'))
            'inclusions': inclusions,
          if (duration != existing.estimatedDurationMinutes)
            'estimated_duration_minutes': duration,
          if (order != existing.displayOrder) 'display_order': order,
          if (_active != existing.isActive) 'is_active': _active,
        };
        if (changes.isNotEmpty) {
          await repo.updatePackage(existing.id, changes);
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

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: _existing == null ? 'New package' : 'Edit package',
      formKey: _formKey,
      busy: _busy,
      error: _error,
      onSave: _save,
      children: [
        Text(
          widget.service.name,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        fieldGap,
        TextFormField(
          controller: _name,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          validator: (v) =>
              Validators.requiredText(v, label: 'package name', max: 80),
          decoration: const InputDecoration(labelText: 'Package name'),
        ),
        fieldGap,
        TextFormField(
          controller: _price,
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          validator: Validators.price,
          decoration: const InputDecoration(
            labelText: 'Price',
            prefixText: '₹ ',
          ),
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('package-original'),
          controller: _original,
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) {
            if ((v ?? '').trim().isEmpty) return null;
            final original = Validators.parseAmount(v!);
            final price = Validators.parseAmount(_price.text);
            if (original == null) return 'Enter a valid amount';
            if (price != null && original < price) {
              return 'Cannot be lower than the price';
            }
            return null;
          },
          decoration: const InputDecoration(
            labelText: 'Original price (optional)',
            helperText: 'Shown crossed out next to the price',
            prefixText: '₹ ',
          ),
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('package-warranty'),
          controller: _warranty,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          validator: (v) {
            final text = (v ?? '').trim();
            if (text.isEmpty) return null;
            final days = int.tryParse(text);
            return days == null || days < 1 || days > 3650
                ? 'Enter 1 to 3650 days'
                : null;
          },
          decoration: const InputDecoration(
            labelText: 'Warranty (optional)',
            suffixText: 'days',
          ),
        ),
        fieldGap,
        TextFormField(
          controller: _duration,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          validator: Validators.optionalDuration,
          decoration: const InputDecoration(
            labelText: 'Estimated duration (optional)',
            suffixText: 'minutes',
          ),
        ),
        fieldGap,
        TextFormField(
          controller: _description,
          enabled: !_busy,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          validator: (v) =>
              Validators.optionalText(v, label: 'description', max: 1000),
          decoration: const InputDecoration(labelText: 'Description (optional)'),
        ),
        fieldGap,
        TextFormField(
          controller: _inclusions,
          enabled: !_busy,
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          validator: _validateInclusions,
          decoration: const InputDecoration(
            labelText: 'What is included (one per line)',
            alignLabelWithHint: true,
          ),
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('package-exclusions'),
          controller: _exclusions,
          enabled: !_busy,
          minLines: 2,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What is not included (one per line)',
            alignLabelWithHint: true,
          ),
        ),
        fieldGap,
        DropdownButtonFormField<PartsPolicy>(
          key: const ValueKey('package-parts-policy'),
          value: _partsPolicy,
          items: const [
            DropdownMenuItem(
              value: PartsPolicy.serviceOnly,
              child: Text('Labour only (parts extra)'),
            ),
            DropdownMenuItem(
              value: PartsPolicy.partsIncluded,
              child: Text('Parts included'),
            ),
            DropdownMenuItem(
              value: PartsPolicy.partsExtra,
              child: Text('Parts charged extra'),
            ),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(
                    () => _partsPolicy = value ?? PartsPolicy.serviceOnly,
                  ),
          decoration: const InputDecoration(labelText: 'Spare parts'),
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('package-parts-note'),
          controller: _partsNote,
          enabled: !_busy,
          maxLength: 300,
          decoration: const InputDecoration(
            labelText: 'Parts note (optional)',
            helperText: 'Shown to the customer instead of the default text',
          ),
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
