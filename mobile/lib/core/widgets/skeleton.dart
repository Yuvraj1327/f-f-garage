import 'package:flutter/material.dart';

/// A static grey placeholder block. Deliberately not animated: it keeps the
/// layout steady while data loads and never keeps the frame pipeline busy.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A card-shaped placeholder with a title line and two text lines.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 160, height: 18),
            SizedBox(height: 12),
            SkeletonBox(height: 12),
            SizedBox(height: 8),
            SkeletonBox(width: 220, height: 12),
          ],
        ),
      ),
    );
  }
}

/// Placeholder list shown instead of a spinner on list screens.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: count,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, __) => const SkeletonCard(),
        ),
      ),
    );
  }
}
