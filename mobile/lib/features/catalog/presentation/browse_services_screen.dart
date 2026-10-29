import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/enums.dart';
import '../../booking/presentation/cart_bar.dart';
import '../../vehicles/presentation/vehicle_switcher.dart';
import '../providers/catalog_providers.dart';
import 'service_card.dart';

/// "2-Wheeler Services": the customer's vehicle, a search box and four tabs
/// (Book a Mechanic, Service Packages, Specific Repair, Engine Repair). Every
/// price comes from the catalogue API. A sticky bar appears once a service is
/// added.
class BrowseServicesScreen extends ConsumerStatefulWidget {
  const BrowseServicesScreen({super.key, this.initialQuery = ''});

  /// A search typed on Home.
  final String initialQuery;

  @override
  ConsumerState<BrowseServicesScreen> createState() =>
      _BrowseServicesScreenState();
}

class _BrowseServicesScreenState extends ConsumerState<BrowseServicesScreen> {
  late final TextEditingController _search =
      TextEditingController(text: widget.initialQuery);
  late String _query = widget.initialQuery;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = ref.watch(catalogVehicleTypeProvider);
    final services = ref.watch(browseServicesProvider(type));
    return DefaultTabController(
      length: CatalogTab.values.length,
      // Opens on "Book a Mechanic", which holds the 3 default services.
      initialIndex: CatalogTab.values.indexOf(CatalogTab.mechanic),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('2-Wheeler Services'),
          actions: const [CartIconButton()],
        ),
        bottomNavigationBar: const CartBar(),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  children: [
                    const VehicleSwitcher(),
                    const SizedBox(height: 10),
                    TextField(
                      key: const ValueKey('service-search'),
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Search services...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() {
                                  _search.clear();
                                  _query = '';
                                }),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [for (final tab in CatalogTab.values) Tab(text: tab.label)],
              ),
              Expanded(
                child: AsyncView<List<GarageService>>(
                  value: services,
                  loading: const ListSkeleton(),
                  onRetry: () => ref.invalidate(browseServicesProvider(type)),
                  builder: (all) => TabBarView(
                    children: [
                      for (final tab in CatalogTab.values)
                        _CatalogTabView(
                          tab: tab,
                          type: type,
                          all: all,
                          query: _query,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogTabView extends ConsumerStatefulWidget {
  const _CatalogTabView({
    required this.tab,
    required this.type,
    required this.all,
    required this.query,
  });

  final CatalogTab tab;
  final VehicleType type;
  final List<GarageService> all;
  final String query;

  @override
  ConsumerState<_CatalogTabView> createState() => _CatalogTabViewState();
}

class _CatalogTabViewState extends ConsumerState<_CatalogTabView>
    with AutomaticKeepAliveClientMixin {
  String? _group;

  @override
  bool get wantKeepAlive => true;

  bool _matches(GarageService s, String query) =>
      query.isEmpty ||
      s.name.toLowerCase().contains(query) ||
      s.category.toLowerCase().contains(query) ||
      (s.repairGroup ?? '').toLowerCase().contains(query) ||
      (s.shortDescription ?? '').toLowerCase().contains(query) ||
      (s.description ?? '').toLowerCase().contains(query);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final query = widget.query.trim().toLowerCase();
    final inTab = [
      for (final s in widget.all)
        if (s.catalogTab == widget.tab) s,
    ];
    if (inTab.isEmpty) {
      return RefreshIndicator(
        onRefresh: () =>
            ref.refresh(browseServicesProvider(widget.type).future),
        child: ListView(
          children: [
            const SizedBox(height: 48),
            EmptyBlock(
              icon: Icons.build_outlined,
              message: 'No ${widget.tab.label.toLowerCase()} services for '
                  '${vehicleLabel(widget.type).toLowerCase()}s yet. '
                  'Please check back soon.',
            ),
          ],
        ),
      );
    }
    final isRepair = widget.tab == CatalogTab.repair;
    final groups = isRepair
        ? _orderedGroups(
            {
              for (final s in inTab)
                if (s.repairGroup != null) s.repairGroup!,
            },
            ref.watch(categoriesProvider).valueOrNull ?? const [],
          )
        : const <String>[];
    final selected = groups.contains(_group) ? _group : null;
    final shown = [
      for (final s in inTab)
        if ((selected == null || s.repairGroup == selected) &&
            _matches(s, query))
          s,
    ];
    final list = RefreshIndicator(
      onRefresh: () =>
          ref.refresh(browseServicesProvider(widget.type).future),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(12),
        children: [
          if (shown.isEmpty)
            const EmptyBlock(
              icon: Icons.search_off,
              message: 'No services match your search.',
            )
          else
            for (final service in shown) ServiceCard(service: service),
        ],
      ),
    );
    if (!isRepair || groups.isEmpty) return list;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GroupRail(
          groups: groups,
          selected: selected,
          onSelected: (g) => setState(() => _group = g),
        ),
        Expanded(child: list),
      ],
    );
  }
}

/// Repair groups in the admin's category order; unknown ones go last, A-Z.
List<String> _orderedGroups(Set<String> names, List<ServiceCategory> ordered) {
  final rank = {
    for (var i = 0; i < ordered.length; i++) ordered[i].name.toLowerCase(): i,
  };
  final list = names.toList();
  list.sort((a, b) {
    final ra = rank[a.toLowerCase()] ?? 100000;
    final rb = rank[b.toLowerCase()] ?? 100000;
    return ra != rb ? ra.compareTo(rb) : a.compareTo(b);
  });
  return list;
}

/// The left rail of repair categories (Brakes, Cables, Battery ...).
class _GroupRail extends StatelessWidget {
  const _GroupRail({
    required this.groups,
    required this.selected,
    required this.onSelected,
  });

  final List<String> groups;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget item(String label, bool on, VoidCallback onTap) => InkWell(
          key: ValueKey('group-$label'),
          onTap: onTap,
          child: Container(
            width: 88,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            decoration: BoxDecoration(
              color: on ? scheme.primaryContainer : null,
              border: Border(
                left: BorderSide(
                  width: 3,
                  color: on ? scheme.primary : Colors.transparent,
                ),
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    color: on ? scheme.primary : scheme.onSurface,
                  ),
            ),
          ),
        );
    return SizedBox(
      width: 88,
      child: ListView(
        children: [
          item('All', selected == null, () => onSelected(null)),
          for (final group in groups)
            item(group, selected == group, () => onSelected(group)),
        ],
      ),
    );
  }
}

/// A centred icon and message that can sit inside a list.
class EmptyBlock extends StatelessWidget {
  const EmptyBlock({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}
