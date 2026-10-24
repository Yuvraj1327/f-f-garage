import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../data/models/catalog.dart';
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
    try {
      final existing = _existing;
      if (existing == null) {
        await repo.createPackage(
          widget.service.id,
          name: name,
          price: price,
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
