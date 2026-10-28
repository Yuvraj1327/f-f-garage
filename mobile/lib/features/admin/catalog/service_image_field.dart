import 'package:flutter/material.dart';

import '../../../core/media/image_picker_service.dart';

/// One picture of a service (banner or square thumbnail): a preview and the
/// buttons to pick from the gallery, take a photo, replace or remove it.
class ServiceImageSlot extends StatelessWidget {
  const ServiceImageSlot({
    super.key,
    required this.idKey,
    required this.title,
    required this.helper,
    required this.aspectRatio,
    required this.url,
    required this.uploading,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  /// Prefix of the widget keys: `<idKey>-gallery`, `-camera`, `-remove`, `-preview`.
  final String idKey;
  final String title;
  final String helper;
  final double aspectRatio;
  final String? url;
  final bool uploading;
  final bool enabled;
  final ValueChanged<PickSource> onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final has = url != null;
    final off = !enabled || uploading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: textTheme.titleSmall),
        Text(helper, style: textTheme.bodySmall),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: aspectRatio == 1 ? 160 : 400),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: uploading
                    ? const Center(child: CircularProgressIndicator())
                    : has
                        ? Image.network(
                            url!,
                            key: ValueKey('$idKey-preview'),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.image_outlined, size: 36),
                          ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              key: ValueKey('$idKey-gallery'),
              onPressed: off ? null : () => onPick(PickSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(has ? 'Replace' : 'Gallery'),
            ),
            OutlinedButton.icon(
              key: ValueKey('$idKey-camera'),
              onPressed: off ? null : () => onPick(PickSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Camera'),
            ),
            if (has)
              TextButton.icon(
                key: ValueKey('$idKey-remove'),
                onPressed: off ? null : onRemove,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove'),
              ),
          ],
        ),
      ],
    );
  }
}

/// The part pictures of a service: a row of small squares with a remove
/// button on each, and Gallery / Camera buttons while there is room.
class PartImagesField extends StatelessWidget {
  const PartImagesField({
    super.key,
    required this.urls,
    required this.max,
    required this.uploading,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  final List<String> urls;
  final int max;
  final bool uploading;
  final bool enabled;
  final ValueChanged<PickSource> onPick;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final off = !enabled || uploading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Part pictures (${urls.length}/$max)', style: textTheme.titleSmall),
        Text('Pictures of the parts the service uses.',
            style: textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < urls.length; i++)
              Stack(
                key: ValueKey('part-$i'),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      urls[i],
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        width: 72,
                        height: 72,
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: InkWell(
                      key: ValueKey('part-remove-$i'),
                      onTap: off ? null : () => onRemove(i),
                      child: const CircleAvatar(
                        radius: 11,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            if (uploading)
              const SizedBox(
                width: 72,
                height: 72,
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
        if (urls.length < max) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('part-gallery'),
                onPressed: off ? null : () => onPick(PickSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('part-camera'),
                onPressed: off ? null : () => onPick(PickSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Camera'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
