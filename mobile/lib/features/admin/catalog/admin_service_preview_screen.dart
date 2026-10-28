import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/async_view.dart';
import '../../../data/models/catalog.dart';
import '../../catalog/presentation/service_detail_screen.dart';
import '../providers/admin_providers.dart';

/// A saved service exactly as customers see its details page (even while it is
/// switched off), with the Add buttons turned off.
class AdminServicePreviewScreen extends ConsumerWidget {
  const AdminServicePreviewScreen({super.key, required this.serviceId});

  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminServiceProvider(serviceId));
    return Scaffold(
      appBar: AppBar(title: const Text('Preview as customer')),
      body: SafeArea(
        child: AsyncView<GarageService>(
          value: value,
          onRetry: () => ref.invalidate(adminServiceProvider(serviceId)),
          builder: (service) => ServiceDetailView(service: service, preview: true),
        ),
      ),
    );
  }
}
