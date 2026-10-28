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
import 'package_fields.dart';

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
  late final PackageDraft _draft = PackageDraft(widget.existing);
  bool _busy = false;
  String? _error;

  ServicePackage? get _existing => widget.existing;

  @override
  void dispose() {
    _draft.dispose();
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
    final d = _draft;
    final order = int.tryParse(d.order.text.trim()) ?? 0;
    try {
      final existing = _existing;
      if (existing == null) {
        await repo.createPackage(
          widget.service.id,
          name: Validators.normalizeName(d.name.text),
          price: d.priceValue!,
          originalPrice: d.originalValue,
          advancePercent: d.advanceValue,
          labourCharge: d.labourValue,
          repeatIntervalDays: d.repeatValue,
          warrantyDays: d.warrantyValue,
          exclusions: PackageDraft.lines(d.exclusions),
          includedParts: PackageDraft.lines(d.parts),
          partsPolicy: d.partsPolicy,
          partsNote: d.noteValue,
          description: d.descriptionValue,
          inclusions: PackageDraft.lines(d.inclusions),
          estimatedDurationMinutes: d.durationValue,
          displayOrder: order,
          isActive: d.active,
        );
      } else {
        final changes = <String, dynamic>{
          ...d.changes(existing),
          if (order != existing.displayOrder) 'display_order': order,
          if (d.active != existing.isActive) 'is_active': d.active,
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
        PackageFields(draft: _draft, busy: _busy),
      ],
    );
  }
}
