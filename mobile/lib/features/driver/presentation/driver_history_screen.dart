import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_nav.dart';
import 'driver_job_list.dart';

/// The driver's "History" tab: bookings they have finished.
class DriverHistoryScreen extends ConsumerWidget {
  const DriverHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      bottomNavigationBar: navFor(ref, NavTab.history),
      body: const SafeArea(child: DriverJobList(scope: 'history')),
    );
  }
}
