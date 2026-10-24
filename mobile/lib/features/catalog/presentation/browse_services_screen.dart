import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/enums.dart';
import '../providers/catalog_providers.dart';

/// Customers browse active services, bike or scooter.
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

class _ServiceList extends ConsumerWidget {
  const _ServiceList({required this.type});

  final VehicleType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        return RefreshIndicator(
          onRefresh: () => ref.refresh(browseServicesProvider(type).future),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: services.length,
            itemBuilder: (context, index) =>
                _ServiceCard(service: services[index]),
          ),
        );
      },
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
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(AppRoutes.serviceDetail(service.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ExcludeSemantics(
                child: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor:
                      Theme.of(context).colorScheme.onPrimaryContainer,
                  child: const Icon(Icons.build_outlined),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(service.name, style: textTheme.titleMedium),
                    Text(service.category, style: textTheme.bodySmall),
                    if (service.description != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        service.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (from != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('from', style: textTheme.bodySmall),
                      Text(formatMoney(from), style: textTheme.titleMedium),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
