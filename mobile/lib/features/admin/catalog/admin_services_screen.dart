import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/widgets/app_nav.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../core/widgets/dialogs.dart';
import '../../catalog/presentation/service_card.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/enums.dart';
import '../../../data/providers/data_providers.dart';
import '../providers/admin_providers.dart';

/// All services (bike and scooter), including inactive ones, drawn with the
/// same cards and categories customers see, plus the management controls.
class AdminServicesScreen extends ConsumerStatefulWidget {
  const AdminServicesScreen({super.key});

  @override
  ConsumerState<AdminServicesScreen> createState() =>
      _AdminServicesScreenState();
}

class _AdminServicesScreenState extends ConsumerState<AdminServicesScreen> {
  VehicleType? _filter;
  String? _categoryId;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(adminServicesProvider(_filter));
    final categories = ref.watch(adminCategoriesProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Services'),
        actions: [
          IconButton(
            key: const ValueKey('open-categories'),
            tooltip: 'Categories',
            icon: const Icon(Icons.category_outlined),
            onPressed: () => context.push(AppRoutes.adminCategories),
          ),
        ],
      ),
      bottomNavigationBar: navFor(ref, NavTab.services),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.adminServiceNew),
        icon: const Icon(Icons.add),
        label: const Text('Add service'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  SegmentedButton<VehicleType?>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: null, label: Text('All')),
                      ButtonSegment(value: VehicleType.bike, label: Text('Bike')),
                      ButtonSegment(
                        value: VehicleType.scooter,
                        label: Text('Scooter'),
                      ),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (selection) =>
                        setState(() => _filter = selection.first),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('admin-service-search'),
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                    decoration: const InputDecoration(
                      hintText: 'Search services...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ],
              ),
            ),
            if (categories.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _chip('All', _categoryId == null, () {
                      setState(() => _categoryId = null);
                    }),
                    for (final c in categories)
                      _chip(
                        c.isActive ? c.name : '${c.name} (off)',
                        _categoryId == c.id,
                        () => setState(() => _categoryId = c.id),
                        key: ValueKey('cat-${c.name}'),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: AsyncView<List<GarageService>>(
                value: services,
                onRetry: () => ref.invalidate(adminServicesProvider(_filter)),
                builder: (all) {
                  final items = [
                    for (final s in all)
                      if ((_categoryId == null || s.categoryId == _categoryId) &&
                          (_query.isEmpty ||
                              s.name.toLowerCase().contains(_query) ||
                              s.category.toLowerCase().contains(_query)))
                        s,
                  ];
                  if (items.isEmpty) {
                    return EmptyView(
                      message: all.isEmpty
                          ? 'No services yet. Tap "Add service" to create one.'
                          : 'No services match.',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.refresh(adminServicesProvider(_filter).future),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                      itemCount: items.length,
                      itemBuilder: (context, index) => _AdminServiceCard(
                        service: items[index],
                        index: index,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {Key? key}) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          key: key,
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      );
}

/// The customer's [ServiceCard] with the admin's controls under it.
class _AdminServiceCard extends ConsumerWidget {
  const _AdminServiceCard({required this.service, required this.index});

  final GarageService service;
  final int index;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action, {
    String? done,
  }) async {
    try {
      await action();
      refreshCatalog(ref);
      if (done != null && context.mounted) showSnack(context, done);
    } catch (error) {
      if (context.mounted) showErrorSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(catalogRepositoryProvider);
    final id = service.id;
    final controls = Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (!service.isActive)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: InactiveBadge(),
            ),
          IconButton(
            key: ValueKey('preview-$id'),
            tooltip: 'Preview as customer',
            icon: const Icon(Icons.visibility_outlined),
            onPressed: () => context.push(AppRoutes.adminServicePreview(id)),
          ),
          IconButton(
            key: ValueKey('edit-$id'),
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push(AppRoutes.adminServiceEdit(id)),
          ),
          IconButton(
            key: ValueKey('duplicate-$id'),
            tooltip: 'Duplicate',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () => _run(
              context,
              ref,
              () => repo.duplicateService(id),
              done: 'Copy created (switched off).',
            ),
          ),
          IconButton(
            key: ValueKey('delete-$id'),
            tooltip: service.systemKey != null
                ? 'Built-in services cannot be deleted'
                : 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: service.systemKey != null
                ? null
                : () async {
                    final ok = await confirmAction(
                      context,
                      title: 'Delete service?',
                      message: 'Delete "${service.name}" with its packages and '
                          'pictures? This cannot be undone.',
                    );
                    if (!ok || !context.mounted) return;
                    await _run(
                      context,
                      ref,
                      () => repo.deleteService(id),
                      done: 'Service deleted.',
                    );
                  },
          ),
          ActiveSwitch(
            value: service.isActive,
            semanticLabel: '${service.name} active',
            onChanged: (value) async {
              await repo.updateService(id, {'is_active': value});
              refreshCatalog(ref);
            },
          ),
        ],
      ),
    );
    return Opacity(
      opacity: service.isActive ? 1 : 0.7,
      child: ServiceCard(
        service: service,
        adminControls: controls,
        onOpen: () => context.push(AppRoutes.adminService(id)),
      ),
    );
  }
}
