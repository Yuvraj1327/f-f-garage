import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/filter_pill.dart';
import '../../../core/widgets/service_icon.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/enums.dart';
import '../providers/catalog_providers.dart';

/// "Select Service": the active services, by vehicle type, with a search box
/// and category chips. All data comes from the catalogue API.
class BrowseServicesScreen extends StatelessWidget {
  const BrowseServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Our services'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Scooter'), Tab(text: 'Bike')],
          ),
        ),
        body: const SafeArea(
          child: TabBarView(
            children: [
              _ServiceList(type: VehicleType.scooter),
              _ServiceList(type: VehicleType.bike),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceList extends ConsumerStatefulWidget {
  const _ServiceList({required this.type});

  final VehicleType type;

  @override
  ConsumerState<_ServiceList> createState() => _ServiceListState();
}

class _ServiceListState extends ConsumerState<_ServiceList>
    with AutomaticKeepAliveClientMixin {
  String _query = '';
  String? _category;

  @override
  bool get wantKeepAlive => true;

  List<GarageService> _filter(List<GarageService> services) {
    final query = _query.trim().toLowerCase();
    return [
      for (final service in services)
        if ((_category == null || service.category == _category) &&
            (query.isEmpty ||
                service.name.toLowerCase().contains(query) ||
                service.category.toLowerCase().contains(query) ||
                (service.description ?? '').toLowerCase().contains(query)))
          service,
    ];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final type = widget.type;
    final value = ref.watch(browseServicesProvider(type));
    return AsyncView<List<GarageService>>(
      value: value,
      loading: const ListSkeleton(),
      onRetry: () => ref.invalidate(browseServicesProvider(type)),
      builder: (services) {
        if (services.isEmpty) {
          return EmptyView(
            icon: Icons.build_outlined,
            message: 'No ${vehicleLabel(type).toLowerCase()} services are '
                'available right now. Please check back soon.',
          );
        }
        final categories = {for (final s in services) s.category}.toList()
          ..sort();
        // A category that no longer exists after a refresh falls back to All.
        final selected = categories.contains(_category) ? _category : null;
        final shown = _filter(services);
        return RefreshIndicator(
          onRefresh: () => ref.refresh(browseServicesProvider(type).future),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search services...',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              if (categories.length > 1) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _CategoryChip(
                        label: 'All',
                        selected: selected == null,
                        onTap: () => setState(() => _category = null),
                      ),
                      for (final category in categories)
                        _CategoryChip(
                          label: category,
                          selected: selected == category,
                          onTap: () => setState(() => _category = category),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (shown.isEmpty)
                // Not EmptyView: that scrolls itself and cannot sit in a list.
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 40,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No services match your search.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                )
              else
                for (final service in shown) _ServiceCard(service: service),
            ],
          ),
        );
      },
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterPill(label: label, selected: selected, onSelected: onTap),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service});

  final GarageService service;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final from = service.startingPrice;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.serviceDetail(service.id)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ServiceThumb(category: service.category),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(service.name, style: textTheme.titleMedium),
                    Text(service.category, style: textTheme.bodySmall),
                    if (service.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        service.description!,
                        style: textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (from != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('from', style: textTheme.bodySmall),
                      Text(
                        formatMoney(from),
                        style: textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
