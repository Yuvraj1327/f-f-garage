import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_nav.dart';
import '../../../core/widgets/content_width.dart';
import 'driver_job_list.dart';

/// The driver's "History" tab: bookings they have finished or that were
/// cancelled.
class DriverHistoryScreen extends ConsumerWidget {
  const DriverHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      bottomNavigationBar: navFor(ref, NavTab.history),
      body: const SafeArea(
        child: ContentWidth(child: DriverJobList(scope: 'history')),
      ),
    );
  }
}
