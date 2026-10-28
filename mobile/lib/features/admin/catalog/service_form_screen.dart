import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/media/image_picker_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/enums.dart';
import '../../../data/providers/data_providers.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/vehicle_catalog.dart';
import '../../auth/presentation/widgets/auth_widgets.dart' show MessageBanner;
import '../../catalog/presentation/service_detail_screen.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../providers/admin_providers.dart';
import 'package_fields.dart';
import 'service_image_field.dart';

const int _maxPartImages = 8;

/// Create (serviceId == null) or edit a service: details, price, what is
/// included, pictures (gallery or camera), compatibility and availability, with
/// a preview of what customers will see before anything is published.
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
  late final TextEditingController _short;
  late final TextEditingController _description;
  late final TextEditingController _order;
  late final TextEditingController _badge;
  late final PackageDraft _pkg;
  late final CatalogRepository _repo;
  late VehicleType _vehicle;
  late bool _active;
  String? _categoryId;
  String? _banner;
  String? _thumbnail;
  late List<String> _parts;
  late Set<String> _makes;
  late Set<String> _models;

  /// Pictures uploaded in this session. Any not saved are discarded on exit.
  final Set<String> _uploaded = {};
  String? _uploading;
  bool _saved = false;
  bool _busy = false;
  String? _error;

  GarageService? get _existing => widget.existing;

  /// The package edited inline: the service's only one, or a new one.
  ServicePackage? get _package {
    final packages = _existing?.packages ?? const <ServicePackage>[];
    return packages.length == 1 ? packages.first : null;
  }

  bool get _hasPackageSection =>
      _existing == null || (_existing!.packages.length <= 1);

  @override
  void initState() {
    super.initState();
    _repo = ref.read(catalogRepositoryProvider);
    final s = _existing;
    _name = TextEditingController(text: s?.name ?? '');
    _short = TextEditingController(text: s?.shortDescription ?? '');
    _description = TextEditingController(text: s?.description ?? '');
    _order = TextEditingController(text: (s?.displayOrder ?? 0).toString());
    _badge = TextEditingController(text: s?.badge ?? '');
    _pkg = PackageDraft(_package);
    _vehicle = s?.vehicleType ?? VehicleType.scooter;
    _active = s?.isActive ?? true;
    _categoryId = s?.categoryId;
    _banner = s?.bannerUrl;
    _thumbnail = s?.thumbnailUrl ?? s?.imageUrl;
    _parts = [...?s?.partImageUrls];
    _makes = {...?s?.supportedMakes};
    _models = {...?s?.supportedModels};
  }

  @override
  void dispose() {
    if (!_saved) {
      for (final url in _uploaded) {
        _repo.discardImage(url);
      }
    }
    _name.dispose();
    _short.dispose();
    _description.dispose();
    _order.dispose();
    _badge.dispose();
    _pkg.dispose();
    super.dispose();
  }

  // ---- pictures ---------------------------------------------------------------------
  Future<String?> _pickAndUpload(
    ServiceImageKind kind,
    PickSource source,
  ) async {
    setState(() => _error = null);
    final PickedImage? picked;
    try {
      picked = await ref.read(imagePickerServiceProvider).pick(source);
    } catch (_) {
      if (mounted) {
        setState(() => _error = source == PickSource.camera
            ? 'The camera could not be opened. Check the app has permission.'
            : 'The gallery could not be opened. Check the app has permission.');
      }
      return null;
    }
    if (picked == null || !mounted) return null;
    final problem = checkPicture(picked);
    if (problem != null) {
      setState(() => _error = problem);
      return null;
    }
    setState(() => _uploading = kind.name);
    try {
      final url = await _repo.uploadImage(kind, picked.bytes, picked.contentType!);
      _uploaded.add(url);
      return url;
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
      return null;
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  /// A picture that is no longer used: one uploaded in this session goes now.
  void _drop(String? url) {
    if (url != null && _uploaded.remove(url)) _repo.discardImage(url);
  }

  Future<void> _setBanner(PickSource source) async {
    final url = await _pickAndUpload(ServiceImageKind.banner, source);
    if (url == null) return;
    _drop(_banner);
    setState(() => _banner = url);
  }

  Future<void> _setThumbnail(PickSource source) async {
    final url = await _pickAndUpload(ServiceImageKind.thumbnail, source);
    if (url == null) return;
    _drop(_thumbnail);
    setState(() => _thumbnail = url);
  }

  Future<void> _addPart(PickSource source) async {
    final url = await _pickAndUpload(ServiceImageKind.part, source);
    if (url == null) return;
    setState(() => _parts = [..._parts, url]);
  }

  // ---- preview ---------------------------------------------------------------------
  GarageService _draftService() {
    final category = _selectedCategory();
    final package = ServicePackage(
      id: 'draft',
      serviceId: 'draft',
      name: _existing?.packages.firstOrNull?.name ?? 'Standard',
      price: _pkg.priceValue ?? 0,
      originalPrice: _pkg.originalValue,
      advancePercent: _pkg.advanceValue,
      labourCharge: _pkg.labourValue,
      repeatIntervalDays: _pkg.repeatValue,
      warrantyDays: _pkg.warrantyValue,
      estimatedDurationMinutes: _pkg.durationValue,
      inclusions: PackageDraft.lines(_pkg.inclusions),
      includedParts: PackageDraft.lines(_pkg.parts),
      exclusions: PackageDraft.lines(_pkg.exclusions),
      partsPolicy: _pkg.partsPolicy,
      partsNote: _pkg.noteValue,
      description: _pkg.descriptionValue,
      displayOrder: 0,
      isActive: true,
      extraCharges: const [],
    );
    String? text(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    return GarageService(
      id: _existing?.id ?? 'draft',
      name: text(_name) ?? 'New service',
      vehicleType: _vehicle,
      category: category?.name ?? 'General',
      description: text(_description),
      shortDescription: text(_short),
      systemKey: _existing?.systemKey,
      catalogTab: category?.tab ?? CatalogTab.package,
      imageUrl: null,
      bannerUrl: _banner,
      thumbnailUrl: _thumbnail,
      partImageUrls: _parts,
      supportedMakes: _makes.toList(),
      supportedModels: _models.toList(),
      badge: text(_badge),
      displayOrder: 0,
      isActive: _active,
      packages: _hasPackageSection
          ? [package]
          : (_existing?.packages ?? const []),
      extraCharges: _existing?.extraCharges ?? const [],
    );
  }

  ServiceCategory? _selectedCategory() {
    final all = ref.read(adminCategoriesProvider).valueOrNull ?? const [];
    for (final c in all) {
      if (c.id == _categoryId) return c;
    }
    return null;
  }

  void _openPreview() {
    final service = _draftService();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Preview as customer')),
          body: SafeArea(
            child: ServiceDetailView(service: service, preview: true),
          ),
        ),
      ),
    );
  }

  // ---- save ------------------------------------------------------------------------
  String? _orNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (_busy || _uploading != null) return;
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) {
      setState(() => _error = 'Choose a category.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final name = Validators.normalizeName(_name.text);
    final short = _orNull(_short);
    final description = _orNull(_description);
    final badge = _orNull(_badge);
    final order = int.tryParse(_order.text.trim()) ?? 0;
    final category = _selectedCategory();
    final makes = _makes.toList()..sort();
    final models = _models.toList()..sort();
    try {
      final existing = _existing;
      if (existing == null) {
        await _create(
          name: name,
          short: short,
          description: description,
          badge: badge,
          order: order,
          category: category,
          makes: makes,
          models: models,
        );
      } else {
        await _update(
          existing,
          name: name,
          short: short,
          description: description,
          badge: badge,
          order: order,
          makes: makes,
          models: models,
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(error);
      });
    }
  }

  Future<void> _create({
    required String name,
    required String? short,
    required String? description,
    required String? badge,
    required int order,
    required ServiceCategory? category,
    required List<String> makes,
    required List<String> models,
  }) async {
    // Created switched off, completed with its package, then switched on: a
    // customer never sees a service without a price.
    final created = await _repo.createService(
      name: name,
      vehicleType: _vehicle,
      category: category?.name ?? 'General',
      categoryId: _categoryId,
      description: description,
      shortDescription: short,
      bannerUrl: _banner,
      thumbnailUrl: _thumbnail,
      partImageUrls: _parts,
      supportedMakes: makes,
      supportedModels: models,
      badge: badge,
      displayOrder: order,
      isActive: false,
    );
    try {
      final d = _pkg;
      await _repo.createPackage(
        created.id,
        name: 'Standard',
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
      );
      if (_active) {
        await _repo.updateService(created.id, {'is_active': true});
      }
    } catch (_) {
      // Nothing half-made is left behind (this also removes its pictures).
      try {
        await _repo.deleteService(created.id);
        _uploaded.clear();
      } catch (_) {}
      rethrow;
    }
    _finish(replaceWith: created.id);
  }

  Future<void> _update(
    GarageService existing, {
    required String name,
    required String? short,
    required String? description,
    required String? badge,
    required int order,
    required List<String> makes,
    required List<String> models,
  }) async {
    bool same(List<String> a, List<String> b) => a.join('\n') == b.join('\n');
    final oldMakes = [...existing.supportedMakes]..sort();
    final oldModels = [...existing.supportedModels]..sort();
    final thumbWas = existing.thumbnailUrl ?? existing.imageUrl;
    final changes = <String, dynamic>{
      if (name != existing.name) 'name': name,
      if (short != existing.shortDescription) 'short_description': short,
      if (description != existing.description) 'description': description,
      if (_categoryId != existing.categoryId) 'category_id': _categoryId,
      if (badge != existing.badge) 'badge': badge,
      if (_banner != existing.bannerUrl) 'banner_url': _banner,
      if (_thumbnail != thumbWas) 'thumbnail_url': _thumbnail,
      if (_thumbnail == null && existing.imageUrl != null) 'image_url': null,
      if (!same(_parts, existing.partImageUrls)) 'part_image_urls': _parts,
      if (!same(makes, oldMakes)) 'supported_makes': makes,
      if (!same(models, oldModels)) 'supported_models': models,
      if (order != existing.displayOrder) 'display_order': order,
      if (_active != existing.isActive) 'is_active': _active,
    };
    if (changes.isNotEmpty) {
      await _repo.updateService(existing.id, changes);
    }
    final package = _package;
    if (package != null) {
      final pkgChanges = _pkg.changes(package, withName: false);
      if (pkgChanges.isNotEmpty) {
        await _repo.updatePackage(package.id, pkgChanges);
      }
    } else if (existing.packages.isEmpty) {
      final d = _pkg;
      await _repo.createPackage(
        existing.id,
        name: 'Standard',
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
      );
    }
    _finish();
  }

  void _finish({String? replaceWith}) {
    final stillUsed = <String>{
      if (_banner != null) _banner!,
      if (_thumbnail != null) _thumbnail!,
      ..._parts,
    };
    for (final url in _uploaded.difference(stillUsed)) {
      _repo.discardImage(url);
    }
    _saved = true;
    refreshCatalog(ref);
    if (!mounted) return;
    if (replaceWith != null) {
      context.pushReplacement(AppRoutes.adminService(replaceWith));
    } else {
      context.pop();
    }
  }

  // ---- compatibility ----------------------------------------------------------------
  Future<void> _pickModels() async {
    final makes = _makes.isEmpty ? vehicleMakes() : (_makes.toList()..sort());
    final options = <String>{
      for (final m in makes) ...vehicleModels(m, _vehicle),
      ..._models,
    }.toList()
      ..sort();
    final chosen = {..._models};
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            builder: (context, controller) => Column(
              children: [
                ListTile(
                  title: const Text('Supported models'),
                  subtitle: const Text('None ticked = every model'),
                  trailing: FilledButton(
                    key: const ValueKey('models-done'),
                    onPressed: () => Navigator.of(context).pop(chosen),
                    child: const Text('Done'),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: controller,
                    children: [
                      for (final model in options)
                        CheckboxListTile(
                          key: ValueKey('model-$model'),
                          title: Text(model),
                          value: chosen.contains(model),
                          onChanged: (on) => setSheet(() {
                            on == true ? chosen.add(model) : chosen.remove(model);
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) setState(() => _models = result);
  }

  // ---- build -----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final editing = _existing != null;
    final categories = ref.watch(adminCategoriesProvider);
    final textTheme = Theme.of(context).textTheme;
    final locked = _busy;
    return FormPage(
      title: editing ? 'Edit service' : 'New service',
      formKey: _formKey,
      busy: _busy,
      error: _error,
      onSave: _save,
      saveLabel: editing ? 'Save changes' : (_active ? 'Publish service' : 'Save service'),
      actions: [
        TextButton.icon(
          key: const ValueKey('service-preview'),
          onPressed: _openPreview,
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Preview'),
        ),
      ],
      children: [
        TextFormField(
          controller: _name,
          enabled: !locked,
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
            onSelectionChanged: editing || locked
                ? null
                : (selection) => setState(() {
                      _vehicle = selection.first;
                      _models.clear();
                    }),
          ),
        ),
        fieldGap,
        categories.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => MessageBanner(message: errorMessage(error)),
          data: (all) {
            final choices = [
              for (final c in all)
                if (c.isActive || c.id == _categoryId) c,
            ];
            _categoryId ??= _defaultCategory(choices);
            return DropdownButtonFormField<String>(
              key: const ValueKey('service-category'),
              value: choices.any((c) => c.id == _categoryId) ? _categoryId : null,
              isExpanded: true,
              items: [
                for (final c in choices)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(
                      c.isActive ? c.name : '${c.name} (off)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: locked ? null : (v) => setState(() => _categoryId = v),
              validator: (v) => v == null ? 'Choose a category' : null,
              decoration: const InputDecoration(
                labelText: 'Category',
                helperText: 'Decides where customers find it',
              ),
            );
          },
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('service-badge'),
          controller: _badge,
          enabled: !locked,
          maxLength: 24,
          decoration: const InputDecoration(
            labelText: 'Offer label (optional)',
            helperText: 'e.g. Trending, 20% OFF, Best value',
          ),
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('service-short'),
          controller: _short,
          enabled: !locked,
          maxLength: 140,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Short description (optional)',
            helperText: 'One line shown on the list card',
          ),
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('service-description'),
          controller: _description,
          enabled: !locked,
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          validator: (v) =>
              Validators.optionalText(v, label: 'description', max: 1000),
          decoration: const InputDecoration(
            labelText: 'Full description (optional)',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 24),
        Text('Pictures', style: textTheme.titleMedium),
        const SizedBox(height: 12),
        ServiceImageSlot(
          idKey: 'banner',
          title: 'Banner',
          helper: 'Wide picture at the top of the details page (16:9).',
          aspectRatio: 16 / 9,
          url: _banner,
          uploading: _uploading == ServiceImageKind.banner.name,
          enabled: !locked,
          onPick: _setBanner,
          onRemove: () {
            _drop(_banner);
            setState(() => _banner = null);
          },
        ),
        const SizedBox(height: 16),
        ServiceImageSlot(
          idKey: 'thumbnail',
          title: 'Thumbnail',
          helper: 'Square picture for lists (1:1).',
          aspectRatio: 1,
          url: _thumbnail,
          uploading: _uploading == ServiceImageKind.thumbnail.name,
          enabled: !locked,
          onPick: _setThumbnail,
          onRemove: () {
            _drop(_thumbnail);
            setState(() => _thumbnail = null);
          },
        ),
        const SizedBox(height: 16),
        PartImagesField(
          urls: _parts,
          max: _maxPartImages,
          uploading: _uploading == ServiceImageKind.part.name,
          enabled: !locked,
          onPick: _addPart,
          onRemove: (i) {
            _drop(_parts[i]);
            setState(() => _parts = [..._parts]..removeAt(i));
          },
        ),
        const SizedBox(height: 24),
        Text('Price and what is included', style: textTheme.titleMedium),
        const SizedBox(height: 12),
        if (_hasPackageSection)
          PackageFields(
            draft: _pkg,
            busy: locked,
            showName: false,
            showOrderAndActive: false,
          )
        else
          Text(
            'This service has several packages. Edit their prices and '
            'inclusions from the service page.',
            key: const ValueKey('multi-package-note'),
            style: textTheme.bodyMedium,
          ),
        const SizedBox(height: 24),
        Text('Works with', style: textTheme.titleMedium),
        Text(
          'Leave empty if every ${vehicleLabel(_vehicle).toLowerCase()} can '
          'have this service.',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final make in {...vehicleMakes(), ..._makes}.toList()..sort())
              FilterChip(
                key: ValueKey('make-$make'),
                label: Text(make),
                selected: _makes.contains(make),
                onSelected: locked
                    ? null
                    : (on) => setState(() {
                          on ? _makes.add(make) : _makes.remove(make);
                        }),
              ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('pick-models'),
          onPressed: locked ? null : _pickModels,
          icon: const Icon(Icons.two_wheeler),
          label: Text(
            _models.isEmpty
                ? 'Choose models (all models)'
                : 'Models: ${_models.length} chosen',
          ),
        ),
        const SizedBox(height: 24),
        Text('Availability', style: textTheme.titleMedium),
        fieldGap,
        TextFormField(
          controller: _order,
          enabled: !locked,
          keyboardType: TextInputType.number,
          validator: Validators.displayOrder,
          decoration: const InputDecoration(
            labelText: 'Display order',
            helperText: 'Lower numbers are listed first',
          ),
        ),
        SwitchListTile(
          key: const ValueKey('service-active'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Visible to customers'),
          subtitle: const Text('Switch off to hide it without deleting'),
          value: _active,
          onChanged: locked ? null : (v) => setState(() => _active = v),
        ),
      ],
    );
  }

  /// A new service starts in the category of its first tab: "Service Packages".
  String? _defaultCategory(List<ServiceCategory> choices) {
    for (final c in choices) {
      if (c.systemKey == 'tab_package') return c.id;
    }
    return choices.firstOrNull?.id;
  }
}
